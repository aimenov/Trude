/// Client-side rating tier table (display only — the server never sees
/// tiers). Thresholds are the plan's canonical numbers:
/// Новичок <1100, Картёжник 1100+, Плут 1250+, Шулер 1450+, Катала 1700+,
/// Легенда салона 2000+. Tier *names* live in the ARBs under the ICU keys
/// used here ([Strings.tierName]).
library;

class RatingTier {
  const RatingTier(this.key, this.minRating);

  /// ICU select key for [Strings.tierName].
  final String key;

  /// Inclusive lower bound.
  final int minRating;
}

/// Ascending by [RatingTier.minRating].
const kRatingTiers = <RatingTier>[
  RatingTier('novice', 0),
  RatingTier('cardplayer', 1100),
  RatingTier('rogue', 1250),
  RatingTier('sharp', 1450),
  RatingTier('hustler', 1700),
  RatingTier('legend', 2000),
];

/// Index into [kRatingTiers] for [rating] (0 = Новичок).
int tierIndexFor(int rating) {
  var index = 0;
  for (var i = 0; i < kRatingTiers.length; i++) {
    if (rating >= kRatingTiers[i].minRating) index = i;
  }
  return index;
}

/// The tier a [rating] falls into.
RatingTier tierFor(int rating) => kRatingTiers[tierIndexFor(rating)];
