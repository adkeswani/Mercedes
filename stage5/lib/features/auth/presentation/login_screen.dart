import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';

/// Sign-in screen with Google Sign-In button.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  bool _autoLoginScheduled = false;
  final _releaseCanaryEmailController = TextEditingController();
  final _releaseCanaryPasswordController = TextEditingController();

  @override
  void dispose() {
    _releaseCanaryEmailController.dispose();
    _releaseCanaryPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signIn(Future<void> Function() operation) async {
    setState(() => _isLoading = true);

    try {
      await operation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() {
    return _signIn(() async {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    });
  }

  Future<void> _signInForBrowserSmoke() {
    return _signIn(() async {
      await ref.read(authRepositoryProvider).signInWithEmailAndPassword(
            email: browserSmokeConfig.email,
            password: browserSmokeConfig.password,
          );
    });
  }

  Future<void> _signInForReleaseCanary() {
    final email = _releaseCanaryEmailController.text.trim();
    if (!isReleaseCanaryEmail(email) ||
        _releaseCanaryPasswordController.text.isEmpty) {
      return _signIn(
        () => Future<void>.error(
          StateError(
            'Release canary credentials must use the release-canary- '
            'namespace and include a password.',
          ),
        ),
      );
    }
    return _signIn(() async {
      await ref.read(authRepositoryProvider).signInWithEmailAndPassword(
            email: email,
            password: _releaseCanaryPasswordController.text,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (browserSmokeConfig.autoLoginEnabled && !_autoLoginScheduled) {
      _autoLoginScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _signInForBrowserSmoke();
        }
      });
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mercedes', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'Training Management',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 48),
            _isLoading
                ? const CircularProgressIndicator()
                : FilledButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                  ),
            if (!_isLoading && browserSmokeConfig.loginEnabled) ...[
              const SizedBox(height: 12),
              TextButton(
                key: browserSmokeLoginButtonKey,
                onPressed: _signInForBrowserSmoke,
                child: const Text('Sign in to local test account'),
              ),
            ],
            if (!_isLoading && releaseCanaryMode) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 360,
                child: TextField(
                  key: releaseCanaryEmailFieldKey,
                  controller: _releaseCanaryEmailController,
                  autofillHints: const [AutofillHints.username],
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Release canary email',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 360,
                child: TextField(
                  key: releaseCanaryPasswordFieldKey,
                  controller: _releaseCanaryPasswordController,
                  autofillHints: const [AutofillHints.password],
                  obscureText: true,
                  onSubmitted: (_) => _signInForReleaseCanary(),
                  decoration: const InputDecoration(
                    labelText: 'Release canary password',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Sign in to release canary',
                button: true,
                excludeSemantics: true,
                child: FilledButton(
                  key: releaseCanaryLoginButtonKey,
                  onPressed: _signInForReleaseCanary,
                  child: const Text('Sign in to release canary'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
