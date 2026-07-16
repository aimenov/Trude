// Visual regression gallery for the "Midnight Parlor" redesign.
//
// Snapshots the painter-drawn deck (faces, back, selected/golden variants) at
// reveal and pile scales, the MyHand fan, and the nickname screen scaffold
// into test/goldens/*.png. Regenerate with:
//
//   flutter test test/visual_gallery_test.dart --update-goldens
//
// Goldens are rendered with the real bundled PlayfairDisplay faces so serif
// indices/marquees look like production; all other text uses the
// deterministic FlutterTest font.

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';
import 'package:trude/core/theme/trude_theme.dart';
import 'package:trude/features/game/widgets/card_widgets.dart';
import 'package:trude/features/game/widgets/my_hand.dart';
import 'package:trude/features/nickname/nickname_screen.dart';

Future<void> _loadFonts() async {
  final loader = FontLoader('PlayfairDisplay');
  for (final asset in const [
    'assets/fonts/PlayfairDisplay-Regular.ttf',
    'assets/fonts/PlayfairDisplay-Bold.ttf',
    'assets/fonts/PlayfairDisplay-Black.ttf',
    'assets/fonts/PlayfairDisplay-BoldItalic.ttf',
  ]) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

/// Felt-table stage: the gallery content over the same radial candlelight
/// gradient the real table uses, so ivory cards are judged against felt.
Widget _stage(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTrudeTheme(),
    home: RepaintBoundary(
      key: const ValueKey('stage'),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: TrudeGradients.feltLight),
        child: Center(child: child),
      ),
    ),
  );
}

Finder get _stageFinder => find.byKey(const ValueKey('stage'));

class _FakeStore implements GuestIdentityStore {
  GuestIdentity? _identity =
      GuestIdentity(deviceId: 'golden-device', nickname: 'Goldie');

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('card gallery at reveal scale (width 90)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(760, 720);
    addTearDown(tester.view.reset);

    const w = 90.0;
    await tester.pumpWidget(_stage(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: const [
            TrudeCardFace(rank: 'A', suit: 'S', width: w),
            TrudeCardFace(rank: 'K', suit: 'H', width: w),
            TrudeCardFace(rank: 'Q', suit: 'C', width: w),
            TrudeCardFace(rank: 'J', suit: 'D', width: w),
            TrudeCardFace(rank: '10', suit: 'S', width: w),
            TrudeCardFace(rank: '7', suit: 'H', width: w),
            TrudeCardFace(rank: '2', suit: 'C', width: w),
            TrudeCardFace(rank: 'JOKER', width: w),
            TrudeCardBack(width: w),
            TrudeCardFace(rank: '9', suit: 'D', width: w, selected: true),
            TrudeCardFace(rank: 'Q', suit: 'S', width: w, golden: true),
          ],
        ),
      ),
    ));
    await tester.pump();
    await expectLater(
        _stageFinder, matchesGoldenFile('goldens/card_gallery_w90.png'));
  });

  testWidgets('card gallery at pile scale (width 16)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(220, 120);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_stage(
      const Wrap(
        spacing: 10,
        alignment: WrapAlignment.center,
        children: [
          TrudeCardBack(width: 16),
          TrudeCardFace(rank: 'A', suit: 'S', width: 16),
          TrudeCardFace(rank: '10', suit: 'H', width: 16),
          TrudeCardFace(rank: 'JOKER', width: 16),
        ],
      ),
    ));
    await tester.pump();
    await expectLater(
        _stageFinder, matchesGoldenFile('goldens/card_gallery_w16.png'));
  });

  testWidgets('my hand fan with 8 cards, 2 selected', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(520, 180);
    addTearDown(tester.view.reset);

    final cards = [
      Card(id: 'c1', rank: 'A', suit: 'S'),
      Card(id: 'c2', rank: 'K', suit: 'H'),
      Card(id: 'c3', rank: 'Q', suit: 'D'),
      Card(id: 'c4', rank: 'J', suit: 'C'),
      Card(id: 'c5', rank: '10', suit: 'S'),
      Card(id: 'c6', rank: '9', suit: 'H'),
      Card(id: 'c7', rank: '7', suit: 'D'),
      Card(id: 'c8', rank: 'JOKER'),
    ];
    await tester.pumpWidget(_stage(
      SizedBox(
        width: 500,
        child: MyHandView(
          cards: cards,
          selectedIds: const {'c2', 'c5'},
          selectable: true,
          onToggle: (_, _) {},
          shiver: false,
          speed: AnimationSpeed.normal,
          onFlickThrow: () {},
        ),
      ),
    ));
    await tester.pump();
    await expectLater(
        _stageFinder, matchesGoldenFile('goldens/my_hand_fan.png'));
  });

  testWidgets('nickname screen scaffold', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTrudeTheme(),
        home: const RepaintBoundary(
          key: ValueKey('stage'),
          child: NicknameScreen(),
        ),
      ),
    ));
    // Play the one-shot entrance to its settled end state.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
        _stageFinder, matchesGoldenFile('goldens/nickname_screen.png'));
  });
}
