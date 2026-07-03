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

  const Track({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.year,
    this.albumArtUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'uri': uri,
        'title': title,
        'artist': artist,
        'year': year,
        'albumArtUrl': albumArtUrl,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        uri: json['uri'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        year: (json['year'] as num).toInt(),
        albumArtUrl: json['albumArtUrl'] as String?,
      );
}
