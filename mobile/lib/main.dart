import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'api/patient_repository.dart';
import 'app_shell.dart';
import 'auth.dart';
import 'login_screen.dart';
import 'model_manager.dart';
import 'sync.dart';
import 'theme.dart';
import 'theme_controller.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
const cnnModelAsset = String.fromEnvironment(
  'CNN_MODEL_ASSET',
  defaultValue: 'assets/models/pneumonia_resnet50.onnx',
);
const cnnBackend = String.fromEnvironment('CNN_BACKEND', defaultValue: 'onnx');
const slmGgufAsset = String.fromEnvironment(
  'SLM_GGUF_ASSET',
  defaultValue: 'assets/models/slm_norm_q4.gguf',
);
const eagerModelLoad = bool.fromEnvironment(
  'EAGER_MODEL_LOAD',
  defaultValue: false,
);

/// Dev/emulator escape hatch. Normal sign-in goes through Google; this token
/// is only a fallback so a token can still be injected without the OAuth flow.
const devAuthToken = String.fromEnvironment('AUTH_TOKEN', defaultValue: '');

/// Web OAuth client ID (NOT the Android one). Passed to Google as
/// `serverClientId` so the idToken is audienced to the backend's
/// `GOOGLE_CLIENT_ID`.
///
/// No default: real values live in the gitignored `.env` (see `.env.example`).
/// Supply it with `--dart-define-from-file=.env` or
/// `--dart-define=GOOGLE_WEB_CLIENT_ID=...`. When unset, sign-in reports a
/// configuration error rather than failing silently.
const googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One HTTP client for the whole app, so auth, sync and the repository share a
  // single connection pool instead of each holding its own.
  final httpClient = http.Client();

  final models = ModelManager(
    cnnAsset: cnnModelAsset,
    slmGgufAsset: slmGgufAsset,
    eagerLoad: eagerModelLoad,
  );

  final themeController = ThemeController();

  final auth = AuthService(
    baseUrl: apiBaseUrl,
    webClientId: googleWebClientId,
    devToken: devAuthToken,
    client: httpClient,
  );

  // Independent work, run together so the first frame is not gated on the sum
  // of model init, two Keystore reads and the Google plugin init. `restore`
  // sets the session, so a returning user starts signed in and can capture
  // offline.
  await Future.wait([
    models.init(),
    themeController.load(),
    auth.initialize().catchError((_) {}),
    auth.restore(),
  ]);

  // One HTTP layer for all authenticated reads/writes. The token and the
  // refresh hook are read live, so they always reflect the current session.
  final apiClient = ApiClient(
    baseUrl: apiBaseUrl,
    tokenProvider: () => auth.token,
    onUnauthorized: auth.refresh,
    client: httpClient,
  );
  final repository = PatientRepository(apiClient);

  final sync = V2Sync(
    baseUrl: apiBaseUrl,
    token: auth.token,
    // One silent re-auth when the JWT lapses; V2Sync adopts the new token.
    onUnauthorized: auth.refresh,
    client: httpClient,
  );
  V2Sync.watchConnectivity(() => sync.retryQueued());

  runApp(
    IntelliMedApp(
      models: models,
      sync: sync,
      auth: auth,
      repository: repository,
      apiClient: apiClient,
      themeController: themeController,
    ),
  );
}

class IntelliMedApp extends StatefulWidget {
  const IntelliMedApp({
    super.key,
    required this.models,
    required this.sync,
    required this.auth,
    required this.repository,
    required this.apiClient,
    required this.themeController,
  });

  final ModelManager models;
  final V2Sync sync;
  final AuthService auth;
  final PatientRepository repository;
  final ApiClient apiClient;
  final ThemeController themeController;

  @override
  State<IntelliMedApp> createState() => _IntelliMedAppState();
}

class _IntelliMedAppState extends State<IntelliMedApp> {
  @override
  void dispose() {
    // Models and the shell outlive sign-in: signing out must NOT dispose the
    // model manager, or signing back in would reuse a closed one.
    widget.models.dispose();
    widget.auth.dispose();
    widget.themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.themeController,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'IntelliMed On-Device',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: ValueListenableBuilder<AuthState>(
          valueListenable: widget.auth.state,
          builder: (context, state, _) {
            if (state != AuthState.signedIn) {
              return LoginScreen(auth: widget.auth);
            }
            // Keep the sync client's token in step with the session.
            widget.sync.token = widget.auth.token;
            return AppShell(
              models: widget.models,
              sync: widget.sync,
              auth: widget.auth,
              repository: widget.repository,
              themeController: widget.themeController,
            );
          },
        ),
      ),
    );
  }
}
