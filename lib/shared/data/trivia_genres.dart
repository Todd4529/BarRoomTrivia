/// All 20 Verified Human-Made Trivia Genres & Icon Mapping for Flutter Monorepo
class TriviaGenres {
  static const List<String> allGenres = [
    'Auto Select',
    'Random (Mixed)',
    '80s & 90s Nostalgia',
    'Art & Architecture',
    'Automotive & Racing',
    'Beer, Wine & Spirits',
    'Classic Literature',
    'Comics & Superheroes',
    'Food & Culinary',
    'Homebrewing Beer',
    'Mind Benders & Riddles',
    'Movies & Hollywood',
    'Mythology & Folklore',
    'Pop Culture & Music',
    'Rock & Roll Classics',
    'Science & Technology',
    'Sitcoms & TV Dramas',
    'Sports & Stadiums',
    'Video Games & Gaming',
    'Wildlife & Nature',
    'World Geography',
    'World History',
  ];

  static const Map<String, String> genreIconMap = {
    '80s & 90s Nostalgia': '📺',
    'Art & Architecture': '🎨',
    'Automotive & Racing': '🏎️',
    'Beer, Wine & Spirits': '🍻',
    'Classic Literature': '📚',
    'Comics & Superheroes': '🦸',
    'Food & Culinary': '🍕',
    'Homebrewing Beer': '🍺',
    'Mind Benders & Riddles': '🧠',
    'Movies & Hollywood': '🎬',
    'Mythology & Folklore': '🏛️',
    'Pop Culture & Music': '🎵',
    'Rock & Roll Classics': '🎸',
    'Science & Technology': '🧪',
    'Sitcoms & TV Dramas': '📺',
    'Sports & Stadiums': '⚽',
    'Video Games & Gaming': '🎮',
    'Wildlife & Nature': '🦁',
    'World Geography': '🌍',
    'World History': '📜',
    'Auto Select': '⚡',
    'Random (Mixed)': '🎲',
  };

  static String getIcon(String genre) {
    return genreIconMap[genre] ?? '💡';
  }
}
