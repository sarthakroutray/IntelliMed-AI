// Deterministic rendering of a structured lab document for the summariser.
//
// The T5 model is a summariser, not a structurer: feeding it the raw OCR stream
// gives it interleaved column soup and produces vague output. Rendering the
// already-extracted rows instead gives it clean input, and bounds length (the
// tokenizer truncates to ~128 tokens).
//
// Format per row, e.g.: `Hemoglobin 11.2 g/dL (ref 13-17, marked L)`.

import 'rule_engine.dart';

/// Compact, deterministic rendering of [doc]. Falls back to [fallback] (the
/// raw OCR text) when the document carries no tests, so the model still gets
/// something to summarise.
String renderLabText(LabDocument doc, {String fallback = ''}) {
  final lines = <String>[];
  for (final panel in doc.panels) {
    if (panel.tests.isEmpty) continue;
    if (panel.panelName != 'Ungrouped') lines.add(panel.panelName);
    for (final test in panel.tests) {
      lines.add(_renderTest(test));
    }
  }
  if (lines.isEmpty) return fallback;
  return lines.join('\n');
}

String _renderTest(LabTest test) {
  final buffer = StringBuffer(test.testName);
  if (test.value != null) buffer.write(' ${_formatNumber(test.value!)}');
  if (test.unit != null) buffer.write(' ${test.unit}');

  final reference = _reference(test);
  if (reference != null && test.flagInSource != null) {
    buffer.write(' (ref $reference, marked ${test.flagInSource})');
  } else if (reference != null) {
    buffer.write(' (ref $reference)');
  } else if (test.flagInSource != null) {
    buffer.write(' (marked ${test.flagInSource})');
  }
  return buffer.toString();
}

String? _reference(LabTest test) {
  if (test.rangeLow != null && test.rangeHigh != null) {
    return '${_formatNumber(test.rangeLow!)}-${_formatNumber(test.rangeHigh!)}';
  }
  if (test.rangeRaw != null) return test.rangeRaw;
  if (test.rangeLow != null) return '>= ${_formatNumber(test.rangeLow!)}';
  if (test.rangeHigh != null) return '<= ${_formatNumber(test.rangeHigh!)}';
  return null;
}

/// Trailing `.0` stripped, matching the viewer's number rendering.
String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
