/// An opponent's seat chip: avatar with idle bob, an animated rotating-
/// gradient turn ring with breathing scale when it's their turn, a depleting
/// countdown arc, a count chip that pulses on every change, and a shake
/// driven by the reveal set piece when they're caught lying.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/motion/animation_speed.dart';
import '../../../core/net/client_game_state.dart';
import '../../../core/strings.dart';
import '../anim/motion_jitter.dart';
import '../anim/motion_spec.dart';
import '../anim/table_anchors.dart';
import 'countdown_ring.dart';

class SeatAvatar extends StatefulWidget {
  const SeatAvatar({
    super.key,
    required this.player,
    required this.isTurn,
    required this.remaining,
    required this.turnTotal,
    required this.speed,
    required this.anchors,
  });

  final PlayerView player;
  final bool isTurn;

  /// Time left on the active turn (zero when not their turn).
  final Duration remaining;
  final Duration turnTotal;
  final AnimationSpeed speed;
  final TableAnchors anchors;

  @override
  State<SeatAvatar> createState() => _SeatAvatarState();
}

class _SeatAvatarState extends State<SeatAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: MotionSpec.turnRingRotation);
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: MotionSpec.avatarBobPeriod,
    value: motionJitter.range(0, 1), // randomized phase per avatar
  );
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    _syncIdle();
    widget.anchors.shake.addListener(_onShake);
  }

  @override
  void didUpdateWidget(SeatAvatar old) {
    super.didUpdateWidget(old);
    if (old.isTurn != widget.isTurn || old.speed != widget.speed) _syncIdle();
  }

  void _syncIdle() {
    final animate = !widget.speed.isOff;
    if (animate && widget.isTurn) {
      if (!_ring.isAnimating) _ring.repeat();
    } else {
      _ring.stop();
    }
    if (animate) {
      if (!_bob.isAnimating) _bob.repeat();
    } else {
      _bob.stop();
    }
  }

  void _onShake() {
    final pulse = widget.anchors.shake.value;
    if (pulse == null || pulse.seat != widget.player.seat) return;
    if (widget.speed.isOff || !mounted) return;
    _shake.forward(from: 0);
  }

  @override
  void dispose() {
    widget.anchors.shake.removeListener(_onShake);
    _ring.dispose();
    _bob.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = widget.player;

    return Container(
      width: 86,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: AnimatedBuilder(
        animation: Listenable.merge([_ring, _bob, _shake]),
        builder: (context, child) {
          final bob = widget.speed.isOff
              ? 0.0
              : sin(_bob.value * 2 * pi) * MotionSpec.avatarBobAmplitude;
          // Decaying sideways shake for the caught liar.
          final shakeT = _shake.value;
          final shakeDx = _shake.isAnimating || (shakeT > 0 && shakeT < 1)
              ? sin(shakeT * pi * 7) * 7 * (1 - shakeT)
              : 0.0;
          final breathe = widget.isTurn && !widget.speed.isOff
              ? 1 +
                  MotionSpec.breathingScaleDelta *
                      sin(_ring.value * 2 * pi *
                          MotionSpec.turnRingRotation.inMilliseconds /
                          MotionSpec.breathingPeriod.inMilliseconds)
              : 1.0;
          return Transform.translate(
            offset: Offset(shakeDx, bob),
            child: Transform.scale(scale: breathe, child: child),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatarWithRings(theme),
            const SizedBox(height: 2),
            Text(
              player.nickname,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            _badgesRow(theme),
          ],
        ),
      ),
    );
  }

  Widget _avatarWithRings(ThemeData theme) {
    final scheme = theme.colorScheme;
    const avatarSize = 40.0;
    const ringSize = 52.0;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.isTurn)
            AnimatedBuilder(
              animation: _ring,
              builder: (context, _) => CustomPaint(
                size: const Size.square(ringSize),
                painter: _TurnRingPainter(
                  rotation: _ring.value * 2 * pi,
                  color: scheme.primary,
                ),
              ),
            ),
          if (widget.isTurn && widget.turnTotal > Duration.zero)
            SizedBox(
              width: ringSize - 2,
              height: ringSize - 2,
              child: CustomPaint(
                painter: CountdownRingPainter(
                  fraction: (widget.remaining.inMilliseconds /
                          widget.turnTotal.inMilliseconds)
                      .clamp(0.0, 1.0),
                  color: countdownColor(widget.remaining, scheme),
                  trackColor: Colors.transparent,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          CircleAvatar(
            radius: avatarSize / 2,
            child: Text(_initial()),
          ),
        ],
      ),
    );
  }

  String _initial() {
    final n = widget.player.nickname;
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  Widget _badgesRow(ThemeData theme) {
    final player = widget.player;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Count chip pulses whenever the (rendered) count changes.
        TweenAnimationBuilder<double>(
          key: ValueKey(player.cardCount),
          tween: Tween(begin: 1.35, end: 1.0),
          duration: widget.speed.scale(const Duration(milliseconds: 240)),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Chip(
            label: Text('${player.cardCount}'),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
        if (player.isOut)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(Strings.outBadge, style: const TextStyle(fontSize: 10)),
          ),
        if (!player.connected)
          const Icon(Icons.power_off, size: 14)
        else if (player.autoPilot)
          const Icon(Icons.smart_toy, size: 14),
      ],
    );
  }
}

/// Rotating sweep-gradient stroke around the active player.
class _TurnRingPainter extends CustomPainter {
  _TurnRingPainter({required this.rotation, required this.color});

  final double rotation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.05),
          color,
          color.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.55, 1.0],
        transform: GradientRotation(rotation),
      ).createShader(rect);
    canvas.drawArc(rect, 0, 2 * pi, false, paint);
  }

  @override
  bool shouldRepaint(_TurnRingPainter old) =>
      old.rotation != rotation || old.color != color;
}
