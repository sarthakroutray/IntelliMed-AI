// Authentication for the on-device app.
//
// The app signs in with Google, exchanges the Google ID token for a backend
// JWT at `POST /api/v1/auth/google-login`, and stores that JWT in
// Keystore-backed encrypted storage. The JWT is what authorizes `/api/v2/*`
// sync.
//
// This is the ONE deliberate exception to the "app never talks to /api/v1"
// rule (see sync.dart): auth lives on the frozen v1 surface, and the backend
// route is used exactly as-is. Inference and result upload remain v2-only.
//
// The Android OAuth client registered in Google Cloud is matched by package
// name + signing SHA-1 and is never referenced here. The *web* client ID is
// passed as `serverClientId` so the returned idToken is audienced to the
// backend's `GOOGLE_CLIENT_ID`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Role used for `POST /api/v1/auth/google-login`. The v2 structured-ingest
/// route rejects non-patient roles, so the app always signs in as a patient.
const appAuthRole = 'patient';

/// Secure-storage key holding the backend JWT.
const _tokenKey = 'intellimed_auth_token';

// ---------------------------------------------------------------------------
// Pure JWT helpers (no plugin/network dependencies — unit-tested directly)
// ---------------------------------------------------------------------------

/// Decodes a JWT's payload segment without verifying the signature.
/// Returns null when the token is malformed. Never throws.
Map<String, dynamic>? decodeJwtPayload(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) return null;
  try {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final json = jsonDecode(decoded);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  }
}

/// Whether [jwt]'s `exp` claim has passed, with a small clock-skew allowance.
///
/// A token with no readable `exp` is treated as usable rather than expired:
/// the backend remains the authority, and a stale token surfaces as a 401 that
/// [AuthService.refresh] can recover from. Failing closed here would lock the
/// user out of offline capture for a token the server may still accept.
bool isJwtExpired(
  String jwt, {
  DateTime? now,
  Duration skew = const Duration(seconds: 30),
}) {
  final exp = decodeJwtPayload(jwt)?['exp'];
  if (exp is! int) return false;
  final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  return (now ?? DateTime.now().toUtc()).add(skew).isAfter(expiry);
}

/// The `sub` claim (the user's email) for display purposes.
String? jwtEmail(String jwt) => decodeJwtPayload(jwt)?['sub'] as String?;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

enum AuthErrorKind {
  /// The user dismissed the Google account picker — not really a failure.
  canceled,

  /// Google Sign-In isn't configured for this build/device (bad SHA-1,
  /// missing serverClientId, consent screen not set up).
  notConfigured,

  /// The Google account exists on the backend with a different role.
  wrongRole,

  /// No connectivity — sign-in requires the network.
  offline,

  /// Anything else (backend error, malformed response).
  unknown,
}

/// User-presentable auth failure.
class AuthException implements Exception {
  AuthException(this.kind, this.message);

  final AuthErrorKind kind;
  final String message;

  @override
  String toString() => 'AuthException($kind): $message';
}

// ---------------------------------------------------------------------------
// Injectable seams (the Google plugin and secure storage can't run in unit
// tests, so both are abstracted and faked in tests/)
// ---------------------------------------------------------------------------

/// Persistence for the backend JWT.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// [TokenStore] backed by Android Keystore via flutter_secure_storage.
///
/// Uses the plugin's default Android options (flutter_secure_storage 11+):
/// AES-GCM-NoPadding data encryption with RSA-OAEP-SHA256 KeyStore key
/// wrapping, and `resetOnError: true`. The older
/// `encryptedSharedPreferences` flag was removed in v10 and is no longer
/// needed — the defaults are already Keystore-backed.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _tokenKey);
}

/// Source of Google ID tokens.
abstract class IdTokenProvider {
  /// Configures the plugin. Safe to call once at startup.
  Future<void> initialize();

  /// Interactive sign-in. Returns the idToken, or null if Google returned
  /// none. Throws [AuthException] for user-cancel and config problems.
  Future<String?> signIn();

