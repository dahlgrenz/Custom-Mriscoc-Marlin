import 'track.dart';

/// En spelare i ett rum. Spelarens [id] är Firebase-auth-uid:t.
/// [timeline] är spelarens korrekt placerade kort, sorterade efter år (stigande).
class Player {
  final String id;
  final String name;

  /// Emoji-avatar som representerar spelaren i UI:t.
  final String avatar;
  final int score;
  final List<Track> timeline;

  const Player({
    required this.id,
    required this.name,
    this.avatar = '🎧',
    this.score = 0,
    this.timeline = const [],
  });

  Player copyWith({int? score, List<Track>? timeline}) => Player(
        id: id,
        name: name,
        avatar: avatar,
        score: score ?? this.score,
        timeline: timeline ?? this.timeline,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'score': score,
        // Firebase gillar map framför list; nyckla på index för stabil ordning.
        'timeline': {
          for (var i = 0; i < timeline.length; i++) '$i': timeline[i].toJson(),
        },
      };

  factory Player.fromJson(Map<String, dynamic> json) {
    final rawTimeline = json['timeline'];
    final tracks = <Track>[];
    if (rawTimeline is Map) {
      final entries = rawTimeline.entries.toList()
        ..sort((a, b) => int.parse('${a.key}').compareTo(int.parse('${b.key}')));
      for (final e in entries) {
        tracks.add(Track.fromJson(Map<String, dynamic>.from(e.value as Map)));
      }
    }
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      avatar: json['avatar'] as String? ?? '🎧',
      score: (json['score'] as num?)?.toInt() ?? 0,
      timeline: tracks,
    );
  }
}
