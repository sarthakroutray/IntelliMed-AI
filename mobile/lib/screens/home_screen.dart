import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../copy.dart';
import '../formatting.dart';
import '../model_manager.dart';
import '../store.dart';
import '../sync.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/stat_card.dart';
import 'capture_detail_screen.dart';
import 'patient_summary_screen.dart';
import 'trends_screen.dart';

/// Patient dashboard: real counts, quick actions, connected doctors and the
/// most recent on-device captures.
///
/// Server data and local data are loaded independently — the local store still
/// renders when the backend is unreachable, which matters because the app is
/// offline-first.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.models,
    required this.sync,
    required this.refreshToken,
    required this.isActive,
    required this.onNavigate,
  });

  final PatientRepository repository;
  final ModelManager models;
  final V2Sync sync;
  final int refreshToken;

  /// Whether this is the tab currently shown. Inactive tabs skip loading so a
  /// change on one screen never refetches the others in the background.
  final bool isActive;

  /// Switch bottom-nav destination (1 = Capture, 3 = Docs, 4 = Me).
  final ValueChanged<int> onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _serverError;

  Profile? _profile;
  List<LabReport> _reports = const [];
  List<DocumentSummary> _documents = const [];
  List<LinkedDoctor> _doctors = const [];
  List<Map<String, Object?>> _recent = const [];
  Map<String, int> _counts = const {};

  int _seenToken = -1;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A tab only reloads when the shared token moved past what it last saw.
    // Deferred changes surface the next time the tab is shown, and simply
    // switching tabs never triggers a refetch.
    if (widget.isActive && widget.refreshToken != _seenToken) _load();
  }

  Future<void> _load() async {
    _seenToken = widget.refreshToken;
    if (mounted) setState(() => _loading = true);

    // Local first: publish what is on the device immediately so the dashboard
    // is usable without waiting on the network. `_loading` deliberately stays
    // true until the server responds, so an empty local store keeps showing the
    // loading state rather than flashing "no captures".
    final store = await ResultStore.instance();
    final local = await Future.wait([
      store.counts(),
      store.all(limit: 3),
    ]);
    if (mounted) {
      setState(() {
        _counts = local[0] as Map<String, int>;
        _recent = local[1] as List<Map<String, Object?>>;
      });
    } else {
      return;
    }

    Profile? profile;
    var reports = <LabReport>[];
    var documents = <DocumentSummary>[];
    var doctors = <LinkedDoctor>[];
    String? serverError;

    try {
      final results = await Future.wait([
        widget.repository.getProfile(),
        widget.repository.listLabReports(),
        widget.repository.listDocuments(),
        widget.repository.listLinkedDoctors(),
      ]);
      profile = results[0] as Profile;
      reports = results[1] as List<LabReport>;
      documents = results[2] as List<DocumentSummary>;
      doctors = results[3] as List<LinkedDoctor>;
    } on ApiException catch (e) {
      serverError = e.kind == ApiErrorKind.unauthorized
          ? 'Your session has expired. Sign in again from Me.'
          : e.message;
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _reports = reports;
      _documents = documents;
      _doctors = doctors;
      _serverError = serverError;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = (_counts['pending'] ?? 0) + (_counts['failed'] ?? 0);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Greeting(profile: _profile),
          const SizedBox(height: 16),
          if (_serverError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InlineBanner(
                tone: BannerTone.warning,
                icon: Icons.cloud_off_outlined,
                title: 'Server unavailable',
                message: '$_serverError Showing on-device data only.',
              ),
            ),
          // Two rows of two rather than a fixed-aspect GridView: the cards then
          // take their natural height, so they cannot overflow when the user
          // has larger text enabled. IntrinsicHeight keeps each pair equal
          // height (stretch needs a bounded cross axis, which a ListView
          // child does not have).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Reports',
                    value: '${_reports.length}',
                    icon: Icons.description_outlined,
                    onTap: () => widget.onNavigate(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: 'Documents',
                    value: '${_documents.length}',
                    icon: Icons.folder_outlined,
                    onTap: () => widget.onNavigate(3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Captures',
                    value: '${_counts['total'] ?? 0}',
                    icon: Icons.document_scanner_outlined,
                    accent: AppColors.statusNeutralLightFg,
                    onTap: () => widget.onNavigate(1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: 'Pending sync',
                    value: '$pending',
                    icon: Icons.sync_outlined,
                    accent: pending > 0
                        ? AppColors.statusPendingLightFg
                        : AppColors.statusSyncedDarkFg,
                    onTap: () => widget.onNavigate(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Quick actions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => widget.onNavigate(1),
                  icon: const Icon(Icons.document_scanner, size: 18),
                  label: const Text('Capture'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onNavigate(3),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Upload'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Trends spans captures and server reports, so it opens as its own
          // screen rather than taking a sixth bottom-nav slot.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TrendsScreen(repository: widget.repository),
                ),
              ),
              icon: const Icon(Icons.show_chart, size: 18),
              label: const Text('Your values over time'),
            ),
          ),
          const SizedBox(height: 10),
          // The full-patient summary spans captures, reports and documents, so
          // it opens as its own screen too (same reasoning as Trends above).
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PatientSummaryScreen(
                    repository: widget.repository,
                    models: widget.models,
                  ),
                ),
              ),
              icon: const Icon(Icons.summarize_outlined, size: 18),
              label: const Text('Full patient summary'),
            ),
          ),
          const SizedBox(height: 20),
          _DoctorsCard(
            doctors: _doctors,
            onManage: () => widget.onNavigate(4),
          ),
          const SizedBox(height: 20),
          Text('Recent captures', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (_loading && _recent.isEmpty)
            const LoadingView()
          else if (_recent.isEmpty)
            const EmptyState(
              icon: Icons.document_scanner_outlined,
              title: 'No captures yet',
              message:
                  'Capture a document to run on-device inference. Results work '
                  'offline and sync when you reconnect.',
            )
          else
            for (final row in _recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecentCaptureTile(
                  row: row,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CaptureDetailScreen(
                          rowId: row['id'] as int,
                          models: widget.models,
                          sync: widget.sync,
                          onChanged: _load,
                        ),
                      ),
                    );
                    _load();
                  },
                ),
              ),
          const SizedBox(height: 12),
          Text(
            patternListCaption,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile?.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == null ? 'Welcome back' : 'Welcome back, $name',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 3),
        Text(
          profile == null
              ? 'Loading your account…'
              : profile!.email,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DoctorsCard extends StatelessWidget {
  const _DoctorsCard({required this.doctors, required this.onManage});

  final List<LinkedDoctor> doctors;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Connected doctors',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(onPressed: onManage, child: const Text('Manage')),
            ],
          ),
          if (doctors.isEmpty)
            Text(
              'No doctors connected yet. Generate an access code and share it '
              'with your doctor to link your records.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final doctor in doctors.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.activeNavFill,
                      child: Text(
                        doctor.initial,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        doctor.displayName,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.check_circle,
                      size: 15,
                      color: AppColors.statusSyncedDarkFg,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _RecentCaptureTile extends StatelessWidget {
  const _RecentCaptureTile({required this.row, required this.onTap});

  final Map<String, Object?> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = '${row['kind']}';
    final status = '${row['sync_status']}';

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(_iconFor(kind), size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kindLabel(kind), style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  reviewStatusLine(status),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }

  static IconData _iconFor(String kind) {
    switch (kind) {
      case 'prescription':
        return Icons.medication_outlined;
      case 'xray':
        return Icons.image_outlined;
      default:
        return Icons.science_outlined;
    }
  }
}
