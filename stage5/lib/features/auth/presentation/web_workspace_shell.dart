import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/browser_smoke_status.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/core/web_workspace/web_workspace_mode.dart';
import 'package:stage5/features/auth/domain/user_profile.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/auth/presentation/home_screen.dart';
import 'package:stage5/features/profile/presentation/feedback_dialog.dart';
import 'package:stage5/features/profile/presentation/feedback_providers.dart';

const webWorkspaceBreakpoint = 900.0;
const webWorkspaceModeSwitcherKey = Key('web-workspace-mode-switcher');
const webWorkspaceAccountIdentityKey = Key('web-workspace-account-identity');

String webWorkspaceAccountIdentity({
  UserProfile? profile,
  String? authDisplayName,
  String? authEmail,
}) {
  final displayName = profile?.displayName.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  final username = profile?.username?.trim();
  if (username != null && username.isNotEmpty) return username;
  final firebaseDisplayName = authDisplayName?.trim();
  if (firebaseDisplayName != null && firebaseDisplayName.isNotEmpty) {
    return firebaseDisplayName;
  }
  final email = profile?.email.trim();
  if (email != null && email.isNotEmpty) return email;
  final firebaseEmail = authEmail?.trim();
  if (firebaseEmail != null && firebaseEmail.isNotEmpty) return firebaseEmail;
  return 'Signed in';
}

enum WebWorkspaceDestination {
  athleteToday(
    mode: WebWorkspaceMode.athlete,
    label: 'Today',
    path: '/athlete/today',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
  ),
  athleteCalendar(
    mode: WebWorkspaceMode.athlete,
    label: 'My calendar',
    path: '/athlete/calendar',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
  ),
  athletePrograms(
    mode: WebWorkspaceMode.athlete,
    label: 'My programs',
    path: '/athlete/programs',
    icon: Icons.school_outlined,
    selectedIcon: Icons.school,
  ),
  athleteHistory(
    mode: WebWorkspaceMode.athlete,
    label: 'Workout history',
    path: '/athlete/history',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
  ),
  athleteProgress(
    mode: WebWorkspaceMode.athlete,
    label: 'Progress',
    path: '/athlete/progress',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
  ),
  athleteMessages(
    mode: WebWorkspaceMode.athlete,
    label: 'Messages',
    path: '/athlete/messages',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
  ),
  trainerDashboard(
    mode: WebWorkspaceMode.trainer,
    label: 'Dashboard',
    path: '/trainer/dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  trainerClients(
    mode: WebWorkspaceMode.trainer,
    label: 'Clients',
    path: '/trainer/clients',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  trainerExercises(
    mode: WebWorkspaceMode.trainer,
    label: 'Exercise library',
    path: '/trainer/exercises',
    icon: Icons.fitness_center_outlined,
    selectedIcon: Icons.fitness_center,
  ),
  trainerWorkouts(
    mode: WebWorkspaceMode.trainer,
    label: 'Workout library',
    path: '/trainer/workouts',
    icon: Icons.sports_gymnastics_outlined,
    selectedIcon: Icons.sports_gymnastics,
  ),
  trainerPrograms(
    mode: WebWorkspaceMode.trainer,
    label: 'Program library',
    path: '/trainer/programs',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
  ),
  trainerCalendar(
    mode: WebWorkspaceMode.trainer,
    label: 'Calendar & assignments',
    path: '/trainer/calendar',
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note,
  );

  const WebWorkspaceDestination({
    required this.mode,
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final WebWorkspaceMode mode;
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  static List<WebWorkspaceDestination> forMode(WebWorkspaceMode mode) {
    return values.where((destination) => destination.mode == mode).toList();
  }
}

class ResponsiveAuthenticatedHome extends StatelessWidget {
  const ResponsiveAuthenticatedHome({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < webWorkspaceBreakpoint) {
          return const HomeScreen();
        }
        return const KeyedSubtree(
          key: authenticatedAppEntryKey,
          child: _WebWorkspaceRedirect(),
        );
      },
    );
  }
}

class _WebWorkspaceRedirect extends ConsumerStatefulWidget {
  const _WebWorkspaceRedirect();

  @override
  ConsumerState<_WebWorkspaceRedirect> createState() =>
      _WebWorkspaceRedirectState();
}

class _WebWorkspaceRedirectState extends ConsumerState<_WebWorkspaceRedirect> {
  bool _redirectScheduled = false;

