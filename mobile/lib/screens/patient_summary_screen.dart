import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../copy.dart';
import '../formatting.dart';
import '../model_manager.dart';
import '../patient_summary.dart';
import '../store.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/result_viewers.dart';

/// One doctor-facing summary over every stored record.
///
/// Local-first: the deterministic roll-up is built from the on-device store and
/// renders even with no network. Cloud lab reports and cloud prescriptions are
/// merged in when reachable. The written narrative is one on-device model call
/// (chunked if the records are many); if it cannot run, the facts still stand.
class PatientSummaryScreen extends StatefulWidget {
  const PatientSummaryScreen({
    super.key,
    required this.repository,
    this.models,
  });

  final PatientRepository repository;

  /// Null when there is no model manager in context — the screen then shows the
  /// deterministic facts only.
  final ModelManager? models;

  @override
  State<PatientSummaryScreen> createState() => _PatientSummaryScreenState();
}

class _PatientSummaryScreenState extends State<PatientSummaryScreen> {
  /// Cap on per-document fetches for cloud prescriptions: the backend has no
  /// prescription-list endpoint, so each one is an individual request.
  static const int _maxCloudPrescriptions = 20;

  bool _loading = true;
  bool _generating = false;
  String? _generateError;

  Profile? _profile;
  List<PatientRecord> _records = const [];
  PatientSummaryFacts? _facts;
  String? _narrative;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _generateError = null;
      });
    }

    final store = await ResultStore.instance();
    final localRows = await store.all(limit: 500);

    Profile? profile;
    var reports = <LabReport>[];
    var documents = <DocumentSummary>[];
    try {
      final results = await Future.wait([
        widget.repository.getProfile(),
        widget.repository.listLabReports(),
        widget.repository.listDocuments(),
      ]);
      profile = results[0] as Profile;
      reports = results[1] as List<LabReport>;
      documents = results[2] as List<DocumentSummary>;
    } on ApiException {
      // Offline is fine: the on-device records carry the summary.
    }

    final records = <PatientRecord>[];
    for (final row in localRows) {
      final record = _recordFromRow(row);
      if (record != null) records.add(record);
    }
    final syncedIds = syncedServerIds(localRows);
    for (final report in reports) {
      if (syncedIds.contains(report.id)) continue;
      records.add(
        PatientRecord.fromEnvelope(
          report.result,
          date: report.uploadedAt,
          sourceLabel: report.filename,
        ),
      );
    }
    records.addAll(await _cloudPrescriptions(documents));
    records.sort((a, b) {
      final da = a.date;
      final db = b.date;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _records = records;
      _facts = buildFacts(records);
      _loading = false;
    });

    await _generate();
  }

  PatientRecord? _recordFromRow(Map<String, Object?> row) {
    final envelope = decodeEnvelope('${row['result_json']}');
    if (envelope == null) return null;
    return PatientRecord.fromEnvelope(
      ResultEnvelope.fromJson(envelope),
      date: parseSqliteUtc('${row['created_at']}'),
      sourceLabel: 'This device',
    );
  }

  Future<List<PatientRecord>> _cloudPrescriptions(
    List<DocumentSummary> documents,
  ) async {
    final targets = documents
        .where((d) => d.detectedType == 'prescription')
        .take(_maxCloudPrescriptions)
        .toList();
    final records = <PatientRecord>[];
    for (final summary in targets) {
      try {
        final detail = await widget.repository.getDocument(summary.id);
        records.add(
          PatientRecord.fromDocumentAnalysis(
            detail.analysis,
            date: summary.uploadedAt,
            sourceLabel: summary.filename,
          ),
        );
      } on ApiException {
        // Best effort: skip a document that will not load.
      }
    }
    return records;
  }

  Future<void> _generate() async {
    final models = widget.models;
    if (models == null || _records.isEmpty) return;
    final cards = _records
        .map(buildRecordCard)
        .where((card) => card.trim().isNotEmpty)
        .toList();
    if (cards.isEmpty) return;

    if (mounted) setState(() => _generating = true);
    try {
      final text = await models.summarizePatient(cards);
      if (!mounted) return;
      setState(() {
        _narrative = text.isEmpty ? null : text;
        _generateError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _narrative = null;
        _generateError = '$e';
      });
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _copy() async {
    final facts = _facts;
    if (facts == null) return;
    await Clipboard.setData(
      ClipboardData(text: renderPatientSummaryText(facts, _records, _narrative)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied — paste it into a message to your doctor.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = _facts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient summary'),
        actions: [
          IconButton(
            tooltip: 'Regenerate',
            onPressed: _generating || _loading ? null : _generate,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Copy for your doctor',
            onPressed: facts == null || facts.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Gathering your records…')
          : facts == null || facts.isEmpty
          ? const _EmptySummary()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(
                  profile: _profile,
                  facts: facts,
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _NarrativeCard(
                  narrative: _narrative,
                  generating: _generating,
                  error: _generateError,
                ),
                const SizedBox(height: 16),
                _AtAGlance(facts: facts),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Copy for your doctor'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  patientSummaryDisclaimer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmptySummary extends StatelessWidget {
  const _EmptySummary();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        EmptyState(
          icon: Icons.summarize_outlined,
          title: 'No records yet',
          message:
              'Capture a prescription or lab report and its results will '
              'appear here, ready to summarise for your doctor.',
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.profile,
    required this.facts,
    required this.theme,
  });

  final Profile? profile;
  final PatientSummaryFacts facts;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? facts.name;
    final age = _ageFrom(profile?.dateOfBirth) ?? facts.age;
    final sex = profile?.gender ?? facts.sex;

    final details = <String>[
      if (age != null) 'Age ${formatNumber(age)}',
      if (sex != null && sex.trim().isNotEmpty) sex,
      if (profile?.bloodType != null && profile!.bloodType!.isNotEmpty)
        'Blood type ${profile!.bloodType}',
    ];

    final clinical = <String>[
      if (profile?.allergies != null && profile!.allergies!.isNotEmpty)
        'Allergies: ${profile!.allergies}',
      if (profile?.chronicConditions != null &&
          profile!.chronicConditions!.isNotEmpty)
        'Ongoing conditions: ${profile!.chronicConditions}',
    ];

    final counts = facts.countsByKind.entries
        .map((e) => '${e.value} ${_kindWord(e.key, e.value)}')
        .toList()
      ..sort();
    final range = facts.earliest == null || facts.latest == null
        ? ''
        : ' · ${_shortDate(facts.earliest!)} to ${_shortDate(facts.latest!)}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_ind_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name ?? 'Patient',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(details.join(' · '), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text('${counts.join(', ')}$range', style: theme.textTheme.bodySmall),
          if (clinical.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final line in clinical)
              Text(line, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text(
            patientSummaryCaption,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({
    required this.narrative,
    required this.generating,
    required this.error,
  });

  final String? narrative;
  final bool generating;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrative = this.narrative;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Summary for your doctor',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (generating)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const _Badge(label: 'AI generated'),
            ],
          ),
          const SizedBox(height: 10),
          if (generating)
            Text(
              'Reading your records on this device…',
              style: theme.textTheme.bodyMedium,
            )
          else if (narrative != null && narrative.isNotEmpty)
            SelectableText(narrative, style: theme.textTheme.bodyMedium)
          else
            Text(patientSummaryUnavailable, style: theme.textTheme.bodySmall),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            insightDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _AtAGlance extends StatelessWidget {
  const _AtAGlance({required this.facts});

  final PatientSummaryFacts facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('At a glance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(patternListCaption, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        if (facts.criticalValues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InlineBanner(
              tone: BannerTone.error,
              icon: Icons.error_outline,
              title: 'Critical values',
              message: facts.criticalValues.map((t) => t.summary).join('\n'),
            ),
          ),
        if (facts.abnormalHighlights.isNotEmpty) ...[
          _FactsCard(
            title: 'Outside printed range',
            icon: Icons.science_outlined,
            lines: facts.abnormalHighlights.map((t) => t.summary).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (facts.patterns.isNotEmpty) ...[
          _FactsCard(
            title: 'Patterns for review',
            icon: Icons.rule_folder_outlined,
            lines: [
              for (final pattern in facts.patterns)
                '${pattern.name}'
                    '${pattern.category == null || pattern.category == 'General' ? '' : ' · ${pattern.category}'}'
                    '${pattern.severity == null ? '' : ' (${pattern.severity})'}'
                    '${pattern.implication == null ? '' : ' — ${pattern.implication}'}',
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (facts.currentMeds.isNotEmpty) ...[
          PrescriptionItemsCard(
            items: [
              for (final med in facts.currentMeds)
                PrescriptionItem(
                  medication: med.medication,
                  dosage: med.dosage,
                  frequency: med.frequency,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (facts.trendHighlights.isNotEmpty) ...[
          _FactsCard(
            title: 'Changes over time',
            icon: Icons.show_chart,
            caption: patientSummaryTrendsCaption,
            lines: facts.trendHighlights,
          ),
          const SizedBox(height: 12),
        ],
        if (facts.notes.isNotEmpty)
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.info_outline,
            title: 'Notes',
            message: facts.notes.join('\n'),
          ),
      ],
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({
    required this.title,
    required this.lines,
    this.icon,
    this.caption,
  });

  final String title;
  final List<String> lines;
  final IconData? icon;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = this.caption;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

int? _ageFrom(String? dateOfBirth) {
  final date = DateTime.tryParse(dateOfBirth ?? '');
  if (date == null) return null;
  final now = DateTime.now();
  var age = now.year - date.year;
  if (now.month < date.month ||
      (now.month == date.month && now.day < date.day)) {
    age--;
  }
  return age < 0 ? null : age;
}

String _kindWord(String kind, int count) {
  final label = kindLabel(kind).toLowerCase();
  return count == 1 ? label : '${label}s';
}

String _shortDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
