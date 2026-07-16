/// Physics-y emoji reaction bursts: 5-9 copies fountain up from the sender's
/// avatar with random velocity, spin, and gravity, fading over ~1.2 s.
/// A single custom [Ticker] drives all live particles.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'motion_jitter.dart';
import 'motion_spec.dart';

class _EmojiParticle {
  _EmojiParticle({
    required this.emoji,
    required this.origin,
    required this.velocity,
    required this.spin,
    required this.born,
    required this.size,
  });

  final String emoji;
  final Offset origin;
  final Offset velocity; // dp/s
  final double spin; // rad/s
  final Duration born;
  final double size;
}

class EmojiBurstController extends ChangeNotifier {
  final List<_EmojiParticle> _particles = [];
  final List<({String emoji, Offset origin})> _pendingBursts = [];

  /// Fountain [emoji] up from [origin] (global coords).
  void burst(String emoji, Offset origin) {
    _pendingBursts.add((emoji: emoji, origin: origin));
    notifyListeners();
  }
}

class EmojiBurstLayer extends StatefulWidget {
  const EmojiBurstLayer({super.key, required this.controller});

  final EmojiBurstController controller;

  @override
  State<EmojiBurstLayer> createState() => _EmojiBurstLayerState();
}

class _EmojiBurstLayerState extends State<EmojiBurstLayer>
    with SingleTickerProviderStateMixin {
  // Created in initState: lazy init would run createTicker (an ancestor
  // lookup) during dispose when no burst ever fired.
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final pending = widget.controller._pendingBursts;
    if (pending.isEmpty) return;
    for (final b in List.of(pending)) {
      _spawn(b.emoji, b.origin);
    }
    pending.clear();
    if (!_ticker.isActive) {
      _elapsed = Duration.zero;
      _ticker.start();
    }
  }

  void _spawn(String emoji, Offset origin) {
    final count = motionJitter.intRange(
        MotionSpec.reactionMinCount, MotionSpec.reactionMaxCount);
    for (var i = 0; i < count; i++) {
      // Fountain: mostly upward, fanned sideways.
      final angle = motionJitter.range(-pi * 0.80, -pi * 0.20);
      final speed = MotionSpec.reactionLaunchSpeed * motionJitter.range(0.6, 1.3);
      widget.controller._particles.add(_EmojiParticle(
        emoji: emoji,
        origin: origin,
        velocity: Offset(cos(angle), sin(angle)) * speed,
        spin: motionJitter.range(-6, 6),
        born: _elapsed,
        size: motionJitter.range(18, 30),
      ));
    }
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    final particles = widget.controller._particles;
    particles.removeWhere(
        (p) => elapsed - p.born > MotionSpec.reactionBurstLife);
    if (particles.isEmpty) {
      _ticker.stop();
      _elapsed = Duration.zero;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final layerOrigin =
        (box != null && box.attached) ? box.localToGlobal(Offset.zero) : Offset.zero;
    final lifeSec = MotionSpec.reactionBurstLife.inMilliseconds / 1000;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          for (final p in widget.controller._particles)
            _buildParticle(p, layerOrigin, lifeSec),
        ],
      ),
    );
  }

  Widget _buildParticle(_EmojiParticle p, Offset layerOrigin, double lifeSec) {
    final ageSec =
        (_elapsed - p.born).inMicroseconds / Duration.microsecondsPerSecond;
    final t = (ageSec / lifeSec).clamp(0.0, 1.0);
    final pos = p.origin -
        layerOrigin +
        p.velocity * ageSec +
        Offset(0, MotionSpec.reactionGravity * ageSec * ageSec / 2);
    // Fade out over the last 40 % of life.
    final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4);

    return Positioned(
      left: pos.dx - p.size / 2,
      top: pos.dy - p.size / 2,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: p.spin * ageSec,
          child: Text(p.emoji, style: TextStyle(fontSize: p.size)),
        ),
      ),
    );
  }
}
