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
    this.onElapsedChanged,
    this.onCompleted,
    super.key,
  });

  final String label;
  final int? targetSeconds;
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

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  bool get _isCountdown => widget.targetSeconds != null;

  int get _displaySeconds {
    if (!_isCountdown) {
      return _elapsedSeconds;
    }
    final remaining = widget.targetSeconds! - _elapsedSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final completed =
        _isCountdown && elapsed.inSeconds >= widget.targetSeconds!;
    if (completed) {
      elapsed = Duration(seconds: widget.targetSeconds!);
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
        _elapsedSeconds >= widget.targetSeconds! &&
        _elapsedSeconds > 0;
    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text('${widget.label}:', style: theme.textTheme.bodySmall),
        const SizedBox(width: 6),
        Text(
          isDone ? 'Time!' : _format(_displaySeconds),
          style: theme.textTheme.titleMedium?.copyWith(
            color: isDone ? Colors.green : null,
          ),
        ),
        const Spacer(),
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
