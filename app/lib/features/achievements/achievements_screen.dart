import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/meta_models.dart';
import '../../core/net/meta_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../home/parlor_widgets.dart';
import 'achievement_art.dart';

/// Medallion grid from the server catalog: unlocked achievements as polished
/// brass medallions with their unlock date, locked ones as dark unpolished
/// versions with the description as hint.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider);
    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.achievementsTitle),
          leading: BackButton(onPressed: () => context.go('/home')),
          bottom: achievements.valueOrNull == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(24),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      Strings.achievementsCount(
                        achievements.valueOrNull!.unlocked.length,
                        achievements.valueOrNull!.catalog.length,
                      ),
                      style: TrudeType.etched.copyWith(
                          fontSize: 10.5, letterSpacing: 2),
                    ),
                  ),
                ),
        ),
        body: RefreshIndicator(
          color: TrudeColors.brass,
          backgroundColor: TrudeColors.surfaceRaised,
          onRefresh: () => ref.refresh(achievementsProvider.future),
          child: switch (achievements) {
            AsyncData(:final value) => _grid(context, value),
            AsyncError() => _scrollableMessage(
                context, Strings.achievementsLoadFailed),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  /// Pull-to-refresh needs a scrollable even for the error state.
  Widget _scrollableMessage(BuildContext context, String message) =>
      LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.8,
              child: Center(
                child: Text(message,
                    style: const TextStyle(color: TrudeColors.textMuted)),
              ),
            ),
          ],
        ),
      );

  Widget _grid(BuildContext context, MeAchievements data) {
    final unlockedByKey = data.unlockedByKey;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: data.catalog.length,
      itemBuilder: (context, i) {
        final info = data.catalog[i];
        return _MedallionCard(info: info, unlock: unlockedByKey[info.key]);
      },
    );
  }
}

class _MedallionCard extends StatelessWidget {
  const _MedallionCard({required this.info, required this.unlock});

  final AchievementInfo info;
  final AchievementUnlock? unlock;

  bool get _unlocked => unlock != null;

  @override
  Widget build(BuildContext context) {
    final title = Strings.achievementTitle(info.key, info.title);
    final description =
        Strings.achievementDescription(info.key, info.description);

    return Container(
      decoration: BoxDecoration(
        color: TrudeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(
          color: _unlocked
              ? TrudeColors.brass.withValues(alpha: 0.6)
              : TrudeColors.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Medallion(emoji: achievementEmoji(info.key), unlocked: _unlocked),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TrudeType.cardIndex.copyWith(
              fontSize: 13.5,
              letterSpacing: 0.3,
              color:
                  _unlocked ? TrudeColors.brassBright : TrudeColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _unlocked
                ? Strings.unlockedOn(unlock!.unlockedDate)
                : description,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              color: _unlocked
                  ? TrudeColors.textPrimary.withValues(alpha: 0.85)
                  : TrudeColors.textMuted.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// The engraved medallion: coin-edge notches, double brass ring, emoji
/// monogram. Locked medallions are dark, unpolished, and greyed out.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.emoji, required this.unlocked});

  final String emoji;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final glyph = Text(emoji, style: const TextStyle(fontSize: 26));
    return SizedBox(
      width: 60,
      height: 60,
      child: CustomPaint(
        painter: _MedallionPainter(unlocked: unlocked),
        child: Center(
          child: unlocked
              ? glyph
              : ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      TrudeColors.textMuted, BlendMode.srcIn),
                  child: Opacity(opacity: 0.45, child: glyph),
                ),
        ),
      ),
    );
  }
}

class _MedallionPainter extends CustomPainter {
  const _MedallionPainter({required this.unlocked});

  final bool unlocked;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;

    // Face: a soft dish from raised to sunken.
    final face = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.4),
        colors: unlocked
            ? [TrudeColors.surfaceRaised, TrudeColors.surfaceSunken]
            : [TrudeColors.surfaceSunken, TrudeColors.midnight],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r * 0.88, face);

    // Outer ring: brushed brass sweep when polished, dull when locked.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    if (unlocked) {
      ring.shader = const SweepGradient(
        colors: [
          TrudeColors.brassDark,
          TrudeColors.brassBright,
          TrudeColors.brass,
          TrudeColors.brassBright,
          TrudeColors.brassDark,
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    } else {
      ring.color = TrudeColors.brassDark.withValues(alpha: 0.45);
    }
    canvas.drawCircle(c, r - 1.5, ring);

    // Inner hairline ring.
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = unlocked
          ? TrudeColors.brass.withValues(alpha: 0.75)
          : TrudeColors.hairline;
    canvas.drawCircle(c, r * 0.76, inner);

    // Coin-edge notches around the rim.
    final notch = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = unlocked
          ? TrudeColors.brassDark
          : TrudeColors.brassDark.withValues(alpha: 0.3);
    const ticks = 28;
    for (var i = 0; i < ticks; i++) {
      final a = 2 * pi * i / ticks;
      final dir = Offset(cos(a), sin(a));
      canvas.drawLine(c + dir * (r - 4.2), c + dir * (r - 2.2), notch);
    }
  }

  @override
  bool shouldRepaint(covariant _MedallionPainter oldDelegate) =>
      oldDelegate.unlocked != unlocked;
}
