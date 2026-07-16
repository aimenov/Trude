/// Typographic/emoji placeholder art for achievement badges, keyed by the
/// server catalog key (consistent with the rest of the app's placeholder
/// style; real art is a later asset milestone).
library;

const _emojiByKey = <String, String>{
  'best_liar': '\u{1F3AD}', // 🎭
  'pathological_truther': '\u{1F607}', // 😇
  'human_polygraph': '\u{1F50D}', // 🔍
  'gullible': '\u{1F41F}', // 🐟
  'poker_face': '\u{1F5FF}', // 🗿
  'smuggler': '\u{1F0CF}', // 🃏
  'hot_potato': '\u{1F954}', // 🥔
  'jokers_best_friend': '\u{1F921}', // 🤡
  'demolition_crew': '\u{1F4A3}', // 💣
  'comeback_season': '\u{1F4C8}', // 📈
  'serial_winner': '\u{1F3C6}', // 🏆
  'it_wasnt_me': '\u{1F925}', // 🤥
};

String achievementEmoji(String key) => _emojiByKey[key] ?? '\u{1F3C5}'; // 🏅
