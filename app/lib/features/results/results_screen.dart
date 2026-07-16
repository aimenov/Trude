import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../achievements/achievement_art.dart';
import '../achievements/achievement_toast.dart';
import '../game/widgets/card_widgets.dart';
import '../home/parlor_widgets.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(currentRoomProvider, (prev, next) {
      if (next == null) context.go('/home');
    });

    final state = ref.watch(gameStateProvider);
    final results = state.lastResults;
    final placements = [...?results?.placements]
      ..sort((a, b) => a.placement.compareTo(b.placement));
    final unlocked = ref.watch(unlockedThisGameProvider);

    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(Strings.resultsTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final entry in placements)
                        _PlacementPlaque(
                          state: state,
                          results: results!,
                          entry: entry,
                        ),
                      if (unlocked.isNotEmpty) ...[
                        const EtchedDivider(),
                        Text(
                          Strings.unlockedThisGame,
                          textAlign: TextAlign.center,
                          style: TrudeType.etched.copyWith(
                              fontSize: 11, letterSpacing: 2.4),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final a in unlocked)
                              _UnlockChip(
                                emoji: achievementEmoji(a.key),
                                title:
                                    Strings.achievementTitle(a.key, a.title),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: BrassButton(
                          onPressed: () => context.go('/lobby'),
                          child: Text(Strings.stayForRematch,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56)),
                          onPressed: () async {
                            await ref
                                .read(currentRoomProvider.notifier)
                                .leaveRoom();
                            if (context.mounted) context.go('/home');
                          },
                          child: Text(Strings.leave),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One podium row: an engraved plaque with a placement medallion, serif name,
/// and etched stat line. First place gets the brass treatment; the joker
/// loser gets a spotlight ring and the joker card itself.
class _PlacementPlaque extends StatelessWidget {
  const _PlacementPlaque({
    required this.state,
    required this.results,
    required this.entry,
  });

  final ClientGameState state;
  final GameOverEvent results;
  final PlacementEntry entry;

  @override
  Widget build(BuildContext context) {
    final player = state.playerById(entry.userId);
    final nickname = player?.nickname ?? Strings.seatName(entry.seat);
    final isLoser = entry.userId == results.loserUserId;
    final isWinner = entry.placement == 1;

    final stats = results.stats is Map ? results.stats as Map : const {};
    final playerStats =
        stats[entry.userId] is Map ? stats[entry.userId] as Map : const {};
    int stat(String key) => (playerStats[key] as num?)?.toInt() ?? 0;

    final plaque = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: isWinner ? TrudeGradients.brass : null,
        color: isWinner ? null : TrudeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(
          color: isWinner
              ? TrudeColors.brassDark
              : (isLoser ? TrudeColors.brass : TrudeColors.hairline),
          width: isLoser ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _PlacementMedallion(entry: entry, isWinner: isWinner),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrudeType.display.copyWith(
                    fontSize: 17,
                    letterSpacing: 0.5,
                    color: isWinner
                        ? TrudeColors.textOnBrass
                        : TrudeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  Strings.statsLine(
                    stat('liesSurvived'),
                    stat('liesCaught'),
                    stat('checksWon'),
                  ),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: isWinner
                        ? TrudeColors.textOnBrass.withValues(alpha: 0.75)
                        : TrudeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isLoser) ...[
            const SizedBox(width: 10),
            const _JokerSpotlight(),
          ],
        ],
      ),
    );

    if (!isLoser) return plaque;
    // Spotlight wash behind the loser's plaque.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [
            TrudeColors.brassBright.withValues(alpha: 0.10),
            TrudeColors.brassBright.withValues(alpha: 0),
          ],
        ),
      ),
      child: plaque,
    );
  }
}

/// Engraved circular medallion with the placement label ("1st", "2nd", …).
class _PlacementMedallion extends StatelessWidget {
  const _PlacementMedallion({required this.entry, required this.isWinner});

  final PlacementEntry entry;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            isWinner ? TrudeColors.brassBright : TrudeColors.surfaceSunken,
        border: Border.all(
          color: isWinner ? TrudeColors.brassDark : TrudeColors.brassDark,
          width: isWinner ? 2 : 1.2,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isWinner
                ? TrudeColors.brassDark.withValues(alpha: 0.6)
                : TrudeColors.hairline,
          ),
        ),
        child: Center(
          child: Text(
            Strings.placementLabel(entry.placement),
            style: TrudeType.display.copyWith(
              fontSize: 13,
              letterSpacing: 0,
              color: isWinner
                  ? TrudeColors.textOnBrass
                  : TrudeColors.brassBright,
            ),
          ),
        ),
      ),
    );
  }
}

/// The joker card in a small spotlight ring — the loser's reveal.
class _JokerSpotlight extends StatelessWidget {
  const _JokerSpotlight();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            TrudeColors.jokerPurple.withValues(alpha: 0.35),
            TrudeColors.jokerPurple.withValues(alpha: 0),
          ],
        ),
        border: Border.all(
            color: TrudeColors.brass.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Transform.rotate(
        angle: 0.12,
        child: const TrudeCardFace(rank: 'JOKER', width: 26),
      ),
    );
  }
}

/// A small parlor chip for an achievement unlocked this game.
class _UnlockChip extends StatelessWidget {
  const _UnlockChip({required this.emoji, required this.title});

  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius + 6),
        border: Border.all(color: TrudeColors.brassDark),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 7),
          Text(
            title,
            style: TrudeType.cardIndex.copyWith(
                fontSize: 12.5, color: TrudeColors.brassBright),
          ),
        ],
      ),
    );
  }
}