  @override
  Widget build(BuildContext context) {
    if (!_redirectScheduled) {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(ref.read(webWorkspaceModeProvider).initialLocation);
      });
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class AdaptiveWebWorkspaceRoute extends StatelessWidget {
  const AdaptiveWebWorkspaceRoute({
    required this.mode,
    required this.destination,
    required this.webChild,
    this.mobileChild = const HomeScreen(),
    super.key,
  });

  final WebWorkspaceMode mode;
  final WebWorkspaceDestination destination;
  final Widget webChild;
  final Widget mobileChild;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < webWorkspaceBreakpoint) {
          return mobileChild;
        }
        return WebWorkspaceShell(
          mode: mode,
          destination: destination,
          child: webChild,
        );
      },
    );
  }
}

class WebWorkspaceShell extends ConsumerStatefulWidget {
  const WebWorkspaceShell({
    required this.mode,
    required this.destination,
    required this.child,
    super.key,
  });

  final WebWorkspaceMode mode;
  final WebWorkspaceDestination destination;
  final Widget child;

  @override
  ConsumerState<WebWorkspaceShell> createState() => _WebWorkspaceShellState();
}

class _WebWorkspaceShellState extends ConsumerState<WebWorkspaceShell> {
  @override
  void initState() {
    super.initState();
    _scheduleModeSync();
  }

  @override
  void didUpdateWidget(covariant WebWorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _scheduleModeSync();
    }
  }

  void _scheduleModeSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(webWorkspaceModeProvider.notifier).select(widget.mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    final authenticatedUser = ref.watch(authStateProvider).valueOrNull;
    final authenticatedEmail = authenticatedUser?.email;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final accountIdentity = webWorkspaceAccountIdentity(
      profile: profile,
      authDisplayName: authenticatedUser?.displayName,
      authEmail: authenticatedEmail,
    );
    if (browserAutomationEnabled && authenticatedEmail != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          markBrowserSmokeAuthenticated(authenticatedEmail, widget.mode.name);
          markBrowserSmokeAccountIdentity(accountIdentity);
        }
      });
    }
    final destinations = WebWorkspaceDestination.forMode(widget.mode);
    final selectedIndex = destinations.indexOf(widget.destination);

    return Scaffold(
      key: authenticatedAppEntryKey,
      appBar: AppBar(
        title: Text('Mercedes · ${widget.mode.label} workspace'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SegmentedButton<WebWorkspaceMode>(
              key: webWorkspaceModeSwitcherKey,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: WebWorkspaceMode.athlete,
                  label: Text('Athlete'),
                  icon: Icon(Icons.directions_run),
                ),
                ButtonSegment(
                  value: WebWorkspaceMode.trainer,
                  label: Text('Trainer'),
                  icon: Icon(Icons.manage_accounts_outlined),
                ),
              ],
              selected: {widget.mode},
              onSelectionChanged: (selection) {
                final mode = selection.single;
                ref.read(webWorkspaceModeProvider.notifier).select(mode);
                context.go(mode.initialLocation);
              },
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            key: webWorkspaceAccountIdentityKey,
            label: 'Signed in as $accountIdentity',
            child: Tooltip(
              message: 'Signed in as $accountIdentity',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  accountIdentity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.feedback_outlined),
            tooltip: 'Send feedback',
            onPressed: () => _showFeedback(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 224,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              context.go(destinations[index].path);
            },
            destinations: [
              for (final destination in destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Future<void> _showFeedback(BuildContext context) async {
    final user = ref.read(authStateProvider).value;
    final repository = ref.read(feedbackRepositoryProvider);
    if (user == null || repository == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to send feedback.')),
      );
      return;
    }

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => FeedbackDialog(
        onSubmit: (type, body) async {
          await repository.submit(
            actorId: user.uid,
            type: type,
            body: body,
            appVersion: feedbackAppVersion,
            platform: currentFeedbackPlatform(),
            deviceModel: currentFeedbackDeviceModel(),
            screenName: widget.destination.name,
          );
        },
      ),
    );
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback sent. Thank you!')),
      );
    }
  }
}

class WebWorkspacePlaceholder extends StatelessWidget {
  const WebWorkspacePlaceholder({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
