import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'matchmake.dart';
import 'protocol_codes.dart';

/// A decoded ROOM_DATA message: `type` is the string the server used in
/// `client.send(type, payload)` / `room.broadcast(type, payload)`.
class RoomMessage {
  RoomMessage(this.type, this.data);

  final String type;

  /// msgpack-decoded payload, deep-converted so every map is
  /// `Map<String, dynamic>`. Null when the message carried no body.
  final dynamic data;

  @override
  String toString() => 'RoomMessage($type, $data)';
}

/// Transport-level ERROR frame (protocol code 11) — e.g. seat expiry or an
/// exception thrown by the room's onJoin. Distinct from our game's 'error'
/// ROOM_DATA message.
class RoomProtocolError implements Exception {
  RoomProtocolError(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'RoomProtocolError($code): $message';
}

/// A live WebSocket connection to one Colyseus room.
///
/// Speaks exactly the byte framing documented in [ProtocolCodes]; game state
/// sync frames (14/15/16) are ignored because the room's schema state is empty.
class RoomConnection {
  RoomConnection._(this._channel, this.roomId, this.sessionId);

  final WebSocketChannel _channel;
  final String roomId;
  final String sessionId;

  final _messages = StreamController<RoomMessage>.broadcast();
  final _errors = StreamController<RoomProtocolError>.broadcast();
  final _joined = Completer<void>();
  final _closed = Completer<void>();

  /// Full `roomId:token` reconnection token, set once the JOIN_ROOM frame is
  /// received. Pass to [MatchmakeClient.reconnect] after a disconnect.
  String? reconnectionToken;

  /// Serializer id announced in the join handshake (unused; state is empty).
  String? serializerId;

  bool _hasJoined = false;
  bool get isJoined => _hasJoined && !_closed.isCompleted;

  /// Broadcast stream of decoded ROOM_DATA messages.
  Stream<RoomMessage> get messages => _messages.stream;

  /// Broadcast stream of protocol-level ERROR frames.
  Stream<RoomProtocolError> get protocolErrors => _errors.stream;

  /// Completes when the socket closes (for any reason).
  Future<void> get onClose => _closed.future;

  /// Opens the WebSocket for [reservation] and completes once the JOIN_ROOM
  /// handshake finishes. [httpBase] is the server's HTTP origin
  /// (e.g. `http://127.0.0.1:2567`); ws/wss is derived from its scheme.
  static Future<RoomConnection> connect(
    Uri httpBase,
    SeatReservation reservation, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    var basePath = httpBase.path;
    if (basePath.endsWith('/')) basePath = basePath.substring(0, basePath.length - 1);
    // Mirrors colyseus.js buildEndpoint(): ws(s)://host[:port]{path}/{processId}/{roomId}?sessionId=...
    final wsUri = httpBase.replace(
      scheme: httpBase.scheme == 'https' ? 'wss' : 'ws',
      path: '$basePath/${reservation.processId}/${reservation.roomId}',
      queryParameters: {
        'sessionId': reservation.sessionId,
        if (reservation.reconnectionToken != null)
          'reconnectionToken': reservation.reconnectionToken!,
      },
    );

    final channel = WebSocketChannel.connect(wsUri);
    await channel.ready;
    final conn = RoomConnection._(channel, reservation.roomId, reservation.sessionId);
    conn._listen();
    await conn._joined.future.timeout(timeout);
    return conn;
  }

  void _listen() {
    _channel.stream.listen(
      (raw) {
        try {
          _onFrame(raw);
        } catch (e) {
          _errors.add(RoomProtocolError(-1, 'Failed to decode frame: $e'));
        }
      },
      onError: (Object e) {
        if (!_joined.isCompleted) _joined.completeError(e);
        _errors.add(RoomProtocolError(-1, e.toString()));
      },
      onDone: _handleClosed,
      cancelOnError: false,
    );
  }

  void _handleClosed() {
    if (!_joined.isCompleted) {
      _joined.completeError(RoomProtocolError(
        _channel.closeCode ?? -1,
        'Connection closed before join completed: ${_channel.closeReason ?? ''}',
      ));
    }
    if (!_closed.isCompleted) _closed.complete();
    _messages.close();
    _errors.close();
  }

  void _onFrame(dynamic raw) {
    if (raw is! List<int>) return; // text frames are never used by Colyseus
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    if (bytes.isEmpty) return;

    switch (bytes[0]) {
      case ProtocolCodes.joinRoom:
        _onJoinRoom(bytes);
      case ProtocolCodes.error:
        final r = _MsgpackReader(bytes, 1);
        final code = r.readNumber().toInt();
        final message = r.readString();
        final err = RoomProtocolError(code, message);
        if (!_joined.isCompleted) {
          _joined.completeError(err);
        } else {
          _errors.add(err);
        }
      case ProtocolCodes.leaveRoom:
        // Server asked us to leave: acknowledge and let it close the socket.
        leave();
      case ProtocolCodes.roomData:
        _onRoomData(bytes);
      default:
        // 14/15/16/17: schema state sync / byte messages — unused, ignored.
        break;
    }
  }

