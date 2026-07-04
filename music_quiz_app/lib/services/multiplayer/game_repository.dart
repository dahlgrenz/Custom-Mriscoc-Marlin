import 'dart:math';

import 'package:firebase_database/firebase_database.dart';

import '../../models/game_room.dart';
import '../../models/player.dart';
import '../../models/track.dart';

/// All realtidskommunikation med Firebase Realtime Database.
/// Rummet är serverns sanningskälla; klienterna prenumererar på ändringar.
class GameRepository {
  final FirebaseDatabase _db;
  GameRepository({FirebaseDatabase? db})
      : _db = db ?? FirebaseDatabase.instance;

  DatabaseReference _room(String code) => _db.ref('rooms/$code');

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // utan lättförväxlade
  String _generateCode([int length = 4]) {
    final rnd = Random.secure();
    return List.generate(length, (_) => _codeChars[rnd.nextInt(_codeChars.length)])
        .join();
  }

  /// Skapar ett rum och lägger till värden som första spelare.
  Future<String> createRoom({
    required String hostId,
    required String hostName,
    String hostAvatar = '🎧',
    required String playlistId,
    String playlistName = '',
    int targetCards = 10,
  }) async {
    // Försök tills vi hittar en oanvänd kod.
    String code;
    do {
      code = _generateCode();
    } while ((await _room(code).get()).exists);

    final room = GameRoom(
      code: code,
      hostId: hostId,
      status: RoomStatus.lobby,
      mode: GameMode.timeline,
      targetCards: targetCards,
      playlistId: playlistId,
      playlistName: playlistName,
      players: {
        hostId: Player(id: hostId, name: hostName, avatar: hostAvatar),
      },
    );
    await _room(code).set(room.toJson());
    return code;
  }

  /// Går med i ett befintligt rum. Kastar om rummet saknas eller redan spelar.
  Future<void> joinRoom({
    required String code,
    required String playerId,
    required String playerName,
    String playerAvatar = '🎧',
  }) async {
    final snapshot = await _room(code).get();
    if (!snapshot.exists) {
      throw StateError('Rummet $code finns inte.');
    }
    final room = GameRoom.fromJson(
        Map<String, dynamic>.from(snapshot.value as Map));
    if (room.status != RoomStatus.lobby) {
      throw StateError('Spelet i rum $code har redan startat.');
    }
    await _room(code)
        .child('players/$playerId')
        .set(Player(id: playerId, name: playerName, avatar: playerAvatar)
            .toJson());
  }

  /// Värden justerar mål-antal kort/poäng i lobbyn (synkas till alla).
  Future<void> updateTargetCards({
    required String code,
    required int target,
  }) =>
      _room(code).child('targetCards').set(target);

  /// Värden byter spelläge i lobbyn.
  Future<void> updateMode({required String code, required GameMode mode}) =>
      _room(code).child('mode').set(mode.name);

  /// Skriver om enbart den nuvarande rundan (används vid steal-övergången).
  Future<void> updateRound({
    required String code,
    required GameRound round,
  }) =>
      _room(code).child('currentRound').set(round.toJson());

  /// True/false-ström för om klienten är ansluten till Firebase (för
  /// offline-banner och återanslutning). Firebase återansluter automatiskt.
  Stream<bool> connectionState() {
    return _db.ref('.info/connected').onValue.map(
          (event) => event.snapshot.value == true,
        );
  }

