import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage4/features/auth/data/user_profile_repository.dart';
import 'package:stage4/features/auth/presentation/app_entry_providers.dart';
import 'package:stage4/features/auth/presentation/auth_providers.dart';

/// Screen shown after first sign-in to claim a username.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  Timer? _debounceTimer;

  bool _isChecking = false;
  bool _isClaiming = false;
  String? _availabilityMessage;
  bool _isAvailable = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String value) {
    setState(() {
      _availabilityMessage = null;
      _isAvailable = false;
    });

    _debounceTimer?.cancel();

    final error = UserProfileRepository.validateUsername(value);
    if (error != null) return;

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _checkAvailability(value);
    });
  }

  Future<void> _checkAvailability(String raw) async {
    final canonical = UserProfileRepository.canonicalizeUsername(raw);
    setState(() => _isChecking = true);

    try {
      final repo = ref.read(userProfileRepositoryProvider);
      final taken = await repo.isUsernameTaken(canonical);

      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _isAvailable = !taken;
        _availabilityMessage = taken
            ? '"$canonical" is already taken'
            : '"$canonical" is available';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _availabilityMessage = 'Could not check availability';
      });
    }
  }

  Future<void> _claimUsername() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isClaiming = true);

    try {
      final repo = ref.read(userProfileRepositoryProvider);
      await repo.claimUsername(
        uid: user.uid,
        username: _usernameController.text,
      );
      // Navigation happens automatically via appEntryStateProvider
      // transitioning to AppEntryState.ready.
    } on UsernameAlreadyTakenException {
      if (!mounted) return;
      setState(() {
        _isClaiming = false;
        _isAvailable = false;
        _availabilityMessage = 'Username was just claimed by someone else';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a username',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'This is how other users will find you.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _usernameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'e.g. jane_climber',
                  prefixIcon: const Icon(Icons.alternate_email),
                  suffixIcon: _buildSuffixIcon(),
                ),
                validator: UserProfileRepository.validateUsername,
                onChanged: _onUsernameChanged,
                onFieldSubmitted: (_) => _claimUsername(),
              ),
              if (_availabilityMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _availabilityMessage!,
                  style: TextStyle(
                    color: _isAvailable ? Colors.green : Colors.red,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isClaiming ? null : _claimUsername,
                child: _isClaiming
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Claim Username'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon() {
    if (_isChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_availabilityMessage != null) {
      return Icon(
        _isAvailable ? Icons.check_circle : Icons.cancel,
        color: _isAvailable ? Colors.green : Colors.red,
      );
    }
    return null;
  }
}
