import 'package:flutter/material.dart';

import 'auth.dart';
import 'login_screen.dart';
import 'model_manager.dart';
import 'sync.dart';
import 'tabs_bench_spike.dart';
import 'tabs_capture_results.dart';
import 'theme.dart';
import 'widgets/app_drawer.dart';
import 'widgets/brand_mark.dart';

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
  final models = ModelManager(
    cnnAsset: cnnModelAsset,
    slmGgufAsset: slmGgufAsset,
    eagerLoad: eagerModelLoad,
  );
  await models.init();
  final auth = AuthService(
    baseUrl: apiBaseUrl,
    webClientId: googleWebClientId,
    devToken: devAuthToken,
  );
  // Configure Google Sign-In and restore any stored session before the first
  // frame, so a returning user starts signed in and can capture offline.
  await auth.initialize().catchError((_) {});
  await auth.restore();
  final sync = V2Sync(
    baseUrl: apiBaseUrl,
    token: auth.token,
    // One silent re-auth when the JWT lapses; V2Sync adopts the new token.
    onUnauthorized: auth.refresh,
  );
  V2Sync.watchConnectivity(() => sync.retryQueued());
  runApp(IntelliMedApp(models: models, sync: sync, auth: auth));
}

class IntelliMedApp extends StatefulWidget {
  const IntelliMedApp({
    super.key,
    required this.models,
    required this.sync,
    required this.auth,
  });

  final ModelManager models;
  final V2Sync sync;
  final AuthService auth;

  @override
  State<IntelliMedApp> createState() => _IntelliMedAppState();
}

class _IntelliMedAppState extends State<IntelliMedApp> {
  @override
  void dispose() {
    // Models outlive the signed-in UI: signing out must NOT dispose them, or
    // signing back in would reuse a closed manager. The root widget owns them
    // for the whole process lifetime.
    widget.models.dispose();
    widget.auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IntelliMed On-Device',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
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
          );
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.models,
    required this.sync,
    required this.auth,
  });

  final ModelManager models;
  final V2Sync sync;
  final AuthService auth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _resultsToken = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CaptureTab(
        models: widget.models,
        sync: widget.sync,
        onResultsChanged: () => setState(() => _resultsToken++),
      ),
      ResultsTab(
        refreshToken: _resultsToken,
        sync: widget.sync,
        auth: widget.auth,
      ),
      BenchTab(models: widget.models, sync: widget.sync),
      SpikeTab(models: widget.models),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            BrandMark(size: 26),
            SizedBox(width: 10),
            Text('IntelliMed-AI'),
          ],
        ),
      ),
      drawer: AppDrawer(
        selectedIndex: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
      body: pages[_index],
    );
  }
}
