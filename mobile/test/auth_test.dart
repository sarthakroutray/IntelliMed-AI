import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intellimed_app/auth.dart';

/// Builds an unsigned JWT-shaped string. Signatures are never verified
/// client-side, so a placeholder third segment is sufficient.
String fakeJwt({required Map<String, dynamic> payload}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.sig';
}

String jwtExpiringIn(Duration d) => fakeJwt(
  payload: {
    'sub': 'patient@example.com',
    'role': 'patient',
    'exp': DateTime.now().toUtc().add(d).millisecondsSinceEpoch ~/ 1000,
  },
);

class _FakeProvider implements IdTokenProvider {
  _FakeProvider({this.idToken, this.silent});

  String? idToken;
  String? silent;
  bool initialized = false;
  bool signedOutCalled = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<String?> signIn() async => idToken;

  @override
  Future<String?> silentIdToken() async => silent;

  @override
  Future<void> signOut() async => signedOutCalled = true;
}

class _MemoryStore implements TokenStore {
  _MemoryStore([this.value]);

  String? value;
  int clears = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;

  @override
  Future<void> clear() async {
    value = null;
    clears++;
  }
}

/// Backend `/api/v1/auth/google-login` responder.
http.Client _authClient({int status = 200, String? body}) {
  return MockClient(
    (request) async =>
        http.Response(body ?? jsonEncode({'access_token': jwtExpiringIn(const Duration(hours: 1))}), status),
  );
}

AuthService _service({
  String? stored,
  String devToken = '',
  String? idToken = 'google-id-token',
  String? silent,
  http.Client? client,
  _MemoryStore? store,
  _FakeProvider? provider,
}) {
  return AuthService(
    baseUrl: 'http://localhost:8000',
    webClientId: 'web-client-id',
    provider: provider ?? _FakeProvider(idToken: idToken, silent: silent),
    store: store ?? _MemoryStore(stored),
    client: client ?? _authClient(),
    devToken: devToken,
  );
}