  /// Silent re-auth for an expired JWT. Returns null when no cached account
  /// is available (the user must sign in again).
  Future<String?> silentIdToken();

  Future<void> signOut();
}

/// [IdTokenProvider] backed by google_sign_in 7.x.
///
/// v7 changed shape from 6.x: `GoogleSignIn` is a singleton, `signIn()` became
/// `authenticate()`, and `initialize()` is mandatory before any UI is shown.
class GoogleIdTokenProvider implements IdTokenProvider {
  GoogleIdTokenProvider({required this.serverClientId});

  /// The **web** OAuth client ID, not the Android one.
  final String serverClientId;

  bool _initialized = false;

  GoogleSignIn get _gsi => GoogleSignIn.instance;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (serverClientId.isEmpty) {
      // Fail with something actionable rather than letting the plugin raise an
      // opaque clientConfigurationError at the account picker.
      throw AuthException(
        AuthErrorKind.notConfigured,
        'GOOGLE_WEB_CLIENT_ID is not set. Add it to mobile/.env and run with '
        '--dart-define-from-file=.env (see mobile/.env.example).',
      );
    }
    await _gsi.initialize(serverClientId: serverClientId);
    _initialized = true;
  }

  @override
  Future<String?> signIn() async {
    await initialize();
    if (!_gsi.supportsAuthenticate()) {
      throw AuthException(
        AuthErrorKind.notConfigured,
        'Google sign-in is not available on this device.',
      );
    }
    try {
      final account = await _gsi.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<String?> silentIdToken() async {
    await initialize();
    try {
      // v7 returns a nullable Future here, so the call itself can be absent.
      final pending = _gsi.attemptLightweightAuthentication();
      final account = pending == null ? null : await pending;
      return account?.authentication.idToken;
    } on GoogleSignInException {
      // A silent attempt must never surface an error to the user.
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _gsi.signOut();
    } on GoogleSignInException {
      // Local state is cleared regardless.
    }
  }

  /// v7 split config errors apart; the two config codes both mean "this build
  /// isn't registered correctly with Google".
  AuthException _mapException(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return AuthException(AuthErrorKind.canceled, 'Sign-in cancelled.');
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return AuthException(
          AuthErrorKind.notConfigured,
          'Google sign-in is not configured for this build. Check that '
          'GOOGLE_WEB_CLIENT_ID is set, and that this app\'s package name and '
          'signing certificate are registered in Google Cloud.',
        );
      default:
        return AuthException(
          AuthErrorKind.unknown,
          e.description ?? 'Google sign-in failed.',
        );
    }
  }
}

// ---------------------------------------------------------------------------
// AuthService
// ---------------------------------------------------------------------------

enum AuthState { signedOut, signingIn, signedIn, sessionExpired }

/// Owns the app's auth lifecycle: sign in, restore, refresh, sign out.
///
/// Token resolution order: stored token → [devToken] (`AUTH_TOKEN` dart-define,
/// an emulator/dev escape hatch) → none.
class AuthService {
  AuthService({
    required this.baseUrl,
    required this.webClientId,
    IdTokenProvider? provider,
    TokenStore? store,
    http.Client? client,
    this.devToken = '',
  }) : _provider =
           provider ?? GoogleIdTokenProvider(serverClientId: webClientId),
       _store = store ?? SecureTokenStore(),
       _client = client ?? http.Client();

  /// Backend origin, e.g. `http://10.0.2.2:8000` (no `/api` suffix).
  final String baseUrl;

  /// Web OAuth client ID — passed to Google as `serverClientId`.
  final String webClientId;

  /// Optional dev/emulator token from `--dart-define=AUTH_TOKEN=`.
  final String devToken;

  final IdTokenProvider _provider;
  final TokenStore _store;
  final http.Client _client;

  final ValueNotifier<AuthState> state = ValueNotifier(AuthState.signedOut);
  final ValueNotifier<String?> email = ValueNotifier(null);

  String? _token;

  /// The current backend JWT, or null when signed out.
  String? get token => _token;

  bool get isSignedIn => _token != null;

