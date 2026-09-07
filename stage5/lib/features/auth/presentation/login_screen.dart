import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/browser_smoke_config.dart';
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

  Future<void> _signIn(Future<void> Function() operation) async {
    setState(() => _isLoading = true);

    try {
      await operation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
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
            Text(
              'Mercedes',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
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
          ],
        ),
      ),
    );
  }
}
