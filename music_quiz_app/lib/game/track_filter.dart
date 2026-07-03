import '../models/track.dart';

/// Ett filter som begränsar vilka låtar som ingår i spelet. Rena, testbara
/// regler utan beroenden. Tomma fält = ingen begränsning på den dimensionen.
class TrackFilter {
  /// Startår för valda årtionden, t.ex. {1980, 1990}.
  final Set<int> decades;

  /// Genrer (från Spotify) — träff om låten har någon av dem.
  final Set<String> genres;

  /// Kuraterade taggar (t.ex. "melodifestivalen", "land=se").
  final Set<String> tags;

  /// Fritext mot artistnamnet (skiftlägesokänsligt).
  final String artistQuery;

  /// Lägsta Spotify-popularitet (0 = av).
  final int minPopularity;

  const TrackFilter({
    this.decades = const {},
    this.genres = const {},
    this.tags = const {},
    this.artistQuery = '',
    this.minPopularity = 0,
  });

  bool get isActive =>
      decades.isNotEmpty ||
      genres.isNotEmpty ||
      tags.isNotEmpty ||
      artistQuery.trim().isNotEmpty ||
      minPopularity > 0;

  bool matches(Track t) {
    if (decades.isNotEmpty && !decades.contains(t.decade)) return false;
    if (genres.isNotEmpty && !t.genres.any(genres.contains)) return false;
    if (tags.isNotEmpty && !t.tags.any(tags.contains)) return false;
    if (minPopularity > 0 && t.popularity < minPopularity) return false;
    final q = artistQuery.trim().toLowerCase();
    if (q.isNotEmpty && !t.artist.toLowerCase().contains(q)) return false;
    return true;
  }

  List<Track> apply(List<Track> tracks) =>
      tracks.where(matches).toList(growable: false);

  TrackFilter copyWith({
    Set<int>? decades,
    Set<String>? genres,
    Set<String>? tags,
    String? artistQuery,
    int? minPopularity,
  }) =>
      TrackFilter(
        decades: decades ?? this.decades,
        genres: genres ?? this.genres,
        tags: tags ?? this.tags,
        artistQuery: artistQuery ?? this.artistQuery,
        minPopularity: minPopularity ?? this.minPopularity,
      );

  /// Kort sammanfattning för UI:t (t.ex. "80-tal, 90-tal · pop · artist: abba").
  String get summary {
    final parts = <String>[];
    if (decades.isNotEmpty) {
      final sorted = decades.toList()..sort();
      parts.add(sorted.map((d) => '$d-tal').join(', '));
    }
    if (genres.isNotEmpty) parts.add(genres.join(', '));
    if (tags.isNotEmpty) parts.add(tags.join(', '));
    if (minPopularity > 0) parts.add('populäritet ≥ $minPopularity');
    if (artistQuery.trim().isNotEmpty) parts.add('artist: ${artistQuery.trim()}');
    return parts.isEmpty ? 'Inget filter' : parts.join(' · ');
  }
}
