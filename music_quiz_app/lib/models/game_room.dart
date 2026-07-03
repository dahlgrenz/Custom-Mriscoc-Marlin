import 'player.dart';
import 'track.dart';

enum RoomStatus { lobby, playing, finished }

/// Rundans fas: den aktiva spelaren gissar först; om hen har fel får en
/// utmanare (nästa spelare) chansen att stjäla kortet.
enum RoundPhase { guessing, stealing }

/// Den nuvarande rundan: vilken låt som spelas och vems tur det är.
class GameRound {
  final Track track;
  final String activePlayerId;
  final RoundPhase phase;

  /// Vem som får stjäla när [phase] är [RoundPhase.stealing] (annars null).
  final String? stealerId;

  const GameRound({
    required this.track,
    required this.activePlayerId,
    this.phase = RoundPhase.guessing,
    this.stealerId,
  });

  /// Vem som får agera just nu (gissaren eller utmanaren).
  String get actorId =>
      phase == RoundPhase.stealing ? (stealerId ?? activePlayerId) : activePlayerId;

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'activePlayerId': activePlayerId,
        'phase': phase.name,
        'stealerId': stealerId,
      };

  factory GameRound.fromJson(Map<String, dynamic> json) => GameRound(
        track: Track.fromJson(Map<String, dynamic>.from(json['track'] as Map)),
        activePlayerId: json['activePlayerId'] as String,
        phase: RoundPhase.values.firstWhere(
          (p) => p.name == json['phase'],
          orElse: () => RoundPhase.guessing,
        ),
        stealerId: json['stealerId'] as String?,
      );
}

/// Hela speltillståndet för ett rum — serverns sanningskälla.
class GameRoom {
  final String code;
  final String hostId;
  final RoomStatus status;
  final int targetCards;
  final String playlistId;
  final String playlistName;
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
    this.playlistName = '',
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
        'playlistName': playlistName,
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
      playlistName: json['playlistName'] as String? ?? '',
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
