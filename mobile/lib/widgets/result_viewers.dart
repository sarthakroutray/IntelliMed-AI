// Renderers for structured results.
//
// These are the screens' workhorses: they turn a ResultEnvelope (from the
// server or the local store) or a v1 DocumentAnalysis into readable UI.
//
// Wording rule (see copy.dart): everything is framed as structured context
// for a doctor to review. We describe what the document says ("printed range",
// "outside range") and never assert a diagnosis. Stage 3 marks a value
// `abnormal`, but we surface it as "outside printed range" because that is
// literally what the comparison means.

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'app_card.dart';
import 'feedback.dart';

// ---------------------------------------------------------------------------
// Lab report pieces
// ---------------------------------------------------------------------------

/// Panel header plus its test rows.
class LabPanelCard extends StatelessWidget {
  const LabPanelCard({super.key, required this.panel});

  final LabPanel panel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(panel.panelName, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          for (final test in panel.tests)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LabTestRow(test: test),
            ),
        ],
      ),
    );
  }
}

/// One test: name, value + unit, printed range, and (when the server supplied
/// Stage 3) whether it sits outside that range.
class LabTestRow extends StatelessWidget {
  const LabTestRow({super.key, required this.test});

  final LabTest test;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _valueLabel(test);
    final range = test.rangeLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Both sides flexible: the value column is unconstrained text, so a
        // long value/unit (or a wide range) would otherwise overflow the row.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test.testName, style: theme.textTheme.bodyMedium),
                  if (test.rawTestName.toLowerCase() !=
                      test.testName.toLowerCase())
                    Text(
                      'as printed: ${test.rawTestName}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: _valueColor(theme, test),
                    ),
                  ),
                  if (range != null)
                    Text(
                      'ref $range',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_needsBadge(test)) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (test.direction != null)
                _TinyBadge(
                  label: test.direction == 'low' ? 'below range' : 'above range',
                  color: theme.colorScheme.error,
                )
              else if (test.abnormal == true)
                _TinyBadge(
                  label: 'outside printed range',
                  color: theme.colorScheme.error,
                )
              else if (test.abnormal == false)
                _TinyBadge(
                  label: 'within printed range',
                  color: AppColors.statusSyncedDarkFg,
                )
              else if (!test.comparable && test.value != null)
                const _TinyBadge(
                  label: 'no range to compare',
                  color: AppColors.statusNeutralLightFg,
                ),
              if (test.flagInSource != null)
                _TinyBadge(
                  label: 'marked "${test.flagInSource}" on document',
                  color: AppColors.statusPendingLightFg,
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _valueLabel(LabTest test) {
    final parts = <String>[formatNumber(test.value)];
    if (test.unit != null) parts.add(test.unit!);
    return parts.join(' ');
  }

  /// A badge only when it says something the value alone doesn't.
  static bool _needsBadge(LabTest test) =>
      test.abnormal != null ||
      test.direction != null ||
      test.flagInSource != null ||
      (test.value != null && !test.comparable);

  static Color? _valueColor(ThemeData theme, LabTest test) {
    if (test.abnormal == true || test.direction != null) {
      return theme.colorScheme.error;
    }
    return null;
  }
}

/// A Stage 3 pattern with the exact values that triggered it.
class FlaggedPatternCard extends StatelessWidget {
  const FlaggedPatternCard({super.key, required this.pattern});