  /// Ström av rummets tillstånd i realtid.
  Stream<GameRoom?> watchRoom(String code) {
    return _room(code).onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return null;
      return GameRoom.fromJson(Map<String, dynamic>.from(value as Map));
    });
  }

  /// Startar spelet: slumpar turordning, ger varje spelare ett startkort och
  /// sätter första rundan. [deck] är spellistan i slumpad ordning.
  Future<void> startGame({
    required String code,
    required List<String> playerIds,
    required List<Track> deck,
  }) async {
    final shuffledPlayers = List<String>.from(playerIds)..shuffle(Random.secure());
    var deckIndex = 0;

    final updates = <String, dynamic>{
      'status': RoomStatus.playing.name,
      'turnOrder': shuffledPlayers,
      'turnIndex': 0,
    };

    // Startkort per spelare (avslöjat direkt så tidslinjen inte är tom).
    for (final id in shuffledPlayers) {
      final startCard = deck[deckIndex++ % deck.length];
      updates['players/$id/timeline'] = {'0': startCard.toJson()};
    }

    // Första rundans låt: nästa kort i leken.
    final firstTrack = deck[deckIndex % deck.length];
    updates['currentRound'] = GameRound(
      track: firstTrack,
      activePlayerId: shuffledPlayers.first,
    ).toJson();

    // Spara hela (slumpade) leken i rummet så att alla klienter — inte bara
    // värden — kan avancera till nästa låt när det blir deras tur.
    updates['deck'] = {
      for (var i = 0; i < deck.length; i++) '$i': deck[i].toJson(),
    };

    await _room(code).update(updates);
  }

  /// Startar en klassisk match: status playing + sparad lek. Rundorna drivs
  /// sedan av värden (se GameController). Ingen turordning/startkort behövs.
  Future<void> startClassicGame({
    required String code,
    required List<Track> deck,
  }) async {
    await _room(code).update({
      'status': RoomStatus.playing.name,
      'deck': {for (var i = 0; i < deck.length; i++) '$i': deck[i].toJson()},
      'answers': null, // rensa ev. gamla svar
    });
  }

  /// En spelare skickar sitt svar (klassiskt läge).
  Future<void> submitAnswer({
    required String code,
    required String playerId,
    required int choice,
    required int atMs,
  }) =>
      _room(code).child('answers/$playerId').set({'choice': choice, 'at': atMs});

  Future<void> clearAnswers(String code) =>
      _room(code).child('answers').remove();

  /// Värden läser in alla svar för rundan: {playerId: {choice, at}}.
  Future<Map<String, ({int choice, int at})>> readAnswers(String code) async {
    final snap = await _room(code).child('answers').get();
    if (!snap.exists || snap.value == null) return {};
    final raw = Map<String, dynamic>.from(snap.value as Map);
    return {
      for (final e in raw.entries)
        '${e.key}': (
          choice: ((e.value as Map)['choice'] as num?)?.toInt() ?? -1,
          at: ((e.value as Map)['at'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// Värden skriver rundans facit + uppdaterade poäng/sviter/statistik.
  Future<void> applyClassicScores({
    required String code,
    required Map<String, Player> updated,
    required GameRound revealedRound,
  }) async {
    final updates = <String, dynamic>{'currentRound': revealedRound.toJson()};
    for (final p in updated.values) {
      updates['players/${p.id}/score'] = p.score;
      updates['players/${p.id}/streak'] = p.streak;
      updates['players/${p.id}/stats'] = p.stats.toJson();
    }
    await _room(code).update(updates);
  }

  /// Läser den sparade leken för ett rum (tom lista om den inte finns än).
  Future<List<Track>> loadDeck(String code) async {
    final snap = await _room(code).child('deck').get();
    if (!snap.exists || snap.value == null) return [];
    final raw = Map<String, dynamic>.from(snap.value as Map);
    final entries = raw.entries.toList()
      ..sort((a, b) => int.parse('${a.key}').compareTo(int.parse('${b.key}')));
    return [
      for (final e in entries)
        Track.fromJson(Map<String, dynamic>.from(e.value as Map)),
    ];
  }

  /// Skriver resultatet av en placering och lämnar över turen.
  /// Servern håller poäng och tidslinje; nästa låt sätts av [nextTrack].
  Future<void> submitPlacement({
    required String code,
    required Player updatedActivePlayer,
    required int nextTurnIndex,
    required GameRound nextRound,
  }) async {
    final id = updatedActivePlayer.id;
    await _room(code).update({
      'players/$id/timeline': _timelineMap(updatedActivePlayer.timeline),
      'players/$id/score': updatedActivePlayer.score,
      'players/$id/stats': updatedActivePlayer.stats.toJson(),
      'turnIndex': nextTurnIndex,
      'currentRound': nextRound.toJson(),
    });
  }

  /// Bara turövergång (ingen spelaruppdatering) — t.ex. när en frånvarande
  /// spelares tur hoppas över.
  Future<void> advanceOnly({
    required String code,
    required int nextTurnIndex,
    required GameRound nextRound,
  }) =>
      _room(code).update({
        'turnIndex': nextTurnIndex,
        'currentRound': nextRound.toJson(),
      });

  /// Värden sätter en spelares handikapp (minuspoäng).
  Future<void> setHandicap({
    required String code,
    required String playerId,
    required int handicap,
  }) =>
      _room(code).child('players/$playerId/handicap').set(handicap);

  /// Skriver bara en spelares statistik (t.ex. en miss utan turövergång).
  Future<void> updatePlayerStats({
    required String code,
    required String playerId,
    required PlayerStats stats,
  }) =>
      _room(code).child('players/$playerId/stats').set(stats.toJson());

  Future<void> finishGame(String code) =>
      _room(code).child('status').set(RoomStatus.finished.name);

  Future<void> leaveRoom({required String code, required String playerId}) =>
      _room(code).child('players/$playerId').remove();

  Map<String, dynamic> _timelineMap(List<Track> timeline) => {
        for (var i = 0; i < timeline.length; i++) '$i': timeline[i].toJson(),
      };
}
