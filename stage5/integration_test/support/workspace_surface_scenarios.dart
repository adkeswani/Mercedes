class WorkspaceSurfaceScenario {
  const WorkspaceSurfaceScenario({
    required this.route,
    required this.marker,
    required this.screenshot,
    required this.content,
    this.collapseControl,
    this.controls = const {},
    this.visibleContent = const [],
  });

  final String route;
  final String marker;
  final String screenshot;
  final String? content;
  final List<String> visibleContent;
  final String? collapseControl;
  final Map<String, bool> controls;
}

const athleteWorkspaceSurfaces = [
  WorkspaceSurfaceScenario(
    route: '/athlete/programs',
    marker: 'athlete-programs',
    screenshot: 'athlete-my-programs',
    content: 'Browser Athlete Program',
  ),
  WorkspaceSurfaceScenario(
    route: '/athlete/history',
    marker: 'athlete-history',
    screenshot: 'athlete-workout-history',
    content: 'Browser Completed Workout',
  ),
  WorkspaceSurfaceScenario(
    route: '/athlete/calendar',
    marker: 'athlete-calendar',
    screenshot: 'athlete-calendar',
    content: 'Browser Calendar Workout',
  ),
];

const trainerWorkspaceSurfaces = [
  WorkspaceSurfaceScenario(
    route: '/trainer/dashboard',
    marker: 'trainer-dashboard',
    screenshot: 'trainer-dashboard',
    content: 'Program ending soon: Browser Athlete Program (7 days) | '
        'Reaction: \u{1f389} 1 | Comment: Browser dashboard comment | '
        'Completion: Browser Completed Workout',
    controls: {
      'All filter': false,
      'Completions filter': false,
      'Comments filter': false,
      'Reactions filter': false,
      'Programs filter': false,
      'Personal bests': true,
    },
  ),
  WorkspaceSurfaceScenario(
    route: '/trainer/clients',
    marker: 'trainer-clients',
    screenshot: 'trainer-clients',
    content: 'Browser Smoke Athlete',
  ),
  WorkspaceSurfaceScenario(
    route: '/trainer/exercises',
    marker: 'trainer-exercises',
    screenshot: 'trainer-exercise-library',
    content: 'Browser Trainer Exercise | Strength | '
        'Browser exercises | Unfiled',
    collapseControl: 'Collapse Browser exercises',
  ),
  WorkspaceSurfaceScenario(
    route: '/trainer/workouts',
    marker: 'trainer-workouts',
    screenshot: 'trainer-workout-library',
    content: null,
    visibleContent: [
      'Browser Calendar Workout',
      'Client',
      'Full Body',
      'Browser workouts',
      'Clients',
      'Unfiled',
    ],
    collapseControl: 'Collapse Browser Smoke Athlete',
  ),
  WorkspaceSurfaceScenario(
    route: '/trainer/programs',
    marker: 'trainer-programs',
    screenshot: 'trainer-program-library',
    content: 'Browser Athlete Program | Client | Strength | '
        'Browser programs | Clients | Unfiled',
    collapseControl: 'Collapse Browser Smoke Athlete',
  ),
  WorkspaceSurfaceScenario(
    route: '/trainer/calendar',
    marker: 'trainer-calendar',
    screenshot: 'trainer-calendar-assignments',
    content: 'Browser Smoke Athlete | Browser Athlete Program | '
        'Browser Calendar Workout',
  ),
];