void main() {
  group('JWT helpers', () {
    test('decodes the payload of a well-formed token', () {
      final jwt = fakeJwt(payload: {'sub': 'a@b.com', 'exp': 123});
      expect(decodeJwtPayload(jwt)?['sub'], 'a@b.com');
      expect(jwtEmail(jwt), 'a@b.com');
    });

    test('returns null for malformed tokens instead of throwing', () {
      expect(decodeJwtPayload('not-a-jwt'), isNull);
      expect(decodeJwtPayload('a.!!!not-base64!!!.c'), isNull);
      expect(jwtEmail('garbage'), isNull);
    });

    test('treats a past exp as expired and a future exp as valid', () {
      expect(isJwtExpired(jwtExpiringIn(const Duration(minutes: -5))), isTrue);
      expect(isJwtExpired(jwtExpiringIn(const Duration(hours: 1))), isFalse);
    });

    test('repairs base64url without padding', () {
      // Our encoder strips "="; normalisation must restore it.
      final jwt = jwtExpiringIn(const Duration(hours: 2));
      expect(jwt.contains('='), isFalse);
      expect(isJwtExpired(jwt), isFalse);
    });

    test('a token with no exp is not force-expired', () {
      // The backend stays the authority; failing closed here would lock the
      // user out of offline capture on a token the server may still accept.
      expect(isJwtExpired(fakeJwt(payload: {'sub': 'a@b.com'})), isFalse);
    });
  });

  group('restore', () {
    test('accepts a valid stored token and exposes the email', () async {
      final store = _MemoryStore(jwtExpiringIn(const Duration(hours: 1)));
      final auth = _service(store: store);
      await auth.restore();

      expect(auth.isSignedIn, isTrue);
      expect(auth.state.value, AuthState.signedIn);
      expect(auth.email.value, 'patient@example.com');
      expect(store.clears, 0);
    });

    test('clears an expired stored token and falls back to signed out',
        () async {
      final store = _MemoryStore(jwtExpiringIn(const Duration(minutes: -1)));
      final auth = _service(store: store);
      await auth.restore();

      expect(auth.isSignedIn, isFalse);
      expect(auth.state.value, AuthState.signedOut);
      expect(store.clears, 1);
      expect(store.value, isNull);
    });

    test('prefers a stored token over the dev override', () async {
      final stored = jwtExpiringIn(const Duration(hours: 1));
      final auth = _service(
        store: _MemoryStore(stored),
        devToken: jwtExpiringIn(const Duration(hours: 3)),
      );
      await auth.restore();
      expect(auth.token, stored);
    });

    test('uses the dev override when nothing is stored', () async {
      final dev = jwtExpiringIn(const Duration(hours: 3));
      final auth = _service(store: _MemoryStore(), devToken: dev);
      await auth.restore();
      expect(auth.token, dev);
      expect(auth.state.value, AuthState.signedIn);
    });

    test('ignores an expired dev override', () async {
      final auth = _service(
        store: _MemoryStore(),
        devToken: jwtExpiringIn(const Duration(minutes: -1)),
      );
      await auth.restore();
      expect(auth.isSignedIn, isFalse);
    });
  });

  group('signIn', () {
    test('exchanges the id token at the frozen v1 route as a patient',
        () async {
      Uri? called;
      Map<String, dynamic>? sent;
      final client = MockClient((request) async {
        called = request.url;
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'access_token': jwtExpiringIn(const Duration(hours: 1)),
            'token_type': 'bearer',
          }),
          200,
        );
      });
      final store = _MemoryStore();
      final auth = _service(client: client, store: store);

      await auth.signIn();

      expect(called?.path, '/api/v1/auth/google-login');
      expect(sent?['token'], 'google-id-token');
      expect(sent?['role'], 'patient');
      expect(auth.state.value, AuthState.signedIn);
      // Persisted for the next launch so offline capture works.
      expect(store.value, isNotNull);
      expect(auth.email.value, 'patient@example.com');
    });

    test('maps a 403 to a wrong-role failure', () async {
      final auth = _service(
        client: MockClient((_) async => http.Response('{}', 403)),
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.wrongRole,
          ),
        ),
      );
      expect(auth.state.value, AuthState.signedOut);
    });

    test('maps a transport failure to offline', () async {
      final auth = _service(
        client: MockClient(
          (_) async => throw http.ClientException('no route to host'),
        ),
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.offline,
          ),
        ),
      );
    });

    test('fails cleanly when Google returns no id token', () async {
      final auth = _service(idToken: null);
      await expectLater(auth.signIn(), throwsA(isA<AuthException>()));
      expect(auth.isSignedIn, isFalse);
    });

    test('does not persist a token when the exchange fails', () async {
      final store = _MemoryStore();
      final auth = _service(
        client: MockClient((_) async => http.Response('{}', 500)),
        store: store,
      );
      await expectLater(auth.signIn(), throwsA(isA<AuthException>()));
      expect(store.value, isNull);
    });
  });

  group('refresh', () {
    test('returns a fresh token on success', () async {
      final fresh = jwtExpiringIn(const Duration(hours: 1));
      final auth = _service(
        silent: 'silent-id-token',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'access_token': fresh}),
            200,
          ),
        ),
      );
      await expectLater(auth.refresh(), completion(fresh));
      expect(auth.state.value, AuthState.signedIn);
    });

    test('returns null and flags sessionExpired when silent auth is silent',
        () async {
      final auth = _service(silent: null);
      await expectLater(auth.refresh(), completion(isNull));
      expect(auth.state.value, AuthState.sessionExpired);
    });

    test('never throws when the exchange fails', () async {
      final auth = _service(
        silent: 'silent-id-token',
        client: MockClient((_) async => http.Response('{}', 500)),
      );
      await expectLater(auth.refresh(), completion(isNull));
      expect(auth.state.value, AuthState.sessionExpired);
    });
  });

  group('GoogleIdTokenProvider config guard', () {
    test('throws a clear notConfigured error when serverClientId is empty',
        () async {
      // Empty client ID must fail before touching the Google plugin, so the
      // user gets an actionable message instead of an opaque plugin error.
      final provider = GoogleIdTokenProvider(serverClientId: '');
      await expectLater(
        provider.initialize(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.notConfigured,
          ),
        ),
      );
    });

    test('the message names the define the user must set', () async {
      final provider = GoogleIdTokenProvider(serverClientId: '');
      try {
        await provider.initialize();
        fail('expected AuthException');
      } on AuthException catch (e) {
        expect(e.message, contains('GOOGLE_WEB_CLIENT_ID'));
      }
    });
  });

  group('signOut', () {
    test('clears the token, email and stored value', () async {
      final store = _MemoryStore(jwtExpiringIn(const Duration(hours: 1)));
      final provider = _FakeProvider(idToken: 'x');
      final auth = _service(store: store, provider: provider);
      await auth.restore();
      expect(auth.isSignedIn, isTrue);

      await auth.signOut();

      expect(auth.isSignedIn, isFalse);
      expect(auth.token, isNull);
      expect(auth.email.value, isNull);
      expect(store.value, isNull);
      expect(provider.signedOutCalled, isTrue);
      expect(auth.state.value, AuthState.signedOut);
    });
  });
}
