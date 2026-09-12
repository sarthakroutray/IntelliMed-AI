import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../auth.dart';
import '../copy.dart';
import '../model_manager.dart';
import '../sync.dart';
import '../tabs_bench_spike.dart';
import '../theme.dart';
import '../theme_controller.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/filter_chips.dart';
import 'dev_lab_diff_screen.dart';

/// "Me": profile, settings, connected doctors, and sign-out.
///
/// Also hosts the developer section (bench/spike harnesses and a manual token
/// override) so those tools don't occupy a primary navigation slot.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.auth,
    required this.repository,
    required this.models,
    required this.sync,
    required this.themeController,
    required this.refreshToken,
    required this.isActive,
  });

  final AuthService auth;
  final PatientRepository repository;
  final ModelManager models;
  final V2Sync sync;
  final ThemeController themeController;
  final int refreshToken;

  /// Whether this is the tab currently shown; inactive tabs defer their reload.
  final bool isActive;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  Profile? _profile;
  List<LinkedDoctor> _doctors = const [];
  int _seenToken = -1;

  bool _emailNotifications = true;
  bool _pushNotifications = true;

  bool _editing = false;
  final _form = <String, TextEditingController>{};

  static const _editableFields = <String, String>{
    'name': 'Full name',
    'phone': 'Phone',
    'date_of_birth': 'Date of birth (YYYY-MM-DD)',
    'gender': 'Gender',
    'address': 'Address',
    'emergency_contact': 'Emergency contact name',
    'emergency_phone': 'Emergency contact phone',
    'blood_type': 'Blood type',
    'allergies': 'Known allergies',
    'chronic_conditions': 'Chronic conditions',
  };

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && widget.refreshToken != _seenToken) _load();
  }

  @override
  void dispose() {
    for (final controller in _form.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _seenToken = widget.refreshToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.repository.getProfile(),
        widget.repository.listLinkedDoctors(),
      ]);
      final profile = results[0] as Profile;
      final doctors = results[1] as List<LinkedDoctor>;
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _doctors = doctors;
        _emailNotifications = profile.emailNotifications;
        _pushNotifications = profile.pushNotifications;
        _loading = false;
      });
      // Keep the app theme in step with the account preference.
      widget.themeController.applyFromProfile(profile.darkMode);
      _seedForm(profile);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _seedForm(Profile profile) {
    final values = <String, String>{
      'name': profile.name ?? '',
      'phone': profile.phone ?? '',
      'date_of_birth': profile.dateOfBirth ?? '',
      'gender': profile.gender ?? '',
      'address': profile.address ?? '',
      'emergency_contact': profile.emergencyContact ?? '',
      'emergency_phone': profile.emergencyPhone ?? '',
      'blood_type': profile.bloodType ?? '',
      'allergies': profile.allergies ?? '',
      'chronic_conditions': profile.chronicConditions ?? '',
    };
    values.forEach((key, value) {
      (_form[key] ??= TextEditingController()).text = value;
    });
  }

  Future<void> _saveProfile() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final changes = <String, dynamic>{};
      _form.forEach((key, controller) {
        final text = controller.text.trim();
        if (text.isNotEmpty) changes[key] = text;
      });
      await widget.repository.updateProfile(changes);
      setState(() {
        _editing = false;
        _notice = 'Profile updated.';
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNotifications() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await widget.repository.updateProfile({
        'email_notifications': _emailNotifications,
        'push_notifications': _pushNotifications,
      });
      if (mounted) setState(() => _notice = 'Notification settings saved.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    await widget.themeController.set(mode);
    try {
      await widget.repository.updateProfile({
        'dark_mode': mode == ThemeMode.dark,
      });
    } on ApiException {
      // Local preference already applied; syncing is best-effort.
    }
    if (mounted) setState(() {});
  }

  Future<void> _generateCode() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final code = await widget.repository.generateAccessCode();
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Access code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  code,
                  style: Theme.of(ctx).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share this with your doctor. They enter it in their dashboard '
                  'to link to your records. It has been copied to your clipboard.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    widget.sync.token = null;
  }

  Future<void> _editToken() async {
    final controller = TextEditingController(text: widget.sync.token ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auth token override'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Paste Bearer JWT'),
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
    if (updated == null) return;
    widget.sync.token = updated.isEmpty ? null : updated;
    if (mounted) {
      setState(() => _notice = updated.isEmpty
          ? 'Token cleared.'
          : 'Token set for this session.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _profile;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Me', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingView(message: 'Loading your profile…')
          else if (_error != null)
            ErrorView(message: _error!, onRetry: _load)
          else if (profile != null)
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.activeNavFill,
                    child: Text(
                      profile.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(profile.email, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        Text(
                          'Patient ID #${profile.id}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            InlineBanner(
              tone: BannerTone.info,
              icon: Icons.check_circle_outline,
              message: _notice!,
            ),
          ],
          const SizedBox(height: 20),

          // --- Doctors -------------------------------------------------
          Text('Connected doctors', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_doctors.isEmpty)
                  Text(
                    'No doctors connected yet.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final doctor in _doctors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doctor.displayName,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Text(
                                  doctor.email,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _generateCode,
                  icon: const Icon(Icons.key, size: 18),
                  label: const Text('Generate access code'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your doctor enters this code to link to your records.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Profile -------------------------------------------------
          Row(
            children: [
              Expanded(
                child: Text('Profile', style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: _editing
                    ? () => setState(() => _editing = false)
                    : () => setState(() => _editing = true),
                child: Text(_editing ? 'Cancel' : 'Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (profile != null)
            AppCard(
              child: _editing
                  ? _ProfileForm(form: _form, fields: _editableFields)
                  : _ProfileSummary(profile: profile),
            ),
          if (_editing) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _saveProfile,
              child: Text(_busy ? 'Saving…' : 'Save changes'),
            ),
          ],
          const SizedBox(height: 20),

          // --- Notifications ------------------------------------------
          Text('Notifications', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  value: _emailNotifications,
                  onChanged: (v) => setState(() => _emailNotifications = v),
                  title: const Text('Email notifications'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                SwitchListTile(
                  value: _pushNotifications,
                  onChanged: (v) => setState(() => _pushNotifications = v),
                  title: const Text('Push notifications'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _saveNotifications,
                      child: const Text('Save notification settings'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Appearance ---------------------------------------------
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Wrap-based chips rather than a SegmentedButton, which cannot
                // wrap and overflows on a narrow screen.
                FilterChips<ThemeMode>(
                  values: ThemeMode.values,
                  selected: widget.themeController.value,
                  labelOf: (m) => switch (m) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  },
                  onSelected: _setTheme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Developer ----------------------------------------------
          Text('Developer', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Backend: ${widget.sync.baseUrl}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.sync.token == null || widget.sync.token!.isEmpty
                      ? 'No auth token set'
                      : 'Auth token set',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _editToken,
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Override auth token'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Bench')),
                        body: BenchTab(
                          models: widget.models,
                          sync: widget.sync,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.speed_outlined, size: 18),
                  label: const Text('Bench measurements'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Spike')),
                        body: SpikeTab(models: widget.models),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Spike tools'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DevLabDiffScreen(
                        models: widget.models,
                        repository: widget.repository,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: const Text('Lab engine diff'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 16),
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

class _ProfileForm extends StatelessWidget {
  const _ProfileForm({required this.form, required this.fields});

  final Map<String, TextEditingController> form;
  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in fields.entries) ...[
          TextField(
            controller: form[entry.key],
            decoration: InputDecoration(labelText: entry.value),
            maxLines: entry.key == 'address' || entry.key == 'allergies' ||
                    entry.key == 'chronic_conditions'
                ? 2
                : 1,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final rows = <String, String?>{
      'Full name': profile.name,
      'Phone': profile.phone,
      'Date of birth': profile.dateOfBirth,
      'Gender': profile.gender,
      'Address': profile.address,
      'Emergency contact': profile.emergencyContact,
      'Emergency phone': profile.emergencyPhone,
      'Blood type': profile.bloodType,
      'Allergies': profile.allergies,
      'Chronic conditions': profile.chronicConditions,
    };

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in rows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    entry.key,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value == null || entry.value!.isEmpty
                        ? '—'
                        : entry.value!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