  String get _authUrl =>
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/auth/google-login';

  /// Configure the Google plugin. Does not sign anyone in.
  Future<void> initialize() => _provider.initialize();

  /// Load a usable token from secure storage (or the dev override) at startup,
  /// so a returning user can capture offline without signing in again.
  Future<void> restore() async {
    final stored = await _store.read();
    if (stored != null && stored.isNotEmpty && !isJwtExpired(stored)) {
      _accept(stored);
      return;
    }
    if (stored != null && stored.isNotEmpty) {
      // Expired: clear it and let a silent refresh try to recover.
      await _store.clear();
    }
    if (devToken.isNotEmpty && !isJwtExpired(devToken)) {
      _accept(devToken);
      return;
    }
    state.value = AuthState.signedOut;
  }

  /// Interactive Google sign-in, then exchange the ID token for a backend JWT.
  Future<void> signIn() async {
    state.value = AuthState.signingIn;
    try {
      final idToken = await _provider.signIn();
      if (idToken == null || idToken.isEmpty) {
        throw AuthException(
          AuthErrorKind.unknown,
          'Google did not return an identity token.',
        );
      }
      final jwt = await _exchange(idToken);
      await _store.write(jwt);
      _accept(jwt);
    } on AuthException {
      // Cancelling and config failures both land back on the sign-in screen;
      // the caller decides whether the message is worth showing.
      state.value = AuthState.signedOut;
      rethrow;
    } catch (_) {
      state.value = AuthState.signedOut;
      throw AuthException(
        AuthErrorKind.unknown,
        'Sign-in failed. Please try again.',
      );
    }
  }

  /// One silent re-auth attempt to replace an expired JWT. Returns the fresh
  /// token, or null when silent recovery isn't possible. Never throws.
  Future<String?> refresh() async {
    try {
      final idToken = await _provider.silentIdToken();
      if (idToken == null || idToken.isEmpty) {
        state.value = AuthState.sessionExpired;
        return null;
      }
      final jwt = await _exchange(idToken);
      await _store.write(jwt);
      _accept(jwt);
      return jwt;
    } catch (_) {
      state.value = AuthState.sessionExpired;
      return null;
    }
  }

  /// Signs out of Google and clears the stored JWT. Locally queued results are
  /// intentionally left untouched so they can sync after re-authenticating.
  Future<void> signOut() async {
    await _provider.signOut();
    await _store.clear();
    _token = null;
    email.value = null;
    state.value = AuthState.signedOut;
  }

  /// POST the Google ID token to the frozen v1 route and read back the JWT.
  Future<String> _exchange(String idToken) async {
    final http.Response resp;
    try {
      resp = await _client.post(
        Uri.parse(_authUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': idToken, 'role': appAuthRole}),
      );
    } on http.ClientException catch (_) {
      throw AuthException(
        AuthErrorKind.offline,
        'Cannot reach the backend at $baseUrl. Check the device has network '
        'access and that API_BASE_URL points at the right server.',
      );
    } on SocketException catch (_) {
      throw AuthException(
        AuthErrorKind.offline,
        'Cannot reach the backend at $baseUrl. Check the device has network '
        'access and that API_BASE_URL points at the right server.',
      );
    }

    if (resp.statusCode == 403) {
      throw AuthException(
        AuthErrorKind.wrongRole,
        'This Google account is registered with a different role. Use a '
        'patient account.',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AuthException(
        AuthErrorKind.unknown,
        'Sign-in was rejected by the server (${resp.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(resp.body);
      final token = (decoded is Map) ? decoded['access_token'] : null;
      if (token is! String || token.isEmpty) {
        throw const FormatException('missing access_token');
      }
      return token;
    } catch (_) {
      throw AuthException(
        AuthErrorKind.unknown,
        'The server returned an unexpected sign-in response.',
      );
    }
  }

  void _accept(String jwt) {
    _token = jwt;
    email.value = jwtEmail(jwt);
    state.value = AuthState.signedIn;
  }

  void dispose() {
    state.dispose();
    email.dispose();
  }
}
