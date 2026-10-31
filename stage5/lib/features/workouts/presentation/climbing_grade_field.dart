import 'package:flutter/material.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';

class ClimbingGradeField extends StatelessWidget {
  const ClimbingGradeField({
    required this.system,
    required this.grade,
    required this.onChanged,
    super.key,
  });
  final ClimbingGradingSystem system;
  final String grade;
  final void Function(ClimbingGradingSystem system, String grade) onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<ClimbingGradingSystem>(
            initialValue: system,
            decoration: const InputDecoration(labelText: 'Grading system'),
            items: [
              for (final value in ClimbingGradingSystem.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value, value.grades.first);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('${system.name}-$grade'),
            initialValue: grade,
            decoration: const InputDecoration(labelText: 'Grade'),
            items: [
              for (final value in system.grades)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) {
              if (value != null) onChanged(system, value);
            },
          ),
        ],
      );
}
