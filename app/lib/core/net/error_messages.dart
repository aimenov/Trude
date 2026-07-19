/// Maps room join/create failures to friendly, localized text.
///
/// Raw exceptions (`TrudeApiException(404): …`, `MatchmakeException(…)`)
/// must never reach a SnackBar — everything funnels through
/// [friendlyRoomError], which only ever returns [Strings] values.
library;

import '../strings.dart';
import 'trude_client.dart';

/// Colyseus `ErrorCode.MATCHMAKE_INVALID_ROOM_ID` — thrown by `joinById` both
/// for an unknown roomId (`room "x" not found`) and for a locked room
/// (`room "x" is locked`); a room auto-locks when it fills, so the message
/// text disambiguates the two.
const _matchmakeInvalidRoomId = 4212;

/// A short human sentence for a failed room create/join; never leaks the
/// exception's own text or class name.
String friendlyRoomError(Object e, {required bool creating}) {
  final generic =
      creating ? Strings.createFailedGeneric : Strings.joinFailedGeneric;

  // /rooms/by-code/:code lookup: unknown code -> 404.
  if (e is TrudeApiException) {
    return e.statusCode == 404 ? Strings.roomNotFound : generic;
  }

  if (e is MatchmakeException) {
    final message = e.message.toLowerCase();
    // Full rooms lock themselves (Colyseus autoLock at maxClients); the
    // server's own onJoin guard says "Room is full".
    if (message.contains('locked') || message.contains('full')) {
      return Strings.roomFull;
    }
    if (e.code == _matchmakeInvalidRoomId) return Strings.roomNotFound;
    return generic;
  }

  return generic;
}
