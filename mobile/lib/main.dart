import 'package:flutter/material.dart';

import 'model_manager.dart';
import 'sync.dart';
import 'tabs_bench_spike.dart';
import 'tabs_capture_results.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final models = ModelManager(
    cnnAsset: cnnModelAsset,
    slmGgufAsset: slmGgufAsset,
    eagerLoad: eagerModelLoad,
  );
  await models.init();
  final sync = V2Sync(baseUrl: apiBaseUrl);
  V2Sync.watchConnectivity(() => sync.retryQueued());
  runApp(IntelliMedApp(models: models, sync: sync));
}

class IntelliMedApp extends StatefulWidget {
  const IntelliMedApp({super.key, required this.models, required this.sync});

  final ModelManager models;
  final V2Sync sync;

  @override
  State<IntelliMedApp> createState() => _IntelliMedAppState();
}

class _IntelliMedAppState extends State<IntelliMedApp> {
  int _index = 0;
  int _resultsToken = 0;

  @override
  void dispose() {
    widget.models.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CaptureTab(
        models: widget.models,
        onResultsChanged: () => setState(() => _resultsToken++),
      ),
      ResultsTab(refreshToken: _resultsToken),
      BenchTab(models: widget.models, sync: widget.sync),
      SpikeTab(models: widget.models),
    ];
    return MaterialApp(
      title: 'IntelliMed On-Device',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.teal)),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('IntelliMed — structured context for review'),
        ),
        body: pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.document_scanner),
              label: 'Capture',
            ),
            NavigationDestination(icon: Icon(Icons.list_alt), label: 'Results'),
            NavigationDestination(icon: Icon(Icons.speed), label: 'Bench'),
            NavigationDestination(icon: Icon(Icons.science), label: 'Spike'),
          ],
        ),
      ),
    );
  }
}
