/// Per-game economy rewards: holds the room's latest `rewards` message for
/// the results screen, mirroring the UnlockedThisGameController pattern
/// (achievement_toast.dart).
///
/// The room's broadcast streams do NOT replay, so this provider is
/// eager-bound in app.dart next to the renderedGameState listen — otherwise
/// a lazily-mounted results screen would miss the message.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/economy_providers.dart';

/// The `rewards` message of the game just finished; null before the first
/// gameOver and cleared again when the next game starts.
final rewardsThisGameProvider =
    NotifierProvider<RewardsThisGameController, RewardsMessage?>(
        RewardsThisGameController.new);

class RewardsThisGameController extends Notifier<RewardsMessage?> {
  @override
  RewardsMessage? build() {
    final room = ref.watch(currentRoomProvider);
    if (room != null) {
      final subs = [
        room.onRewards.listen(_onRewards),
        room.onEvents.listen((batch) {
          if (batch.events.any((e) => e is GameStartedEvent)) state = null;
        }),
      ];
      ref.onDispose(() {
        for (final s in subs) {
          s.cancel();
        }
      });
    }
    return null;
  }

  void _onRewards(RewardsMessage rewards) {
    state = rewards;
    // The message carries the post-award balance — snap the wallet to it
    // (authoritative; equals credit(coins) unless the mirror was stale).
    ref.read(walletProvider.notifier).set(rewards.balance);
    final newRating = rewards.newRating;
    if (rewards.rated && newRating != null) {
      ref.read(ratingProvider.notifier).set(newRating);
    }
  }

  /// Drops the held rewards (also happens automatically on gameStarted).
  void clear() => state = null;
}
