/// An opponent's seat: a brass-ringed portrait on a sunken ground with idle
/// bob, a rotating brass turn ring with a soft glow when it's their turn, a
/// depleting countdown arc, an ivory card-stack count chip that pulses on
/// every change, and a shake driven by the reveal set piece when they're
/// caught lying.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/motion/animation_speed.dart';
import '../../../core/net/client_game_state.dart';
import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../anim/motion_jitter.dart';
import '../anim/motion_spec.dart';
import '../anim/table_anchors.dart';
import 'countdown_ring.dart';

class SeatAvatar extends StatefulWidget {
  const SeatAvatar({
    super.key,
    required this.player,
    required this.isTurn,
    this.deadlineTs,
    required this.turnTotal,
    required this.speed,
    required this.anchors,
  });

  final PlayerView player;
  final bool isTurn;

  /// Turn deadline (epoch ms) when it's this seat's turn; null otherwise.
  /// The avatar ticks its own countdown from it — the parent screen no
  /// longer rebuilds 4x/s to drain the arc.
  final int? deadlineTs;
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

  /// Drains the countdown arc; runs only while it's this seat's turn (one
  /// active seat at a time), self-cancels past the deadline and on dispose.
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _syncIdle();
    _syncCountdown();
    widget.anchors.shake.addListener(_onShake);
  }

  @override
  void didUpdateWidget(SeatAvatar old) {
    super.didUpdateWidget(old);
    if (old.isTurn != widget.isTurn || old.speed != widget.speed) _syncIdle();
    if (old.isTurn != widget.isTurn || old.deadlineTs != widget.deadlineTs) {
      _syncCountdown();
    }
  }

  void _syncCountdown() {
    _countdown?.cancel();
    _countdown = null;
    if (!widget.isTurn || widget.deadlineTs == null || _remainingMs() <= 0) {
      return;
    }
    _countdown = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_remainingMs() <= 0) {
        // One last rebuild draws the empty arc, then the timer stops.
        _countdown?.cancel();
        _countdown = null;
      }
      setState(() {});
    });
  }

  /// Milliseconds until [SeatAvatar.deadlineTs] (never negative).
  int _remainingMs() {
    final deadline = widget.deadlineTs;
    if (deadline == null) return 0;
    return max(0, deadline - DateTime.now().millisecondsSinceEpoch);
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
    _countdown?.cancel();
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
            _portraitWithRings(theme),
            const SizedBox(height: 2),
            Text(
              player.nickname,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: TrudeColors.textPrimary),
            ),
            _badgesRow(theme),
          ],
        ),
      ),
    );
  }

  Widget _portraitWithRings(ThemeData theme) {
    final scheme = theme.colorScheme;
    const portraitSize = 40.0;
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
                painter: _TurnRingPainter(rotation: _ring.value * 2 * pi),
              ),
            ),
          if (widget.isTurn &&
              widget.deadlineTs != null &&
              widget.turnTotal > Duration.zero)
            SizedBox(
              width: ringSize - 2,
              height: ringSize - 2,
              child: CustomPaint(
                painter: CountdownRingPainter(
                  fraction:
                      (_remainingMs() / widget.turnTotal.inMilliseconds)
                          .clamp(0.0, 1.0),
                  color: countdownColor(
                      Duration(milliseconds: _remainingMs()), scheme),
                  trackColor: Colors.transparent,
                  strokeWidth: 3.5,
                ),
              ),
            ),
          // The brass-framed portrait itself.
          CustomPaint(
            size: const Size.square(portraitSize + 4),
            painter: _PortraitFramePainter(),
            child: Container(
              width: portraitSize,
              height: portraitSize,
              margin: const EdgeInsets.all(2),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: TrudeColors.surfaceSunken,
                shape: BoxShape.circle,
              ),
              child: Text(
                _initial(),
                style: TrudeType.display.copyWith(
                  fontSize: 19,
                  height: 1.0,
                  color: TrudeColors.brassBright,
                ),
              ),
            ),
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
    // scaleDown: identity at natural size, shrinks only under overflow —
    // regression-proof for any badge/icon combination at the 86px seat width.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!player.isOut)
            // Count chip pulses whenever the (rendered) count changes. An out
            // player shows no chip — «ВЫШЕЛ» already says it all.
            TweenAnimationBuilder<double>(
              key: ValueKey(player.cardCount),
              tween: Tween(begin: 1.35, end: 1.0),
              duration: widget.speed.scale(const Duration(milliseconds: 240)),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: _countChip(player.cardCount),
            )
          else
            Text(
              Strings.outBadge,
              style: TrudeType.etched
                  .copyWith(fontSize: 9, letterSpacing: 1.2, height: 1.2),
            ),
          if (!player.connected)
            const Icon(Icons.power_off, size: 14, color: TrudeColors.textMuted)
          else if (player.autoPilot)
            const Icon(Icons.smart_toy,
                size: 14, color: TrudeColors.textMuted),
        ],
      ),
    );
  }

  /// A tiny ivory card-stack pictogram beside the count. An empty hand on a
  /// player still in the round goes brass — it forces the responder to check.
  Widget _countChip(int count) {
    final emptyButIn = count == 0 && !widget.player.isOut;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: emptyButIn ? TrudeColors.brass : TrudeColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(13, 13),
            painter: _CardStackIconPainter(),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: emptyButIn
                  ? TrudeColors.brassBright
                  : TrudeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rotating brass sweep with a soft outer glow around the active player.
///
/// Perf: no MaskFilter.blur (a saveLayer per frame on some backends) — the
/// glow is two concentric un-blurred sweep strokes under the crisp ring. The
/// shaders are built once, statically, WITHOUT GradientRotation (the ring is
/// a const 52px square); the canvas rotates instead, so nothing is recreated
/// per frame.
class _TurnRingPainter extends CustomPainter {
  _TurnRingPainter({required this.rotation});

  final double rotation;

  static final Rect _shaderRect =
      (Offset.zero & const Size.square(52)).deflate(1.5);

  static final Shader _ringShader = SweepGradient(
    colors: [
      TrudeColors.brass.withValues(alpha: 0.05),
      TrudeColors.brassBright,
      TrudeColors.brass.withValues(alpha: 0.05),
    ],
    stops: const [0.0, 0.55, 1.0],
  ).createShader(_shaderRect);

  /// Wide, faint halo stroke (outer part of the old blur).
  static final Shader _glowWideShader = SweepGradient(
    colors: [
      TrudeColors.brassBright.withValues(alpha: 0.0),
      TrudeColors.brassBright.withValues(alpha: 0.14),
      TrudeColors.brassBright.withValues(alpha: 0.0),
    ],
    stops: const [0.0, 0.55, 1.0],
  ).createShader(_shaderRect);

  /// Narrower, stronger core glow stroke (inner part of the old blur).
  static final Shader _glowMidShader = SweepGradient(
    colors: [
      TrudeColors.brassBright.withValues(alpha: 0.0),
      TrudeColors.brassBright.withValues(alpha: 0.22),
      TrudeColors.brassBright.withValues(alpha: 0.0),
    ],
    stops: const [0.0, 0.55, 1.0],
  ).createShader(_shaderRect);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final center = rect.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    // Layered un-blurred glow underneath, then the crisp brass sweep.
    final glowWide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..shader = _glowWideShader;
    canvas.drawArc(rect, 0, 2 * pi, false, glowWide);

    final glowMid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..shader = _glowMidShader;
    canvas.drawArc(rect, 0, 2 * pi, false, glowMid);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = _ringShader;
    canvas.drawArc(rect, 0, 2 * pi, false, ring);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_TurnRingPainter old) => old.rotation != rotation;
}

/// The static brass bezel around every portrait.
class _PortraitFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final bezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = const SweepGradient(
        colors: [
          TrudeColors.brassDark,
          TrudeColors.brassBright,
          TrudeColors.brass,
          TrudeColors.brassDark,
        ],
        stops: [0.0, 0.25, 0.6, 1.0],
      ).createShader(rect);
    canvas.drawOval(rect, bezel);

    // Inner recess shadow where the portrait sinks into the bezel.
    final recess = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TrudeColors.midnight.withValues(alpha: 0.5);
    canvas.drawOval(rect.deflate(1.4), recess);
  }

  @override
  bool shouldRepaint(_PortraitFramePainter old) => false;
}

/// Three tiny fanned ivory cards — the count chip pictogram.
class _CardStackIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cardW = size.width * 0.62;
    final cardH = size.height * 0.86;
    final fill = Paint()..color = TrudeColors.ivory;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = TrudeColors.inkBlack.withValues(alpha: 0.55);

    final center = Offset(size.width / 2, size.height / 2);
    for (final angle in [-0.22, 0.0, 0.22]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: cardW, height: cardH),
        const Radius.circular(1.6),
      );
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, edge);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CardStackIconPainter old) => false;
}
