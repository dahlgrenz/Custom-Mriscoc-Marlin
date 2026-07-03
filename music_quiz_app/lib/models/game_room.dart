import 'player.dart';
import 'track.dart';

enum RoomStatus { lobby, playing, finished }

/// Den nuvarande rundan: vilken låt som spelas och vems tur det är.
/// [track.year] hålls dolt i UI:t tills [revealed] blir true.
class GameRound {
  final Track track;
  final String activePlayerId;
  final bool revealed;

  const GameRound({
    required this.track,
    required this.activePlayerId,
    this.revealed = false,
  });

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'activePlayerId': activePlayerId,
        'revealed': revealed,
      };

  factory GameRound.fromJson(Map<String, dynamic> json) => GameRound(
        track: Track.fromJson(Map<String, dynamic>.from(json['track'] as Map)),
        activePlayerId: json['activePlayerId'] as String,
        revealed: json['revealed'] as bool? ?? false,
      );
}

/// Hela speltillståndet för ett rum — serverns sanningskälla.
class GameRoom {
  final String code;
  final String hostId;
  final RoomStatus status;
  final int targetCards;
  final String playlistId;
  final Map<String, Player> players;
  final List<String> turnOrder;
  final int turnIndex;
  final GameRound? currentRound;

  const GameRoom({
    required this.code,
    required this.hostId,
    required this.status,
    required this.targetCards,
    required this.playlistId,
    required this.players,
    this.turnOrder = const [],
    this.turnIndex = 0,
    this.currentRound,
  });

  String? get activePlayerId =>
      turnOrder.isEmpty ? null : turnOrder[turnIndex % turnOrder.length];

  Player? get winner {
    for (final p in players.values) {
      if (p.timeline.length >= targetCards) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'hostId': hostId,
        'status': status.name,
        'targetCards': targetCards,
        'playlistId': playlistId,
        'players': {for (final e in players.entries) e.key: e.value.toJson()},
        'turnOrder': turnOrder,
        'turnIndex': turnIndex,
        'currentRound': currentRound?.toJson(),
      };

  factory GameRoom.fromJson(Map<String, dynamic> json) {
    final rawPlayers = (json['players'] as Map?) ?? {};
    final rawTurnOrder = (json['turnOrder'] as List?) ?? [];
    return GameRoom(
      code: json['code'] as String,
      hostId: json['hostId'] as String,
      status: RoomStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RoomStatus.lobby,
      ),
      targetCards: (json['targetCards'] as num?)?.toInt() ?? 10,
      playlistId: json['playlistId'] as String? ?? '',
      players: {
        for (final e in rawPlayers.entries)
          '${e.key}': Player.fromJson(Map<String, dynamic>.from(e.value as Map)),
      },
      turnOrder: [for (final id in rawTurnOrder) '$id'],
      turnIndex: (json['turnIndex'] as num?)?.toInt() ?? 0,
      currentRound: json['currentRound'] == null
          ? null
          : GameRound.fromJson(
              Map<String, dynamic>.from(json['currentRound'] as Map)),
    );
  }
}
