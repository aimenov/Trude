import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error returned by the Colyseus matchmake HTTP API (`{ error, code }` body).
class MatchmakeException implements Exception {
  MatchmakeException(this.message, {this.code, this.httpStatus});

  final String message;
  final int? code;
  final int? httpStatus;

  @override
  String toString() => 'MatchmakeException(code: $code, http: $httpStatus): $message';
}

/// Seat reservation returned by `POST /matchmake/<method>/<roomNameOrId>`.
class SeatReservation {
  SeatReservation({
    required this.roomId,
    required this.processId,
    required this.roomName,
    required this.sessionId,
    this.reconnectionToken,
  });

  factory SeatReservation.fromJson(Map<String, dynamic> json) {
    final room = (json['room'] as Map).cast<String, dynamic>();
    return SeatReservation(
      roomId: room['roomId'] as String,
      processId: room['processId'] as String,
      roomName: (room['name'] as String?) ?? '',
      sessionId: json['sessionId'] as String,
      reconnectionToken: json['reconnectionToken'] as String?,
    );
  }

  final String roomId;
  final String processId;
  final String roomName;
  final String sessionId;

  /// Token half of "roomId:token" — only set on `reconnect` reservations; it
  /// must be forwarded as a `reconnectionToken` query param on the WS URL.
  final String? reconnectionToken;
}

/// Minimal Colyseus 0.16 matchmake client.
///
/// Mirrors colyseus.js `Client.createMatchMakeRequest`: a POST to
/// `/matchmake/{method}/{roomNameOrId}` whose JSON body is the join options
/// (our server reads the auth JWT from `options.token`).
class MatchmakeClient {
  MatchmakeClient(this.baseUri, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// e.g. `Uri.parse('http://127.0.0.1:2567')`
  final Uri baseUri;
  final http.Client _http;

  Future<SeatReservation> create(String roomName, Map<String, dynamic> options) =>
      _request('create', roomName, options);

  Future<SeatReservation> joinOrCreate(String roomName, Map<String, dynamic> options) =>
      _request('joinOrCreate', roomName, options);

  Future<SeatReservation> join(String roomName, Map<String, dynamic> options) =>
      _request('join', roomName, options);

  Future<SeatReservation> joinById(String roomId, Map<String, dynamic> options) =>
      _request('joinById', roomId, options);

  /// [reconnectionToken] is the full `roomId:token` string stored by
  /// `RoomConnection` after a successful join.
  Future<SeatReservation> reconnect(String reconnectionToken) {
    final i = reconnectionToken.indexOf(':');
    if (i <= 0 || i == reconnectionToken.length - 1) {
      throw ArgumentError.value(
          reconnectionToken, 'reconnectionToken', 'expected "roomId:token"');
    }
    final roomId = reconnectionToken.substring(0, i);
    final token = reconnectionToken.substring(i + 1);
    return _request('reconnect', roomId, {'reconnectionToken': token},
        forwardReconnectionToken: token);
  }

  Future<SeatReservation> _request(
    String method,
    String roomNameOrId,
    Map<String, dynamic> options, {
    String? forwardReconnectionToken,
  }) async {
    final uri = baseUri.resolve('/matchmake/$method/$roomNameOrId');
    final res = await _http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(options),
    );

    dynamic body;
    try {
      body = jsonDecode(res.body);
    } catch (_) {
      throw MatchmakeException('Non-JSON matchmake response: ${res.body}',
          httpStatus: res.statusCode);
    }

    if (body is Map && body['error'] != null) {
      throw MatchmakeException(body['error'].toString(),
          code: (body['code'] as num?)?.toInt(), httpStatus: res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw MatchmakeException('Matchmake HTTP ${res.statusCode}',
          httpStatus: res.statusCode);
    }

    final reservation =
        SeatReservation.fromJson((body as Map).cast<String, dynamic>());
    if (forwardReconnectionToken == null) return reservation;
    // colyseus.js forwards the token onto the reservation for reconnects so
    // buildEndpoint() adds it to the WS query string; the server validates it
    // in `hasReservedSeat(sessionId, reconnectionToken)`.
    return SeatReservation(
      roomId: reservation.roomId,
      processId: reservation.processId,
      roomName: reservation.roomName,
      sessionId: reservation.sessionId,
      reconnectionToken: forwardReconnectionToken,
    );
  }

  void close() => _http.close();
}
