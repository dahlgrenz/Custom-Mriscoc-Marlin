import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
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

  /// Senaste fel att visa i UI:t (null = inget fel). UI:t kan rensa via [clearError].
  String? _lastError;
  String? get lastError => _lastError;

  /// True medan en åtgärd (t.ex. spelstart) pågår.
  bool _busy = false;
  bool get busy => _busy;

  /// Uppspelningsstatus från musikkällan.
  bool _isPaused = true;
  bool get isPaused => _isPaused;

  StreamSubscription<GameRoom?>? _roomSub;
  StreamSubscription<PlaybackState>? _playbackSub;

  /// Leken (spellistan i slumpad ordning) — laddas från rummet vid spelstart.
  List<Track> _deck = [];

  bool get isMyTurn => _room?.currentRound?.activePlayerId == myPlayerId;
  bool get isHost => _room?.hostId == myPlayerId;
  Player? get me => _room?.players[myPlayerId];

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  void _setError(Object e) {
    _lastError = AppException.from(e).message;
    notifyListeners();
  }

  /// Prenumerera på ett rum och håll [room] uppdaterat i realtid.
  void bindRoom(String code) {
    _code = code;
    _roomSub?.cancel();
    _roomSub = repo.watchRoom(code).listen(_onRoomUpdate, onError: _setError);

    // Följ uppspelningsstatus för play/paus-knappen.
    _playbackSub?.cancel();
    _playbackSub = music.playbackStates().listen((s) {
      if (_isPaused != s.isPaused) {
        _isPaused = s.isPaused;
        notifyListeners();
      }
    }, onError: (_) {/* status-strömmen är best effort */});
  }

  // Spelar bara automatiskt vid övergången till en ny låt, inte vid varje
  // rum-uppdatering (annars skulle poänguppdateringar starta om låten).
  String? _lastAutoPlayedTrackId;

  Future<void> _onRoomUpdate(GameRoom? room) async {
    _room = room;
    notifyListeners();
    if (room == null || room.status != RoomStatus.playing) return;

    // Ladda leken en gång så även icke-värdar kan avancera på sin tur.
    if (_deck.isEmpty) {
      try {
        _deck = await repo.loadDeck(room.code);
      } catch (e) {
        _setError(e);
      }
    }

    // Spela låten automatiskt när det blir min tur och rundan är ny.
    final track = room.currentRound?.track;
    if (isMyTurn && track != null && track.id != _lastAutoPlayedTrackId) {
      _lastAutoPlayedTrackId = track.id;
      try {
        await music.play(track);
      } catch (e) {
        _setError(e);
      }
    }
  }

  /// Värden laddar spellistan och startar spelet.
  Future<void> hostStartGame(String playlistId) async {
    final room = _room;
    if (room == null) return;
    _busy = true;
    notifyListeners();
    try {
      final tracks = await music.fetchPlaylistTracks(playlistId);
      _deck = List<Track>.from(tracks)..shuffle(Random.secure());
      await repo.startGame(
        code: room.code,
        playerIds: room.players.keys.toList(),
        deck: _deck,
      );
    } catch (e) {
      _setError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Den aktiva spelaren placerar den nu spelande låten på [position] i sin
  /// tidslinje. Servern uppdateras med resultatet och turen lämnas över.
  Future<void> placeCurrentTrack(int position) async {
    final room = _room;
    final round = room?.currentRound;
    final player = me;
    if (room == null || round == null || player == null || !isMyTurn) return;

    try {
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
      final nextActive = room.turnOrder[nextTurnIndex % room.turnOrder.length];
      final nextTrack =
          _deck.isEmpty ? round.track : _deck[nextTurnIndex % _deck.length];

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
    } catch (e) {
      _setError(e);
    }
  }

  /// Play/paus-knapp för den aktiva spelaren.
  Future<void> togglePlayback() async {
    if (!isMyTurn) return;
    try {
      if (_isPaused) {
        final track = _room?.currentRound?.track;
        // resume() återupptar; om inget spelas alls, starta låten på nytt.
        if (track != null && track.id != _lastAutoPlayedTrackId) {
          await music.play(track);
        } else {
          await music.resume();
        }
      } else {
        await music.pause();
      }
    } catch (e) {
      _setError(e);
    }
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _playbackSub?.cancel();
    music.stop();
    super.dispose();
  }
}
