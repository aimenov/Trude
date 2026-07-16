# Audio assets — provenance & licenses

## Naming convention

`<cueName>_<n>.<ext>` where `cueName` matches an `SfxCue` enum value
(`lib/core/audio/sfx_backend.dart`) exactly, e.g. `cardLand_1.ogg`.
The backend discovers variants at runtime from the AssetManifest, so files
can be added/removed here without touching Dart code.

## Kenney "Casino Audio" pack (CC0)

- Source: https://kenney.nl/assets/casino-audio
- Zip downloaded: https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip
- Author: Kenney Vleugels (Kenney.nl), pack version 1.1
- License: Creative Commons Zero (CC0) — http://creativecommons.org/publicdomain/zero/1.0/
  The pack's bundled `License.txt` states: "You may use these assets in
  personal and commercial projects. Credit (Kenney or www.kenney.nl) would
  be nice but is not mandatory."

Files taken from this pack (renamed, otherwise unmodified):

| Shipped file      | Original in pack      |
| ----------------- | --------------------- |
| `shuffle_1.ogg`   | `card-shuffle.ogg`    |
| `shuffle_2.ogg`   | `card-fan-1.ogg`      |
| `shuffle_3.ogg`   | `card-fan-2.ogg`      |
| `cardLand_1.ogg`  | `card-place-1.ogg`    |
| `cardLand_2.ogg`  | `card-place-2.ogg`    |
| `cardLand_3.ogg`  | `card-place-3.ogg`    |
| `cardThrow_1.ogg` | `card-shove-1.ogg`    |
| `cardThrow_2.ogg` | `card-shove-2.ogg`    |
| `cardThrow_3.ogg` | `card-shove-3.ogg`    |
| `cardSlide_1.ogg` | `card-slide-1.ogg`    |
| `cardSlide_2.ogg` | `card-slide-2.ogg`    |
| `cardSlide_3.ogg` | `card-slide-3.ogg`    |
| `flipSnap_1.ogg`  | `card-place-4.ogg`    |
| `flipSnap_2.ogg`  | `card-place-2.ogg`    |

## Synthesized cues

All `.wav` files here (claimStamp, revealTension, verdictTruth, verdictLie,
pilePickup, quadFanfare, jokerReveal, yourTurn, timerUrgent, reactionPop,
uiTap) are generated offline by `tool/render_sfx.dart` (pure-Dart PCM
synthesis, deterministic/seeded — re-run with `dart run tool/render_sfx.dart`)
and are original works of this project — no third-party material.

The card cues (shuffle, cardThrow, cardLand, cardSlide, flipSnap) ship as the
Kenney `.ogg` samples above; the renderer's synth fallbacks for those cues
were removed at integration time since the CC0 samples were sourced
successfully.
