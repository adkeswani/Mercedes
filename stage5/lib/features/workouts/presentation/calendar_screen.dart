import 'package:flutter/material.dart';

import 'package:stage5/features/workouts/presentation/trainer_calendar_screen.dart';

/// Athlete entry point to the shared month-and-day schedule.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const TrainerCalendarScreen(selfService: true);
}
