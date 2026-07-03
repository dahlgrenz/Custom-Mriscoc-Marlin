import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/app_exception.dart';
import '../models/game_room.dart';
import '../models/player.dart';
import '../models/track.dart';
import '../services/multiplayer/game_repository.dart';
import '../services/music/music_source.dart';
import '../services/sound_service.dart';
import 'scoring.dart';

/// Utfallet av en placering, för återkoppling i UI:t.
enum PlacementResult { correct, wrong, stolen, missed }

/// Binder ihop musikkälla + multiplayer-repo + spellogik och exponerar ett
/// observerbart speltillstånd för UI:t.
class GameController extends ChangeNotifier {
  final GameRepository repo;
  final MusicSource music;
  final SoundService sound;
  final String myPlayerId;

  GameController({
    required this.repo,
    required this.music,
    required this.sound,
    required this.myPlayerId,
  });

  String? _code;
  String? get code => _code;

  GameRoom? _room;
  GameRoom? get room => _room;

  /// Senaste fel att visa i UI:t (null = inget fel).
  String? _lastError;
  String? get lastError => _lastError;

  /// Senaste placeringsutfall (för feedback + ljud). Rensas efter visning.
  PlacementResult? _lastResult;
  PlacementResult? get lastResult => _lastResult;

  bool _busy = false;
  bool get busy => _busy;

  bool _isPaused = true;
  bool get isPaused => _isPaused;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<GameRoom?>? _roomSub;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<bool>? _connectionSub;

  /// Leken (spellistan i slumpad ordning) — laddas från rummet vid spelstart.
  List<Track> _deck = [];

  bool get isHost => _room?.hostId == myPlayerId;
  Player? get me => _room?.players[myPlayerId];

  /// Vem som får agera just nu (gissaren eller utmanaren).
  bool get canAct => _room?.currentRound?.actorId == myPlayerId;
  bool get isStealPhase =>
      _room?.currentRound?.phase == RoundPhase.stealing;

  /// Namn på den som förväntas agera just nu.
  String get actorName {
    final round = _room?.currentRound;
    if (round == null) return '–';
    return _room?.players[round.actorId]?.name ?? '–';
  }

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  void clearResult() {
    if (_lastResult == null) return;
    _lastResult = null;
    notifyListeners();
  }

  void _setError(Object e) {
    _lastError = AppException.from(e).message;
    notifyListeners();
  }

  Future<void> _report(PlacementResult result) async {
    _lastResult = result;
    notifyListeners();
    switch (result) {
      case PlacementResult.correct:
        await sound.correct();
      case PlacementResult.stolen:
        await sound.steal();
      case PlacementResult.wrong:
      case PlacementResult.missed:
        await sound.wrong();
    }
  }

  /// Prenumerera på ett rum och håll [room] uppdaterat i realtid.
  void bindRoom(String code) {
    _code = code;
    _roomSub?.cancel();
    _roomSub = repo.watchRoom(code).listen(_onRoomUpdate, onError: _setError);

    _playbackSub?.cancel();
    _playbackSub = music.playbackStates().listen((s) {
      if (_isPaused != s.isPaused) {
        _isPaused = s.isPaused;
        notifyListeners();
      }
    }, onError: (_) {/* status-strömmen är best effort */});

    _connectionSub?.cancel();
    _connectionSub = repo.connectionState().listen((online) {
      if (_isOnline != online) {
        _isOnline = online;
        notifyListeners();
      }
    }, onError: (_) {});
  }

  // Nyckel för det tillstånd vi senast auto-spelade, så vi inte startar om
  // låten vid varje rum-uppdatering (t.ex. poängsynk).
  String? _lastActionKey;

  Future<void> _onRoomUpdate(GameRoom? room) async {
    _room = room;
    notifyListeners();
    if (room == null || room.status != RoomStatus.playing) return;

    if (_deck.isEmpty) {
      try {
        _deck = await repo.loadDeck(room.code);
      } catch (e) {
        _setError(e);
      }
    }

    // Spela låten automatiskt när det blir min tur att agera (gissa eller stjäla).
    final round = room.currentRound;
    if (canAct && round != null) {
      final key = '${round.track.id}|${round.phase.name}|${round.stealerId}';
      if (key != _lastActionKey) {
        _lastActionKey = key;
        try {
          await music.play(round.track);
        } catch (e) {
          _setError(e);
        }
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

  /// Värden justerar mål-antal kort i lobbyn.
  Future<void> setTargetCards(int target) async {
    final room = _room;
    if (room == null || !isHost) return;
    try {
      await repo.updateTargetCards(code: room.code, target: target);
    } catch (e) {
      _setError(e);
    }
  }

  /// Placerar den nu spelande låten på [position] i den agerande spelarens
  /// tidslinje. Hanterar både gissningsfasen och steal-fasen.
  Future<void> placeCurrentTrack(int position) async {
    final room = _room;
    final round = room?.currentRound;
    final player = me;
    if (room == null || round == null || player == null || !canAct) return;

    try {
      await music.pause();
      final correct =
          Scoring.isCorrectPlacement(player.timeline, round.track, position);

      if (round.phase == RoundPhase.guessing) {
        if (correct) {
          final updated = player.copyWith(
            timeline: Scoring.insertSorted(player.timeline, round.track),
            score: player.score + 1,
          );
          await _advanceTurn(room, round, updated);
          await _report(PlacementResult.correct);
        } else {
          // Fel gissning → nästa spelare får chansen att stjäla samma låt.
          final stealer =
              room.turnOrder[(room.turnIndex + 1) % room.turnOrder.length];
          await repo.updateRound(
            code: room.code,
            round: GameRound(
              track: round.track,
              activePlayerId: round.activePlayerId,
              phase: RoundPhase.stealing,
              stealerId: stealer,
            ),
          );
          await _report(PlacementResult.wrong);
        }
      } else {
        // Steal-fas: jag är utmanaren.
        final updated = correct
            ? player.copyWith(
                timeline: Scoring.insertSorted(player.timeline, round.track),
                score: player.score + 1,
              )
            : player;
        await _advanceTurn(room, round, updated);
        await _report(correct ? PlacementResult.stolen : PlacementResult.missed);
      }
    } catch (e) {
      _setError(e);
    }
  }

  /// Lämnar över turen och sätter nästa låt. Avslutar spelet vid vinst.
  Future<void> _advanceTurn(
      GameRoom room, GameRound round, Player updatedActor) async {
    final nextTurnIndex = room.turnIndex + 1;
    final nextActive = room.turnOrder[nextTurnIndex % room.turnOrder.length];
    final nextTrack =
        _deck.isEmpty ? round.track : _deck[nextTurnIndex % _deck.length];

    await repo.submitPlacement(
      code: room.code,
      updatedActivePlayer: updatedActor,
      nextTurnIndex: nextTurnIndex,
      nextRound: GameRound(track: nextTrack, activePlayerId: nextActive),
    );

    if (updatedActor.timeline.length >= room.targetCards) {
      await repo.finishGame(room.code);
    }
  }

  /// Play/paus-knapp för den som agerar.
  Future<void> togglePlayback() async {
    if (!canAct) return;
    try {
      if (_isPaused) {
        await music.resume();
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
    _connectionSub?.cancel();
    music.stop();
    super.dispose();
  }
}
