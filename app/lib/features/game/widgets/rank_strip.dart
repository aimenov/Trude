/// Rank-claim strip for the lead throw: every nameable rank as a mini
/// card-corner tile in one horizontally scrollable row. The chosen tile wears
/// a brass border, a brassBright wash, and a slight lift; the rest sit flat
/// behind a hairline. Tapping a tile reports it via [RankStrip.onChosen].
library;

import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../anim/motion_spec.dart';

class RankStrip extends StatelessWidget {
  const RankStrip({
    super.key,
    required this.ranks,
    required this.chosen,
    required this.onChosen,
  });

  /// Nameable ranks, wire form (`"2".."10" | "J" | "Q" | "K" | "A"`), in
  /// display order. Retired ranks are simply absent.
  final List<String> ranks;

  /// The currently staged claim rank, or null when nothing is staged.
  final String? chosen;

  final ValueChanged<String> onChosen;

  // Mini card-corner tile geometry.
  static const _tileWidth = 34.0;
  static const _tileAspect = 1.3; // height / width
  static const _tileGap = 6.0;
  static const _chosenLift = 3.0; // dp the chosen tile rises
  static const _glyphPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 6);

  /// Chosen-state transition (border/wash/lift settle).
  static const _selectDuration = Duration(milliseconds: 140);
  static const _selectCurve = Curves.easeOutCubic;

  /// Entrance slide distance (dp, from below) for the fade/slide-in.
  static const _enterSlideDy = 10.0;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final strip = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < ranks.length; i++) ...[
            if (i > 0) const SizedBox(width: _tileGap),
            _tile(ranks[i], reduceMotion),
          ],
        ],
      ),
    );

    // Room for the chosen tile's lift so it never clips against the strip.
    final sized = SizedBox(
      height: _tileWidth * _tileAspect + _chosenLift,
      child: Align(alignment: Alignment.bottomCenter, child: strip),
    );

    if (reduceMotion) return sized;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionSpec.handCardEnter,
      curve: MotionSpec.handCardEnterCurve,
      child: sized,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, _enterSlideDy * (1 - t)),
          child: child,
        ),
      ),
    );
  }

  Widget _tile(String rank, bool reduceMotion) {
    final isChosen = rank == chosen;
    final duration = reduceMotion ? Duration.zero : _selectDuration;
    return Semantics(
      button: true,
      selected: isChosen,
      label: Strings.rankWord(rank),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChosen(rank),
        child: AnimatedContainer(
          duration: duration,
          curve: _selectCurve,
          width: _tileWidth,
          height: _tileWidth * _tileAspect,
          margin: EdgeInsets.only(
            top: isChosen ? 0 : _chosenLift,
            bottom: isChosen ? _chosenLift : 0,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isChosen
                ? Color.alphaBlend(
                    TrudeColors.brassBright.withValues(alpha: 0.28),
                    TrudeColors.ivory,
                  )
                : TrudeColors.ivory,
            borderRadius:
                BorderRadius.circular(_tileWidth * TrudeDims.cardRadiusFactor),
            border: Border.all(
              color: isChosen ? TrudeColors.brass : TrudeColors.hairline,
              width: isChosen ? 1.8 : TrudeDims.hairlineWidth,
            ),
            boxShadow: isChosen
                ? [
                    BoxShadow(
                      color: TrudeColors.midnight.withValues(alpha: 0.45),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Padding(
            padding: _glyphPadding,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(
                Strings.rankShort(rank),
                style: TrudeType.cardIndex.copyWith(
                  fontSize: 16,
                  color: TrudeColors.inkBlack,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
