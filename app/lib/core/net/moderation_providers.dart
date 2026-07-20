/// Riverpod providers for player moderation: the blocked-user set that drives
/// client-side nickname masking and reaction suppression, the full block list
/// for the management screen, and the masking helpers themselves.
///
/// Enforcement (join rejection) is server-side; masking is client-side v1 —
/// game broadcasts are shared, so blocked players' nicknames still arrive on
/// the wire and every render site funnels through [maskedNickname] /
/// [maskedInitial] instead.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../strings.dart';
import 'connection_providers.dart';

export 'trude_client.dart' show BlockEntry;

/// UserIds this user has blocked. Seeds itself from `GET /me/blocks` (after
/// ensuring the guest session, like `meProvider`); starts empty until the
/// fetch lands, so masking simply switches on when the set arrives.
///
/// [BlockedIdsController.block] / [BlockedIdsController.unblock] apply
/// optimistically and revert (and rethrow) on server error.
final blockedIdsProvider =
    NotifierProvider<BlockedIdsController, Set<String>>(
        BlockedIdsController.new);

class BlockedIdsController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    var alive = true;
    ref.onDispose(() => alive = false);
    // Seed outside the synchronous build window (ensure() may log in,
    // writing session/identity providers — see meta_providers.dart).
    Future(() async {
      try {
        await ref.read(sessionProvider.notifier).ensure();
        final blocks = await ref.read(trudeClientProvider).getBlocks();
        if (alive) state = {for (final b in blocks) b.userId};
      } catch (_) {
        // Seed is best-effort: masking stays off, optimistic ops still work.
      }
    });
    return const {};
  }

  /// Optimistic block: masks instantly, then `POST /me/blocks`; reverts and
  /// rethrows on failure so callers can surface an error.
  Future<void> block(String userId) async {
    if (state.contains(userId)) return; // already blocked — idempotent
    final previous = state;
    state = {...previous, userId};
    try {
      await ref.read(trudeClientProvider).blockUser(userId);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  /// Optimistic unblock: unmasks instantly, then `DELETE /me/blocks/:userId`;
  /// reverts and rethrows on failure.
  Future<void> unblock(String userId) async {
    if (!state.contains(userId)) return; // not blocked — idempotent
    final previous = state;
    state = {...previous}..remove(userId);
    try {
      await ref.read(trudeClientProvider).unblockUser(userId);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// Full `GET /me/blocks` entries (nickname + date) for the management screen.
/// Refresh with `ref.invalidate(blockedListProvider)` after an unblock.
final blockedListProvider = FutureProvider<List<BlockEntry>>((ref) async {
  await null;
  await ref.read(sessionProvider.notifier).ensure();
  return ref.read(trudeClientProvider).getBlocks();
});

/// The nickname to render for [userId]: [Strings.blockedPlayerName] when
/// blocked, the real [nickname] otherwise. Every nickname render site goes
/// through this (seats, plaques, turn line, results, leaderboard, lobby).
String maskedNickname(Set<String> blocked, String userId, String nickname) =>
    blocked.contains(userId) ? Strings.blockedPlayerName : nickname;

/// The avatar-portrait initial for [userId]: `'?'` when blocked (masking the
/// nickname but keeping its initial would leak it), otherwise the first
/// letter of [nickname] uppercased (`'?'` for an empty nickname).
String maskedInitial(Set<String> blocked, String userId, String nickname) {
  if (blocked.contains(userId)) return '?';
  return nickname.isEmpty ? '?' : nickname[0].toUpperCase();
}
