import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'auth.dart';
import 'copy.dart';
import 'model_manager.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';
import 'widgets/app_card.dart';
import 'widgets/status_chip.dart';

/// Capture tab: camera/gallery pick for prescriptions, lab reports, X-rays.
/// Handwriting capture is not offered as a path — printed documents only,
/// flagged in the UI as a scope note.
class CaptureTab extends StatefulWidget {
  const CaptureTab({
    super.key,
    required this.models,
    required this.onResultsChanged,
    this.sync,
  });

  final ModelManager models;
  final VoidCallback onResultsChanged;
  final V2Sync? sync;

  @override
  State<CaptureTab> createState() => _CaptureTabState();
}

class _CaptureTabState extends State<CaptureTab> {
  final _picker = ImagePicker();
  String _kind = 'lab_report';
  String _status = 'Pick a document to begin on-device processing.';
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _status = 'Reading image…';
    });
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 92);
      if (picked == null) {
        setState(() {
          _status = 'No image selected.';
          _busy = false;
        });
        return;
      }
      setState(() => _status = 'Running on-device inference (queued)…');
      final Map<String, dynamic> envelope;
      if (_kind == 'xray') {
        envelope = await widget.models.processXray(
          image: File(picked.path),
          sync: widget.sync,
          token: widget.sync?.token,
        );
      } else {
        envelope = await widget.models.processDocument(
          image: File(picked.path),
          kind: _kind,
          sync: widget.sync,
          token: widget.sync?.token,
        );
      }
      // Report the status actually written to the local store (pending when
      // offline, synced when it reached the backend) rather than assuming.
      final store = await ResultStore.instance();
      final latest = await store.all(limit: 1);
      final syncStatus =
          latest.isNotEmpty ? '${latest.first['sync_status']}' : 'pending';
      setState(() {
        _status =
            'Structured context ready (${envelope['latency_ms']} ms, ${envelope['engine']}) — ${reviewStatusLine(syncStatus)}.';
        _busy = false;
      });
      widget.onResultsChanged();
    } catch (e) {
      setState(() {
        _status = 'Could not process image: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: 'Capture', subtitle: patternListCaption),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Document type', style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'lab_report',
                    label: Text('Lab report'),
                  ),
                  ButtonSegment(
                    value: 'prescription',
                    label: Text('Prescription'),
                  ),
                  ButtonSegment(value: 'xray', label: Text('X-ray')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Source', style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera, size: 20),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library, size: 20),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _StatusBanner(status: _status, busy: _busy),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Scope note: printed documents only — handwriting OCR is '
                  'future work and is not attempted on-device.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tinted callout showing the current pipeline status, echoing the web app's
/// left-accented alert blocks.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.busy});

  final String status;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        color: AppColors.primary.withValues(alpha: 0.06),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: AppColors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 6),
                      Text(status, style: theme.textTheme.bodyMedium),
                      if (busy) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: const LinearProgressIndicator(minHeight: 6),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Results tab: local store contents with sync status chips.
class ResultsTab extends StatefulWidget {
  const ResultsTab({
    super.key,
    required this.refreshToken,
    this.sync,
    this.auth,
  });

  final int refreshToken;
  final V2Sync? sync;

  /// Present in the app; optional so the tab can be exercised standalone.
  final AuthService? auth;

  @override
  State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<ResultsTab> {
  List<Map<String, Object?>> _rows = [];
  int _seenToken = -1;
  bool _syncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRefresh();
  }

  @override
  void didUpdateWidget(covariant ResultsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRefresh();
  }

  Future<void> _maybeRefresh() async {
    if (_seenToken == widget.refreshToken) return;
    _seenToken = widget.refreshToken;
    final store = await ResultStore.instance();
    final rows = await store.all();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _triggerSync() async {
    final sync = widget.sync;
    if (sync == null) return;
    setState(() => _syncing = true);
    try {
      await sync.retryQueued();
      final store = await ResultStore.instance();
      final rows = await store.all();
      if (mounted) setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signIn() async {
    final auth = widget.auth;
    if (auth == null) return;
    try {
      await auth.signIn();
      widget.sync?.token = auth.token;
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.kind != AuthErrorKind.canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final auth = widget.auth;
    if (auth == null) return;
    await auth.signOut();
    widget.sync?.token = null;
  }

  Future<void> _showTokenDialog() async {
    final controller = TextEditingController(text: widget.sync?.token ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API v2 Auth Token'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Paste Bearer JWT token',
            labelText: 'Patient JWT Token',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated != null && widget.sync != null) {
      setState(() {
        widget.sync!.token = updated.isNotEmpty ? updated : null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated.isNotEmpty ? 'Auth token updated.' : 'Auth token cleared.',
            ),
          ),
        );
      }
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'prescription':
        return Icons.medication_outlined;
      case 'xray':
        return Icons.image_outlined;
      case 'lab_report':
        return Icons.science_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = widget.auth;
    final hasToken =
        widget.sync?.token != null && widget.sync!.token!.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(
          title: 'Results',
          subtitle: 'Local captures and sync status',
        ),
        const SizedBox(height: 16),
        if (auth != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ValueListenableBuilder<AuthState>(
              valueListenable: auth.state,
              builder: (context, state, _) => ValueListenableBuilder<String?>(
                valueListenable: auth.email,
                builder: (context, email, _) => _AccountRow(
                  email: email,
                  sessionExpired: state == AuthState.sessionExpired,
                  signedIn: state == AuthState.signedIn,
                  onSignIn: _signIn,
                  onSignOut: _signOut,
                ),
              ),
            ),
          ),
        AppCard(
          child: Row(
            children: [
              // Manual token entry stays as a dev/emulator fallback; the
              // primary path is Google sign-in on the account row above.
              if (!hasToken) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showTokenDialog,
                    icon: const Icon(Icons.key_off, size: 20),
                    label: const Text('Use token'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _syncing ? null : _triggerSync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync, size: 20),
                  label: const Text('Sync now'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_rows.isEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'No results yet — capture a document first.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ResultTile(
                kind: '${row['kind']}',
                rowId: '${row['id']}',
                status: '${row['sync_status']}',
                icon: _kindIcon('${row['kind']}'),
              ),
            ),
      ],
    );
  }
}

/// A single stored result, styled as a web-style card row.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.kind,
    required this.rowId,
    required this.status,
    required this.icon,
  });

  final String kind;
  final String rowId;
  final String status;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.activeNavFill,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$kind — row $rowId',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  reviewStatusLine(status),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          StatusChip(status: status),
        ],
      ),
    );
  }
}

/// Signed-in account row for the Results tab: shows who is signed in and
/// offers sign-in/sign-out. Never renders token material.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.email,
    required this.signedIn,
    required this.sessionExpired,
    required this.onSignIn,
    required this.onSignOut,
  });

  final String? email;
  final bool signedIn;
  final bool sessionExpired;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final signedIn = this.signedIn;
    final email = this.email;

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.activeNavFill,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(
              signedIn ? Icons.verified_user_outlined : Icons.person_outline,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signedIn ? (email ?? 'Signed in') : 'Not signed in',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  signedIn
                      ? 'Session active'
                      : (sessionExpired
                            ? 'Session expired — sign in to resume sync'
                            : 'Sign in to sync captures'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (signedIn)
            TextButton(
              onPressed: () => onSignOut(),
              child: const Text('Sign out'),
            )
          else
            FilledButton(
              onPressed: () => onSignIn(),
              child: const Text('Sign in'),
            ),
        ],
      ),
    );
  }
}
