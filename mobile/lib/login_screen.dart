import 'package:flutter/material.dart';

import 'auth.dart';
import 'copy.dart';
import 'theme.dart';
import 'widgets/app_card.dart';
import 'widgets/brand_mark.dart';

/// Sign-in gate for the on-device app.
///
/// Mirrors the web login's card layout and uses the same design tokens. The
/// app is patient-only: `/api/v2/lab-reports/upload-structured` rejects other
/// roles, so a doctor account cannot sync captures.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn();
    } on AuthException catch (e) {
      // A dismissed account picker isn't worth an error banner.
      if (e.kind != AuthErrorKind.canceled && mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLockup(markSize: 44)),
                  const SizedBox(height: 24),
                  AppCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to sync structured results for doctor review.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _busy ? null : _signIn,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login, size: 20),
                          label: Text(
                            _busy ? 'Signing in…' : 'Continue with Google',
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          'Patient accounts only. Sign-in requires a network '
                          'connection; once signed in, captures work offline '
                          'and sync automatically when you are back online.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    patternListCaption,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left-accented error block echoing the web app's alert styling.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        color: color.withValues(alpha: 0.08),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
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
