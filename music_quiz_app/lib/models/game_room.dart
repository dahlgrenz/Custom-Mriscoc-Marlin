import 'player.dart';
import 'track.dart';

enum RoomStatus { lobby, playing, finished }

/// Spelläge.
/// - [timeline]: placera låten rätt i tiden (Hitster).
/// - [year]: gissa utgivningsåret; poäng efter hur nära (5/3/1).
/// - [classic]: samtidig flervalsfråga med timer och snabbast-svar-poäng.
enum GameMode { timeline, year, classic }

/// Rundans fas: den aktiva spelaren gissar först; om hen har fel får en
/// utmanare (nästa spelare) chansen att stjäla kortet.
enum RoundPhase { guessing, stealing }

/// Den nuvarande rundan. I tidslinje-/årtalsläget beskriver den vems tur det är;
/// i klassiskt läge bär den även frågan (typ, alternativ, deadline).
class GameRound {
  final Track track;
  final String activePlayerId;
  final RoundPhase phase;

  /// Vem som får stjäla när [phase] är [RoundPhase.stealing] (annars null).
  final String? stealerId;

  // --- Klassiskt läge ---
  /// Frågetyp: "song" | "artist" | "year" (tomt i övriga lägen).
  final String questionType;
  final List<String> options;

  /// Rätt alternativ. Döljs (−1) tills [revealed] är true, för att minska fusk.
  final int correctIndex;

  /// Svarsdeadline i epok-millisekunder (0 = ej satt).
  final int deadlineMs;
  final bool revealed;
  final int roundNumber;

  const GameRound({
    required this.track,
    this.activePlayerId = '',
    this.phase = RoundPhase.guessing,
    this.stealerId,
    this.questionType = '',
    this.options = const [],
    this.correctIndex = -1,
    this.deadlineMs = 0,
    this.revealed = false,
    this.roundNumber = 0,
  });

  /// Vem som får agera just nu (gissaren eller utmanaren).
  String get actorId =>
      phase == RoundPhase.stealing ? (stealerId ?? activePlayerId) : activePlayerId;

  /// Frågetext för klassiskt läge.
  String get promptText => switch (questionType) {
        'artist' => 'Vilken artist?',
        'year' => 'Vilket år?',
        'song' => 'Vilken låt?',
        _ => '',
      };

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'activePlayerId': activePlayerId,
        'phase': phase.name,
        'stealerId': stealerId,
        if (questionType.isNotEmpty) 'questionType': questionType,
        if (options.isNotEmpty) 'options': options,
        'correctIndex': correctIndex,
        if (deadlineMs > 0) 'deadlineMs': deadlineMs,
        'revealed': revealed,
        'roundNumber': roundNumber,
      };

  factory GameRound.fromJson(Map<String, dynamic> json) => GameRound(
        track: Track.fromJson(Map<String, dynamic>.from(json['track'] as Map)),
        activePlayerId: json['activePlayerId'] as String? ?? '',
        phase: RoundPhase.values.firstWhere(
          (p) => p.name == json['phase'],
          orElse: () => RoundPhase.guessing,
        ),
        stealerId: json['stealerId'] as String?,
        questionType: json['questionType'] as String? ?? '',
        options: [for (final o in (json['options'] as List? ?? [])) '$o'],
        correctIndex: (json['correctIndex'] as num?)?.toInt() ?? -1,
        deadlineMs: (json['deadlineMs'] as num?)?.toInt() ?? 0,
        revealed: json['revealed'] as bool? ?? false,
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 0,
      );
}

/// Hela speltillståndet för ett rum — serverns sanningskälla.
class GameRoom {
  final String code;
  final String hostId;
  final RoomStatus status;
  final GameMode mode;

  /// Vinstmål. I [GameMode.timeline] = antal kort; i [GameMode.year] = poäng;
  /// i [GameMode.classic] = antal frågor.
  final int targetCards;

  /// Ledtrådsstil i klassiskt läge: "audio" (hela låten), "intro" (bara 5 s),
  /// eller "cover" (suddigt albumomslag som skärps).
  final String clueStyle;

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
    this.mode = GameMode.timeline,
    required this.targetCards,
    this.clueStyle = 'audio',
    required this.playlistId,
    this.playlistName = '',
    required this.players,
    this.turnOrder = const [],
    this.turnIndex = 0,
    this.currentRound,
  });

  String? get activePlayerId =>
      turnOrder.isEmpty ? null : turnOrder[turnIndex % turnOrder.length];

  /// Grundvärde utan handikapp: antal kort i tidslinjeläge, annars poäng.
  int baseValue(Player p) =>
      mode == GameMode.timeline ? p.timeline.length : p.score;

  /// Rankvärde med handikapp (minuspoäng) inräknat — det som avgör placeringen.
  int rankValue(Player p) => baseValue(p) - p.handicap;

  bool get anyHandicap => players.values.any((p) => p.handicap != 0);

  /// Slutställning (med handikapp) — ledare först.
  List<Player> get ranking {
    final list = players.values.toList()
      ..sort((a, b) => rankValue(b).compareTo(rankValue(a)));
    return list;
  }

  /// Ställning utan handikapp (rå prestation) — ledare först.
  List<Player> get rankingRaw {
    final list = players.values.toList()
      ..sort((a, b) => baseValue(b).compareTo(baseValue(a)));
    return list;
  }

  Player? get winner => players.isEmpty ? null : ranking.first;

  Map<String, dynamic> toJson() => {
        'code': code,
        'hostId': hostId,
        'status': status.name,
        'mode': mode.name,
        'targetCards': targetCards,
        'clueStyle': clueStyle,
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
      mode: GameMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => GameMode.timeline,
      ),
      targetCards: (json['targetCards'] as num?)?.toInt() ?? 10,
      clueStyle: json['clueStyle'] as String? ?? 'audio',
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
