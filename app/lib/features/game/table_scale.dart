/// Responsive scale for the center-table typography.
library;

import 'dart:math';

import 'package:flutter/widgets.dart';

/// Uniform scale factor for the center-table texts (pile labels, claim
/// plaque, retired rail, turn line, event strip, and the claim/verdict
/// overlays).
///
/// Derived from the window size against a 420×760 phone reference via
/// [MediaQuery.sizeOf]: phones stay at exactly 1.0 (mobile layout is
/// unchanged), while larger web/desktop windows scale up to at most 1.5.
/// Taking the min of both axes keeps short-but-wide windows from inflating
/// vertically tight areas.
double tableScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return min(size.width / 420, size.height / 760).clamp(1.0, 1.5);
}
