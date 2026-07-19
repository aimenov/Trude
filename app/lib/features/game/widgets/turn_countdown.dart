/// Self-ticking countdown ring: a leaf that owns its own 250ms timer and
/// setStates only itself, so the ancestor screen never rebuilds just to
/// advance the countdown (perf task A1). Remaining time is recomputed from
/// the wall clock (`deadlineTs - now`) on every tick, so it stays correct
/// under frame drops and missed ticks. The timer cancels itself at zero and
/// on dispose (widget tests fail on pending timers), and re-arms whenever
/// [SelfTickingCountdownRing.deadlineTs] changes (a new turn).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'countdown_ring.dart';

class SelfTickingCountdownRing extends StatefulWidget {
  const SelfTickingCountdownRing({
    super.key,
    required this.deadlineTs,
    required this.totalMs,
    this.size = 34,
    this.strokeWidth = 4.5,
    this.animate = true,
  });

  /// Turn deadline, epoch milliseconds.
  final int deadlineTs;

  /// The armed decision window the ring drains over, milliseconds.
  final int totalMs;

  final double size;
  final double strokeWidth;

  /// Whether the urgent-window stroke pulse may run (see [CountdownRing]).
  final bool animate;

  @override
  State<SelfTickingCountdownRing> createState() =>
      _SelfTickingCountdownRingState();
}

class _SelfTickingCountdownRingState extends State<SelfTickingCountdownRing> {
  static const _tick = Duration(milliseconds: 250);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(SelfTickingCountdownRing old) {
    super.didUpdateWidget(old);
    if (old.deadlineTs != widget.deadlineTs) _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_remaining() <= Duration.zero) return;
    _timer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      if (_remaining() <= Duration.zero) {
        // Deadline passed: one last rebuild draws the empty ring, then stop.
        _timer?.cancel();
        _timer = null;
      }
      setState(() {});
    });
  }

  Duration _remaining() {
    final left = widget.deadlineTs - DateTime.now().millisecondsSinceEpoch;
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  @override
  Widget build(BuildContext context) {
    // The boundary keeps the 4Hz ring repaint from invalidating siblings.
    return RepaintBoundary(
      child: CountdownRing(
        remaining: _remaining(),
        total: Duration(milliseconds: widget.totalMs),
        size: widget.size,
        strokeWidth: widget.strokeWidth,
        animate: widget.animate,
      ),
    );
  }
}
