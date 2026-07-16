/// GlobalKey registry for the measured rects card flights travel between
/// (seat chips, pile, my hand, retired rail), plus a tiny signal bus for
/// effects that target a specific seat widget (the liar shake).
///
/// Face-down cards never have real ids on the wire — flights are identified
/// purely by (seat, ordinal) synthetic keys against these anchor rects.
library;

import 'package:flutter/widgets.dart';

/// A one-shot "shake this seat" pulse. A new instance per pulse so listeners
/// fire even for the same seat twice.
class SeatShake {
  SeatShake(this.seat);

  final int seat;
}

class TableAnchors {
  final pileKey = GlobalKey(debugLabel: 'pile');
  final handKey = GlobalKey(debugLabel: 'myHand');
  final retiredKey = GlobalKey(debugLabel: 'retiredRail');
  final _seatKeys = <int, GlobalKey>{};

  /// Fired by the reveal set piece; the matching SeatAvatar shakes.
  final shake = ValueNotifier<SeatShake?>(null);

  GlobalKey seatKey(int seat) =>
      _seatKeys.putIfAbsent(seat, () => GlobalKey(debugLabel: 'seat$seat'));

  Rect? rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? seatRect(int seat) => rectOf(seatKey(seat));
  Rect? get pileRect => rectOf(pileKey);
  Rect? get handRect => rectOf(handKey);
  Rect? get retiredRect => rectOf(retiredKey);

  /// Where a card leaves from / lands at for [seat]: my own seat maps to the
  /// hand area, everyone else to their seat chip.
  Rect? originForSeat(int seat, int mySeat) =>
      seat == mySeat ? (handRect ?? seatRect(seat)) : seatRect(seat);

  void dispose() => shake.dispose();
}
