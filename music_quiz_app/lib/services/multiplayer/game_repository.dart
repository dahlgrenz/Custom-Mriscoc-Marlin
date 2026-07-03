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
    required String playlistId,
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
      targetCards: targetCards,
      playlistId: playlistId,
      players: {
        hostId: Player(id: hostId, name: hostName),
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
        .set(Player(id: playerId, name: playerName).toJson());
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
    await _room(code).update({
      'players/${updatedActivePlayer.id}/timeline': _timelineMap(updatedActivePlayer.timeline),
      'players/${updatedActivePlayer.id}/score': updatedActivePlayer.score,
      'turnIndex': nextTurnIndex,
      'currentRound': nextRound.toJson(),
    });
  }

  Future<void> finishGame(String code) =>
      _room(code).child('status').set(RoomStatus.finished.name);

  Future<void> leaveRoom({required String code, required String playerId}) =>
      _room(code).child('players/$playerId').remove();

  Map<String, dynamic> _timelineMap(List<Track> timeline) => {
        for (var i = 0; i < timeline.length; i++) '$i': timeline[i].toJson(),
      };
}
