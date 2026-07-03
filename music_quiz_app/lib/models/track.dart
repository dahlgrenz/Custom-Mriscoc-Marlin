/// En låt som spelas i quizet. Musikkälle-oberoende: [uri] är den identifierare
/// som den aktuella [MusicSource] behöver för uppspelning (för Spotify en spotify-URI).
class Track {
  final String id;
  final String uri;
  final String title;
  final String artist;

  /// Utgivningsår — det värde spelaren ska placera rätt i sin tidslinje.
  final int year;

  final String? albumArtUrl;

  /// Genrer (från Spotify-artisten) — används för filter.
  final List<String> genres;

  /// Spotify-popularitet 0–100 — används för "bara hits"-filter.
  final int popularity;

  /// Kuraterade taggar (från tag_data/*.csv), t.ex. "melodifestivalen",
  /// "land=se", "placering=1". Tomt om ingen matchning finns.
  final List<String> tags;

  const Track({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.year,
    this.albumArtUrl,
    this.genres = const [],
    this.popularity = 0,
    this.tags = const [],
  });

  Track copyWith({List<String>? genres, int? popularity, List<String>? tags}) =>
      Track(
        id: id,
        uri: uri,
        title: title,
        artist: artist,
        year: year,
        albumArtUrl: albumArtUrl,
        genres: genres ?? this.genres,
        popularity: popularity ?? this.popularity,
        tags: tags ?? this.tags,
      );

  /// Startåret för låtens årtionde, t.ex. 1994 → 1990.
  int get decade => year - (year % 10);

  Map<String, dynamic> toJson() => {
        'id': id,
        'uri': uri,
        'title': title,
        'artist': artist,
        'year': year,
        'albumArtUrl': albumArtUrl,
        if (genres.isNotEmpty) 'genres': genres,
        if (popularity > 0) 'popularity': popularity,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        uri: json['uri'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        year: (json['year'] as num).toInt(),
        albumArtUrl: json['albumArtUrl'] as String?,
        genres: _stringList(json['genres']),
        popularity: (json['popularity'] as num?)?.toInt() ?? 0,
        tags: _stringList(json['tags']),
      );

  static List<String> _stringList(dynamic v) {
    if (v is List) return [for (final e in v) '$e'];
    return const [];
  }
}
