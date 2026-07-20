/// The per-player actions bottom sheet: report (with a reason dialog), block /
/// unblock, and — when the lobby adds them — seat-swap and admin-only kick.
///
/// Reached by tapping a player anywhere their name shows: table seat avatars,
/// lobby seats, results rows, leaderboard rows. Never shown for self — the
/// entry point guards on the session's own userId.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connection_providers.dart';
import '../../core/net/moderation_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../home/parlor_widgets.dart';

/// Extra rows the lobby contributes: a seat-swap request for anyone, and a
/// kick for the room admin (the server enforces lobby-only + admin-only on
/// `kickPlayer` regardless — this only gates what's offered in the UI).
class PlayerActionsExtras {
  const PlayerActionsExtras({this.onRequestSwap, this.onKick});

  /// Sends the seat-swap request; the sheet closes first.
  final VoidCallback? onRequestSwap;

  /// Kicks the player (admin only — pass null otherwise); the sheet closes
  /// first.
  final VoidCallback? onKick;
}

/// Opens the actions sheet for [userId]/[nickname]. A no-op when [userId] is
/// the signed-in user — the parlor does not let you report yourself.
Future<void> showPlayerActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String nickname,
  PlayerActionsExtras? extras,
}) {
  if (ref.read(sessionProvider)?.userId == userId) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => PlayerActionsSheet(
      userId: userId,
      nickname: nickname,
      extras: extras,
    ),
  );
}

class PlayerActionsSheet extends ConsumerWidget {
  const PlayerActionsSheet({
    super.key,
    required this.userId,
    required this.nickname,
    this.extras,
  });

  final String userId;
  final String nickname;
  final PlayerActionsExtras? extras;

  /// «Пожаловаться» → reason dialog → POST /reports → «Жалоба отправлена».
  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(Strings.reportPlayer),
        children: [
          for (final (wire, label) in [
            ('nickname', Strings.reportReasonNickname),
            ('cheating', Strings.reportReasonCheating),
            ('abuse', Strings.reportReasonAbuse),
            ('other', Strings.reportReasonOther),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(wire),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await ref.read(sessionProvider.notifier).ensure();
      await ref.read(trudeClientProvider).reportPlayer(
            userId: userId,
            reason: reason,
            roomId: ref.read(currentRoomProvider)?.roomId,
          );
      messenger.showSnackBar(SnackBar(content: Text(Strings.reportSent)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(Strings.saveFailed('$e'))));
    }
    if (navigator.mounted) navigator.pop();
  }

  /// Optimistic block/unblock through [blockedIdsProvider]; the sheet closes
  /// either way, and a failed call surfaces as a snackbar (state reverted by
  /// the provider).
  Future<void> _toggleBlock(
      BuildContext context, WidgetRef ref, bool blocked) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sessionProvider.notifier).ensure();
      if (blocked) {
        await ref.read(blockedIdsProvider.notifier).unblock(userId);
      } else {
        await ref.read(blockedIdsProvider.notifier).block(userId);
        messenger
            .showSnackBar(SnackBar(content: Text(Strings.playerBlocked)));
      }
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(Strings.saveFailed('$e'))));
    }
    if (navigator.mounted) navigator.pop();
  }

  /// Closes the sheet, then runs the lobby-supplied action.
  void _popThen(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedIds = ref.watch(blockedIdsProvider);
    final blocked = blockedIds.contains(userId);
    const divider = Divider(height: 1, indent: 16, endIndent: 16);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ParlorPanel(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                maskedNickname(blockedIds, userId, nickname),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrudeType.display.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 10),
              if (extras?.onRequestSwap != null) ...[
                divider,
                ListTile(
                  leading: const Icon(Icons.swap_horiz,
                      color: TrudeColors.brassBright),
                  title: Text(Strings.requestSwap, style: _rowTitle),
                  onTap: () => _popThen(context, extras!.onRequestSwap!),
                ),
              ],
              divider,
              ListTile(
                leading: const Icon(Icons.outlined_flag,
                    color: TrudeColors.brassBright),
                title: Text(Strings.reportPlayer, style: _rowTitle),
                onTap: () => _report(context, ref),
              ),
              divider,
              // The destructive row wears the lie color, like the settings
              // delete-account tile.
              ListTile(
                leading: Icon(
                  blocked ? Icons.lock_open : Icons.block,
                  color: blocked ? TrudeColors.brassBright : TrudeColors.lie,
                ),
                title: Text(
                  blocked ? Strings.unblockPlayer : Strings.blockPlayer,
                  style: blocked
                      ? _rowTitle
                      : _rowTitle.copyWith(color: TrudeColors.lie),
                ),
                onTap: () => _toggleBlock(context, ref, blocked),
              ),
              if (extras?.onKick != null) ...[
                divider,
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined,
                      color: TrudeColors.lie),
                  title: Text(
                    Strings.kickPlayer,
                    style: _rowTitle.copyWith(color: TrudeColors.lie),
                  ),
                  onTap: () => _popThen(context, extras!.onKick!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static final _rowTitle = TrudeType.cardIndex.copyWith(
    fontSize: 15,
    letterSpacing: 0.3,
    color: TrudeColors.textPrimary,
  );
}
