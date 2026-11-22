import 'dart:async';

import 'package:flutter/material.dart';

/// A compact start/pause/reset timer used while completing a workout, for
/// either a timed work interval or a rest period between sets/rounds.
///
/// When [targetSeconds] is provided the timer counts down from it and fires
/// [onCompleted] once (clamping the displayed remaining time at zero).
/// Without a target it counts up indefinitely as a stopwatch. Every tick
/// (and reset) reports the elapsed seconds via [onElapsedChanged] so the
/// caller can keep a recorded actual in sync with the timer. Ticks refresh a
/// timestamp-based elapsed duration, so suspended browsers catch up on resume.
class WorkoutTimerWidget extends StatefulWidget {
  const WorkoutTimerWidget({
    required this.label,
    this.targetSeconds,
    this.initialTargetSeconds,
    this.onTargetChanged,
    this.onElapsedChanged,
    this.onCompleted,
    super.key,
  });

  final String label;
  final int? targetSeconds;
  final int? initialTargetSeconds;
  final ValueChanged<int?>? onTargetChanged;
  final ValueChanged<int>? onElapsedChanged;
  final VoidCallback? onCompleted;

  @override
  State<WorkoutTimerWidget> createState() => WorkoutTimerWidgetState();
}

class WorkoutTimerWidgetState extends State<WorkoutTimerWidget>
    with WidgetsBindingObserver {
  Timer? _ticker;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Duration _elapsedAtStart = Duration.zero;
  int _elapsedSeconds = 0;
  bool _running = false;
  bool _completedNotified = false;
  int? _overrideSeconds;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  int? get _targetSeconds => _overrideSeconds ?? widget.targetSeconds;

  bool get _isCountdown => _targetSeconds != null;

  int get _displaySeconds {
    if (!_isCountdown) {
      return _elapsedSeconds;
    }
    final remaining = _targetSeconds! - _elapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void initState() {
    super.initState();
    _overrideSeconds = widget.initialTargetSeconds;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(WorkoutTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetSeconds != widget.targetSeconds) {
      _overrideSeconds = null;
      reset();
    }
  }

  Future<void> _configure() async {
    final selection = await showDialog<({int? seconds})>(
      context: context,
      builder: (context) => _TimerDurationDialog(
        label: widget.label,
        currentSeconds: _targetSeconds,
        prescribedSeconds: widget.targetSeconds,
      ),
    );
    if (!mounted || selection == null) return;
    _overrideSeconds =
        selection.seconds == widget.targetSeconds ? null : selection.seconds;
    reset();
    widget.onTargetChanged?.call(_targetSeconds);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshElapsed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  void start() {
    if (_running || _completedNotified) {
      return;
    }
    _startedAt = now();
    _elapsedAtStart = _elapsed;
    setState(() => _running = true);
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshElapsed(),
    );
  }

  void _refreshElapsed() {
    if (!_running) {
      return;
    }
    var elapsed = _elapsedAtStart + now().difference(_startedAt!);
    // A device clock adjustment must not make a running timer go backwards.
    if (elapsed < _elapsed) {
      elapsed = _elapsed;
    }
    final completed = _isCountdown && elapsed.inSeconds >= _targetSeconds!;
    if (completed) {
      elapsed = Duration(seconds: _targetSeconds!);
    }
    final secondsChanged = elapsed.inSeconds != _elapsedSeconds;
    setState(() {
      _elapsed = elapsed;
      _elapsedSeconds = elapsed.inSeconds;
      if (completed) {
        _pauseTicker();
        _completedNotified = true;
      }
    });
    if (secondsChanged) {
      widget.onElapsedChanged?.call(_elapsedSeconds);
    }
    if (completed) {
      widget.onCompleted?.call();
    }
  }

  void pause() {
    if (!_running) {
      return;
    }
    _refreshElapsed();
    setState(_pauseTicker);
  }

  void _pauseTicker() {
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _running = false;
  }

  void reset() {
    _pauseTicker();
    setState(() {
      _elapsed = Duration.zero;
      _elapsedAtStart = Duration.zero;
      _elapsedSeconds = 0;
      _completedNotified = false;
    });
    widget.onElapsedChanged?.call(0);
  }

  String _format(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = _isCountdown &&
        _elapsedSeconds >= _targetSeconds! &&
        _elapsedSeconds > 0;
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              Text('${widget.label}:', style: theme.textTheme.bodySmall),
              Text(
                isDone ? 'Time!' : _format(_displaySeconds),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isDone ? Colors.green : null,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Change ${widget.label.toLowerCase()} timer duration',
          onPressed: _configure,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(_running ? Icons.pause : Icons.play_arrow),
          tooltip: _running
              ? 'Pause ${widget.label.toLowerCase()} timer'
              : 'Start ${widget.label.toLowerCase()} timer',
          onPressed: _running ? pause : start,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.replay),
          tooltip: 'Reset ${widget.label.toLowerCase()} timer',
          onPressed: reset,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _TimerDurationDialog extends StatefulWidget {
  const _TimerDurationDialog({
    required this.label,
    required this.currentSeconds,
    required this.prescribedSeconds,
  });

  final String label;
  final int? currentSeconds;
  final int? prescribedSeconds;

  @override
  State<_TimerDurationDialog> createState() => _TimerDurationDialogState();
}

class _TimerDurationDialogState extends State<_TimerDurationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(
    text: widget.currentSeconds?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.label} timer'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.prescribedSeconds == null
                  ? 'Default: stopwatch'
                  : 'Trainer default: ${widget.prescribedSeconds} seconds'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Duration (seconds)'),
                validator: (value) {
                  final seconds = int.tryParse(value?.trim() ?? '');
                  return seconds == null || seconds < 1 || seconds > 2147483647
                      ? 'Enter a positive whole number of seconds (at most 2147483647)'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Changing the duration resets this timer. The trainer prescription is unchanged. This adjustment is not saved when you leave the workout.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop((seconds: widget.prescribedSeconds)),
            child: const Text('Use default'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.of(context)
                    .pop((seconds: int.parse(_controller.text.trim())));
              }
            },
            child: const Text('Apply'),
          ),
        ],
      );
}
