// Date/time formatting shared across screens.

import 'package:intl/intl.dart';

String formatDateTime(DateTime? value) {
  if (value == null) return 'Unknown date';
  return DateFormat('d MMM yyyy, HH:mm').format(value);
}

String formatDate(DateTime? value) {
  if (value == null) return '—';
  return DateFormat('d MMM yyyy').format(value);
}

/// "2 hours ago" style label for recent-activity lists, falling back to an
/// absolute date once it stops being useful.
String formatRelative(DateTime? value) {
  if (value == null) return 'Unknown';
  final now = DateTime.now();
  final diff = now.difference(value);
  if (diff.isNegative) return formatDateTime(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return formatDate(value);
}

/// Human label for a document/report kind.
String kindLabel(String kind) {
  switch (kind) {
    case 'lab_report':
      return 'Lab report';
    case 'prescription':
      return 'Prescription';
    case 'xray':
      return 'X-ray';
    case 'document':
      return 'Document';
    default:
      return kind.isEmpty ? 'Result' : kind;
  }
}
