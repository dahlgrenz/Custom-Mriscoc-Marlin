import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/game_room.dart';
import '../models/player.dart';
import '../models/track.dart';
import '../services/multiplayer/game_repository.dart';
import '../services/music/music_source.dart';
import 'scoring.dart';

/// Binder ihop musikkälla + multiplayer-repo + spellogik och exponerar ett
/// observerbart speltillstånd för UI:t.
class GameController extends ChangeNotifier {
  final GameRepository repo;
  final MusicSource music;
  final String myPlayerId;

  GameController({
    required this.repo,
    required this.music,
    required this.myPlayerId,
  });

  String? _code;
  String? get code => _code;

  GameRoom? _room;
  GameRoom? get room => _room;

  StreamSubscription<GameRoom?>? _sub;

  /// Leken (spellistan i slumpad ordning) — laddas av värden vid start.
  List<Track> _deck = [];

  bool get isMyTurn => _room?.currentRound?.activePlayerId == myPlayerId;
  bool get isHost => _room?.hostId == myPlayerId;
  Player? get me => _room?.players[myPlayerId];

  /// Prenumerera på ett rum och håll [room] uppdaterat i realtid.
  void bindRoom(String code) {
    _code = code;
    _sub?.cancel();
    _sub = repo.watchRoom(code).listen((room) async {
      _room = room;
      if (room != null && room.status == RoomStatus.playing) {
        // Ladda leken en gång så även icke-värdar kan avancera på sin tur.
        if (_deck.isEmpty) {
          _deck = await repo.loadDeck(code);
        }
        // Spela låten automatiskt när det blir min tur.
        if (isMyTurn) {
          final track = room.currentRound?.track;
          if (track != null) music.play(track);
        }
      }
      notifyListeners();
    });
  }

  /// Värden laddar spellistan och startar spelet.
  Future<void> hostStartGame(String playlistId) async {
    final room = _room;
    if (room == null) return;
    final tracks = await music.fetchPlaylistTracks(playlistId);
    _deck = List<Track>.from(tracks)..shuffle(Random.secure());
    await repo.startGame(
      code: room.code,
      playerIds: room.players.keys.toList(),
      deck: _deck,
    );
  }

  /// Den aktiva spelaren placerar den nu spelande låten på [position] i sin
  /// tidslinje. Servern uppdateras med resultatet och turen lämnas över.
  Future<void> placeCurrentTrack(int position) async {
    final room = _room;
    final round = room?.currentRound;
    final player = me;
    if (room == null || round == null || player == null || !isMyTurn) return;

    await music.pause();

    final correct =
        Scoring.isCorrectPlacement(player.timeline, round.track, position);

    final updatedPlayer = correct
        ? player.copyWith(
            timeline: Scoring.insertSorted(player.timeline, round.track),
            score: player.score + 1,
          )
        : player; // fel placering: kortet slängs, tidslinjen oförändrad

    // Nästa spelare + nästa låt ur leken.
    final nextTurnIndex = room.turnIndex + 1;
    final nextActive =
        room.turnOrder[(nextTurnIndex) % room.turnOrder.length];
    final nextTrack = _deck.isEmpty
        ? round.track
        : _deck[nextTurnIndex % _deck.length];

    await repo.submitPlacement(
      code: room.code,
      updatedActivePlayer: updatedPlayer,
      nextTurnIndex: nextTurnIndex,
      nextRound: GameRound(track: nextTrack, activePlayerId: nextActive),
    );

    // Vinstvillkor.
    if (updatedPlayer.timeline.length >= room.targetCards) {
      await repo.finishGame(room.code);
    }
  }

  Future<void> replayCurrent() async {
    final track = _room?.currentRound?.track;
    if (track != null && isMyTurn) await music.play(track);
  }

  @override
  void dispose() {
    _sub?.cancel();
    music.stop();
    super.dispose();
  }
}
