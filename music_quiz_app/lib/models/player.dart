import 'track.dart';

/// Statistik över en spelares svar under matchen (för slutbilden).
class PlayerStats {
  final int perfect; // fullpott (5 p i årtal, rätt placering i tidslinje)
  final int threes; // 3 p (nära) i årtalsläget
  final int ones; // 1 p ("ettor") i årtalsläget
  final int misses; // 0 p / fel placering
  final int steals; // lyckade stölder (tidslinjeläget)

  const PlayerStats({
    this.perfect = 0,
    this.threes = 0,
    this.ones = 0,
    this.misses = 0,
    this.steals = 0,
  });

  PlayerStats copyWith({
    int? perfect,
    int? threes,
    int? ones,
    int? misses,
    int? steals,
  }) =>
      PlayerStats(
        perfect: perfect ?? this.perfect,
        threes: threes ?? this.threes,
        ones: ones ?? this.ones,
        misses: misses ?? this.misses,
        steals: steals ?? this.steals,
      );

  Map<String, dynamic> toJson() => {
        'perfect': perfect,
        'threes': threes,
        'ones': ones,
        'misses': misses,
        'steals': steals,
      };

  factory PlayerStats.fromJson(Map<String, dynamic>? j) => j == null
      ? const PlayerStats()
      : PlayerStats(
          perfect: (j['perfect'] as num?)?.toInt() ?? 0,
          threes: (j['threes'] as num?)?.toInt() ?? 0,
          ones: (j['ones'] as num?)?.toInt() ?? 0,
          misses: (j['misses'] as num?)?.toInt() ?? 0,
          steals: (j['steals'] as num?)?.toInt() ?? 0,
        );
}

/// En spelare i ett rum. Spelarens [id] är Firebase-auth-uid:t.
/// [timeline] är spelarens korrekt placerade kort, sorterade efter år (stigande).
class Player {
  final String id;
  final String name;

  /// Emoji-avatar som representerar spelaren i UI:t.
  final String avatar;
  final int score;
  final List<Track> timeline;

  /// Minuspoäng som värden gett spelaren (handikapp för en riktigt duktig spelare).
  final int handicap;

  final PlayerStats stats;

  const Player({
    required this.id,
    required this.name,
    this.avatar = '🎧',
    this.score = 0,
    this.timeline = const [],
    this.handicap = 0,
    this.stats = const PlayerStats(),
  });

  Player copyWith({
    int? score,
    List<Track>? timeline,
    int? handicap,
    PlayerStats? stats,
  }) =>
      Player(
        id: id,
        name: name,
        avatar: avatar,
        score: score ?? this.score,
        timeline: timeline ?? this.timeline,
        handicap: handicap ?? this.handicap,
        stats: stats ?? this.stats,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'score': score,
        'handicap': handicap,
        'stats': stats.toJson(),
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
      handicap: (json['handicap'] as num?)?.toInt() ?? 0,
      stats: PlayerStats.fromJson(json['stats'] == null
          ? null
          : Map<String, dynamic>.from(json['stats'] as Map)),
    );
  }
}
