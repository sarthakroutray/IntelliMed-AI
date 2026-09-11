# Memory / latency report — real-device measurements

**Rule: no resource arbiter / swap-in/swap-out work begins until this file
holds numbers from a mid-range test device.** The app ships with both models
resident + a serial inference queue; that is the whole resource strategy
until measurement proves otherwise.

## How to measure (Bench tab)

1. `flutter run --dart-define=API_BASE_URL=<backend> [--dart-define=EAGER_MODEL_LOAD=true]`
2. Open the Bench tab, paste an OCR sample (or use the default), tap **Run measurements**.
3. Record below: device model, RAM, Android version, then the harness output.

## Results

| Date | Device (RAM / Android) | CNN eager load (ms) | CNN lazy handle (ms) | CNN first classify (ms) | SLM load (ms) | Normalization (ms) | Queue max depth | Notes |
|------|------------------------|--------------------:|---------------------:|------------------------:|--------------:|-------------------:|----------------:|-------|
| _pending_ | | | | | | | | |

## Decision log

- _pending real-device numbers — arbiter work is explicitly deferred._