  void _onJoinRoom(Uint8List bytes) {
    // [10][u8 len][token utf8][u8 len][serializerId utf8][handshake...]
    var o = 1;
    final tokenLen = bytes[o++];
    final token = utf8.decode(bytes.sublist(o, o + tokenLen));
    o += tokenLen;
    final sidLen = bytes[o++];
    serializerId = utf8.decode(bytes.sublist(o, o + sidLen));
    // Remaining bytes are the schema handshake — ignored (empty room state).
    reconnectionToken = '$roomId:$token';
    _hasJoined = true;
    // Ack with a bare [10]; the server flushes enqueued messages only after this.
    _channel.sink.add(Uint8List.fromList(const [ProtocolCodes.joinRoom]));
    if (!_joined.isCompleted) _joined.complete();
  }

  void _onRoomData(Uint8List bytes) {
    final r = _MsgpackReader(bytes, 1);
    final type = r.isString() ? r.readString() : r.readNumber().toString();
    final data = r.offset < bytes.length
        ? _deepJson(msgpack.deserialize(Uint8List.sublistView(bytes, r.offset)))
        : null;
    _messages.add(RoomMessage(type, data));
  }

  /// Sends a ROOM_DATA message: `[13][msgpack str type][msgpack payload]`.
  /// The payload bytes are omitted entirely when [payload] is null, matching
  /// colyseus.js `room.send(type)` with no message.
  void send(String type, [Object? payload]) {
    if (_closed.isCompleted) throw StateError('Connection is closed');
    // The server decodes the type with @colyseus/schema decode.string, which
    // reads str16/str32 lengths little-endian; msgpack_dart writes them
    // big-endian. fixstr/str8 (< 256 utf8 bytes) are identical in both, and
    // every real message type is short — enforce that.
    assert(utf8.encode(type).length < 256, 'message type too long');
    final b = BytesBuilder(copy: false);
    b.addByte(ProtocolCodes.roomData);
    b.add(msgpack.serialize(type));
    if (payload != null) b.add(msgpack.serialize(payload));
    _channel.sink.add(b.takeBytes());
  }

  /// Consented leave: sends a bare LEAVE_ROOM byte and waits for the server to
  /// close the socket. Pass [consented] = false to just drop the connection
  /// (the server then holds the seat for reconnection).
  Future<void> leave({bool consented = true}) async {
    if (_closed.isCompleted) return;
    if (consented) {
      _channel.sink.add(Uint8List.fromList(const [ProtocolCodes.leaveRoom]));
      try {
        await onClose.timeout(const Duration(seconds: 5));
        return;
      } on TimeoutException {
        // fall through to a hard close
      }
    }
    await _channel.sink.close();
    if (!_closed.isCompleted) await onClose;
  }
}

/// Deep-converts msgpack_dart output (`Map<dynamic, dynamic>`) to JSON-shaped
/// `Map<String, dynamic>` / `List<dynamic>` so model fromJson code can cast.
dynamic _deepJson(dynamic v) {
  if (v is Map) {
    return v.map<String, dynamic>((k, val) => MapEntry(k.toString(), _deepJson(val)));
  }
  if (v is List) return v.map(_deepJson).toList();
  return v;
}

/// Just enough msgpack reading to walk the header values Colyseus writes with
/// @colyseus/schema `encode.string` / `encode.number`.
///
/// CAUTION: schema encode/decode use msgpack PREFIX bytes but write all
/// multi-byte integers/floats LITTLE-endian (standard msgpack is big-endian).
/// This only affects the ERROR frame's code/message and str16+/uint16+ header
/// fields; the actual message payload is packed by msgpackr (standard msgpack)
/// and is decoded with msgpack_dart instead.
class _MsgpackReader {
  _MsgpackReader(this.bytes, this.offset)
      : _view = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData _view;
  int offset;

  bool isString() {
    final p = bytes[offset];
    return (p > 0xa0 && p < 0xc0) || p == 0xd9 || p == 0xda || p == 0xdb;
  }

  String readString() {
    final prefix = bytes[offset++];
    int length;
    if (prefix < 0xc0) {
      length = prefix & 0x1f; // fixstr
    } else if (prefix == 0xd9) {
      length = bytes[offset++];
    } else if (prefix == 0xda) {
      length = _view.getUint16(offset, Endian.little);
      offset += 2;
    } else if (prefix == 0xdb) {
      length = _view.getUint32(offset, Endian.little);
      offset += 4;
    } else {
      throw FormatException('Not a msgpack string prefix: $prefix');
    }
    final s = utf8.decode(Uint8List.sublistView(bytes, offset, offset + length));
    offset += length;
    return s;
  }

  num readNumber() {
    final prefix = bytes[offset++];
    if (prefix < 0x80) return prefix; // positive fixint
    if (prefix > 0xdf) return prefix - 256; // negative fixint
    switch (prefix) {
      case 0xca:
        final v = _view.getFloat32(offset, Endian.little);
        offset += 4;
        return v;
      case 0xcb:
        final v = _view.getFloat64(offset, Endian.little);
        offset += 8;
        return v;
      case 0xcc:
        return bytes[offset++];
      case 0xcd:
        final v = _view.getUint16(offset, Endian.little);
        offset += 2;
        return v;
      case 0xce:
        final v = _view.getUint32(offset, Endian.little);
        offset += 4;
        return v;
      case 0xd0:
        final v = _view.getInt8(offset);
        offset += 1;
        return v;
      case 0xd1:
        final v = _view.getInt16(offset, Endian.little);
        offset += 2;
        return v;
      case 0xd2:
        final v = _view.getInt32(offset, Endian.little);
        offset += 4;
        return v;
      default:
        throw FormatException('Unsupported msgpack number prefix: $prefix');
    }
  }
}