  final FlaggedPattern pattern;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.rule_folder_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(pattern.patternName, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          if (pattern.surfacedText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(pattern.surfacedText, style: theme.textTheme.bodySmall),
          ],
          if (pattern.panelName != null) ...[
            const SizedBox(height: 4),
            Text('Panel: ${pattern.panelName}', style: theme.textTheme.bodySmall),
          ],
          if (pattern.triggeringTests.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Matched on these values',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 6),
            for (final t in pattern.triggeringTests)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_right, size: 16),
                    Expanded(
                      child: Text(
                        '${t.testName} — ${t.summary}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// X-ray
// ---------------------------------------------------------------------------

/// Classifier output as labelled probability bars.
class XrayProbabilityBars extends StatelessWidget {
  const XrayProbabilityBars({super.key, required this.xray});

  final XrayResult xray;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = xray.sortedProbabilities;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Top pattern', style: theme.textTheme.titleSmall),
              ),
              _TinyBadge(
                label: xray.isNormal ? 'normal pattern' : 'review pattern',
                color: xray.isNormal
                    ? AppColors.statusSyncedDarkFg
                    : theme.colorScheme.error,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(xray.topPattern, style: theme.textTheme.bodyMedium),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProbabilityBar(
                  label: entry.key,
                  value: entry.value.toDouble(),
                ),
              ),
          ],
          if (xray.note != null) ...[
            const SizedBox(height: 6),
            Text(xray.note!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (value * 100).clamp(0, 100).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Text('$pct%', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Prescription
// ---------------------------------------------------------------------------

class PrescriptionItemsCard extends StatelessWidget {
  const PrescriptionItemsCard({super.key, required this.items});

  final List<PrescriptionItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prescribed items', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medication_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.medication, style: theme.textTheme.bodyMedium),
                        if (item.dosage != null || item.frequency != null)
                          Text(
                            [
                              if (item.dosage != null) item.dosage!,
                              if (item.frequency != null) item.frequency!,
                            ].join(' • '),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary + OCR
// ---------------------------------------------------------------------------

class SummaryContextCard extends StatelessWidget {
  const SummaryContextCard({super.key, required this.summary});

  final SummaryContext summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Standardized summary',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const _TinyBadge(
                label: 'AI generated',
                color: AppColors.primary,
              ),
            ],
          ),
          if (summary.medicalSummary != null &&
              summary.medicalSummary!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(summary.medicalSummary!, style: theme.textTheme.bodyMedium),
          ],
          if (summary.keyFindings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Key findings', style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            for (final finding in summary.keyFindings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, size: 6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(finding, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Collapsible raw OCR excerpt, kept for traceability.
class OcrExcerptCard extends StatelessWidget {
  const OcrExcerptCard({super.key, required this.text, this.title = 'Extracted text'});

  final String text;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(title, style: theme.textTheme.titleSmall),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt(theme.brightness),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composite: a full ResultEnvelope
// ---------------------------------------------------------------------------

/// Renders everything a ResultEnvelope carries, for either envelope shape
/// (server pipeline, server app-ingest, or local capture).
class ResultEnvelopeView extends StatelessWidget {
  const ResultEnvelopeView({super.key, required this.envelope});

  final ResultEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final envelope = this.envelope;

    if (envelope.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No structured content',
        message: 'This result did not include any panels, patterns or summary.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (envelope.rulesUnreviewed)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: InlineBanner(
              tone: BannerTone.warning,
              icon: Icons.science_outlined,
              title: 'Rule table not clinically reviewed',
              message:
                  'Flags come from an unreviewed placeholder rule table. Treat '
                  'them as a starting point for review, not as findings.',
            ),
          ),
        if (envelope.summaryContext != null && !envelope.summaryContext!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SummaryContextCard(summary: envelope.summaryContext!),
          ),
        if (envelope.xray != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: XrayProbabilityBars(xray: envelope.xray!),
          ),
        if (envelope.prescriptionItems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PrescriptionItemsCard(items: envelope.prescriptionItems),
          ),
        if (envelope.flaggedPatterns.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _SectionLabel(
              title: 'Patterns for review',
              subtitle:
                  'Each pattern lists the exact values that triggered it.',
            ),
          ),
          for (final pattern in envelope.flaggedPatterns)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FlaggedPatternCard(pattern: pattern),
            ),
        ],
        if (envelope.panels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SectionLabel(
              title: 'Measurements',
              subtitle: envelope.hasStage3
                  ? 'Compared against the ranges printed on the document.'
                  : 'Reference comparison not available for this record.',
            ),
          ),
          for (final panel in envelope.panels)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LabPanelCard(panel: panel),
            ),
        ],
        if (envelope.ocrExcerpt != null && envelope.ocrExcerpt!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OcrExcerptCard(text: envelope.ocrExcerpt!),
          ),
        if (envelope.warnings.isNotEmpty)
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.warning_amber_outlined,
            title: 'Extraction warnings',
            message: envelope.warnings.join('\n'),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (subtitle != null)
          Text(subtitle, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Small uppercase pill used inside result cards.
class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composite: a v1 DocumentAnalysis (server-side OCR / NLP / CV / T5)
// ---------------------------------------------------------------------------

/// Renders the `analysis` object returned by `GET /api/v1/documents/{id}`.
class DocumentAnalysisView extends StatelessWidget {
  const DocumentAnalysisView({super.key, required this.analysis});

  final DocumentAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = this.analysis;

    if (!analysis.hasContent) {
      return const EmptyState(
        icon: Icons.hourglass_empty,
        title: 'Analysis not available',
        message:
            'This document has not been analyzed yet. Run analysis to extract '
            'text and findings.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (analysis.title != null || analysis.description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          analysis.title ?? 'Analysis',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (analysis.classification != null)
                        _TinyBadge(
                          label: analysis.classification!,
                          color: (analysis.classification ?? '')
                                  .toLowerCase()
                                  .contains('normal')
                              ? AppColors.statusSyncedDarkFg
                              : theme.colorScheme.error,
                        ),
                    ],
                  ),
                  if (analysis.description != null &&
                      analysis.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      analysis.description!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (analysis.findings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Classifier output',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  for (final finding in analysis.findings)
                    if (finding.confidence != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ConfidenceBar(
                          label: finding.label,
                          percent: finding.confidence!.toDouble(),
                        ),
                      ),
                ],
              ),
            ),
          ),
        if (analysis.medicalSummary != null ||
            analysis.keyFindings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SummaryContextCard(
              summary: SummaryContext(
                medicalSummary: analysis.medicalSummary,
                keyFindings: analysis.keyFindings,
              ),
            ),
          ),
        if (analysis.medications.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Medications detected', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final med in analysis.medications)
                        Chip(label: Text(med)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (analysis.prescriptions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PrescriptionItemsCard(items: analysis.prescriptions),
          ),
        if (analysis.entities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detected entities', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  for (final entity in analysis.entities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entity.text,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          if (entity.label != null)
                            _TinyBadge(
                              label: entity.label!,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (analysis.ocrText != null && analysis.ocrText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OcrExcerptCard(
              text: analysis.ocrText!,
              title: 'Extracted text (OCR)',
            ),
          ),
      ],
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.label, required this.percent});

  final String label;

  /// Already 0..100.
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = (percent / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Text('${percent.toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(value: clamped, minHeight: 6),
        ),
      ],
    );
  }
}
