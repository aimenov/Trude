import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/net/connection_providers.dart';
import '../../core/strings.dart';
import '../achievements/achievement_art.dart';
import '../achievements/achievement_toast.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(Strings.resultsTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final entry in placements)
                  _placementTile(context, state, results!, entry),
                if (unlocked.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(Strings.unlockedThisGame,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in unlocked)
                        Chip(
                          avatar: Text(achievementEmoji(a.key),
                              style: const TextStyle(fontSize: 18)),
                          label: Text(
                              Strings.achievementTitle(a.key, a.title)),
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
                  child: FilledButton(
                    onPressed: () => context.go('/lobby'),
                    child: Text(Strings.stayForRematch),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
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
    );
  }

  Widget _placementTile(
    BuildContext context,
    ClientGameState state,
    GameOverEvent results,
    PlacementEntry entry,
  ) {
    final player = state.playerById(entry.userId);
    final nickname = player?.nickname ?? Strings.seatName(entry.seat);
    final isLoser = entry.userId == results.loserUserId;

    final stats = results.stats is Map ? results.stats as Map : const {};
    final playerStats =
        stats[entry.userId] is Map ? stats[entry.userId] as Map : const {};
    int stat(String key) => (playerStats[key] as num?)?.toInt() ?? 0;

    return ListTile(
      leading: Text(Strings.placementLabel(entry.placement),
          style: Theme.of(context).textTheme.titleLarge),
      title: Text(isLoser ? '$nickname ${Strings.loserMark}' : nickname),
      subtitle: Text(Strings.statsLine(
        stat('liesSurvived'),
        stat('liesCaught'),
        stat('checksWon'),
      )),
    );
  }
}
