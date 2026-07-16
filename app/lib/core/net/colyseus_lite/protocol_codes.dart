/// Colyseus 0.16 wire protocol codes — the FIRST byte of every WebSocket
/// frame exchanged with the server (extracted from colyseus.js/lib/Protocol.js
/// and @colyseus/core/build/Protocol.js, both v0.16).
///
/// Frame layouts (all multi-byte values below are msgpack-encoded unless noted):
///
///   JOIN_ROOM  (server->client):
///     [10][u8 tokenLen][tokenLen bytes utf8 reconnectionToken]
///         [u8 serializerIdLen][serializerIdLen bytes utf8 serializerId]
///         [optional serializer handshake bytes — ignored, no schema state]
///   JOIN_ROOM  (client->server): single byte [10] — acks the join; the server
///     only flips the client to JOINED (and flushes queued messages) on this.
///   ERROR      (server->client): [11][msgpack int code][msgpack str message]
///   LEAVE_ROOM (both directions): single byte [12]
///   ROOM_DATA  (both directions): [13][msgpack str|int type][msgpack payload?]
///     (payload bytes are simply absent when the message carries no body)
///   ROOM_STATE / ROOM_STATE_PATCH (14/15): schema state sync — unused here.
///   ROOM_DATA_BYTES (17): [17][msgpack str|int type][raw bytes] — unused here.
abstract final class ProtocolCodes {
  static const int handshake = 9;
  static const int joinRoom = 10;
  static const int error = 11;
  static const int leaveRoom = 12;
  static const int roomData = 13;
  static const int roomState = 14;
  static const int roomStatePatch = 15;
  static const int roomDataSchema = 16;
  static const int roomDataBytes = 17;
}

/// Matchmaking error codes (colyseus.js/lib/Protocol.js `ErrorCode`).
abstract final class MatchmakeErrorCodes {
  static const int noHandler = 4210;
  static const int invalidCriteria = 4211;
  static const int invalidRoomId = 4212;
  static const int unhandled = 4213;
  static const int expired = 4214;
  static const int authFailed = 4215;
  static const int applicationError = 4216;
}
