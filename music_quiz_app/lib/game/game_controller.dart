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
import '../services/tag_repository.dart';
import 'scoring.dart';
import 'track_filter.dart';

/// Binder ihop musikkälla + multiplayer-repo + spellogik och exponerar ett
/// observerbart speltillstånd för UI:t.
class GameController extends ChangeNotifier {
  final GameRepository repo;
  final MusicSource music;
  final SoundService sound;
  final TagRepository tags;
  final String myPlayerId;

  GameController({
    required this.repo,
    required this.music,
    required this.sound,
    required this.tags,
    required this.myPlayerId,
  });

  String? _code;
  String? get code => _code;

  GameRoom? _room;
  GameRoom? get room => _room;

  /// Senaste fel att visa i UI:t (null = inget fel).
  String? _lastError;
  String? get lastError => _lastError;

  /// Återkoppling att visa (t.ex. "Rätt!" / "+3 poäng"). Rensas efter visning.
  String? _feedback;
  bool _feedbackGood = true;
  String? get feedback => _feedback;
  bool get feedbackGood => _feedbackGood;

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

  /// Alla låtar från spellistan (för filtret), och det valda filtret.
  List<Track> _allTracks = [];
  List<Track> get allTracks => _allTracks;
  TrackFilter _filter = const TrackFilter();
  TrackFilter get filter => _filter;
  List<Track> get filteredTracks => _filter.apply(_allTracks);

  bool _loadingTracks = false;
  bool get loadingTracks => _loadingTracks;

  bool get isHost => _room?.hostId == myPlayerId;
  Player? get me => _room?.players[myPlayerId];

  GameMode get mode => _room?.mode ?? GameMode.timeline;

  /// Vem som får agera just nu (gissaren eller utmanaren).
  bool get canAct => _room?.currentRound?.actorId == myPlayerId;
  bool get isStealPhase => _room?.currentRound?.phase == RoundPhase.stealing;

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

  void clearFeedback() {
    if (_feedback == null) return;
    _feedback = null;
    notifyListeners();
  }

  void _setError(Object e) {
    _lastError = AppException.from(e).message;
    notifyListeners();
  }

  Future<void> _reportFeedback(String text,
      {required bool good, bool steal = false}) async {
    _feedback = text;
    _feedbackGood = good;
    notifyListeners();
    if (steal) {
      await sound.steal();
    } else if (good) {
      await sound.correct();
    } else {
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

  // Id på låten vi senast spelade, så vi inte startar om den vid varje
  // rum-uppdatering (t.ex. poängsynk eller övergång till steal-fas).
  String? _lastPlayedTrackId;

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

    // Värden är "jukebox": spelar rundans låt högt i rummet, oavsett vems tur
    // det är. Andra klienter (t.ex. webbanslutna) behöver då inget eget ljud.
    final round = room.currentRound;
    if (isHost && round != null && round.track.id != _lastPlayedTrackId) {
      _lastPlayedTrackId = round.track.id;
      try {
        await music.play(round.track);
      } catch (e) {
        _setError(e);
      }
    }
  }

  /// Laddar spellistans låtar (med kuraterade taggar) för filtervyn. Idempotent.
  Future<void> loadTracksForFilter(String playlistId) async {
    if (_allTracks.isNotEmpty || _loadingTracks) return;
    _loadingTracks = true;
    notifyListeners();
    try {
      await tags.load();
      final fetched = await music.fetchPlaylistTracks(playlistId);
      _allTracks = tags.applyTo(fetched);
    } catch (e) {
      _setError(e);
    } finally {
      _loadingTracks = false;
      notifyListeners();
    }
  }

  void setFilter(TrackFilter f) {
    _filter = f;
    notifyListeners();
  }

  /// Värden startar spelet med det filtrerade urvalet.
  Future<void> hostStartGame(String playlistId) async {
    final room = _room;
    if (room == null) return;
    _busy = true;
    notifyListeners();
    try {
      if (_allTracks.isEmpty) {
        await tags.load();
        _allTracks = tags.applyTo(await music.fetchPlaylistTracks(playlistId));
      }
      final filtered = _filter.apply(_allTracks);
      final minNeeded = room.players.length + 1;
      if (filtered.length < minNeeded || filtered.length < 4) {
        throw AppException(
            'För få låtar matchar filtret (${filtered.length}). Lätta på filtret.');
      }
      _deck = List<Track>.from(filtered)..shuffle(Random.secure());
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

  /// Värden justerar vinstmål (kort eller poäng) i lobbyn.
  Future<void> setTargetCards(int target) async {
    final room = _room;
    if (room == null || !isHost) return;
    try {
      await repo.updateTargetCards(code: room.code, target: target);
    } catch (e) {
      _setError(e);
    }
  }

  /// Värden byter spelläge i lobbyn. Sätter samtidigt ett rimligt standardmål
  /// för läget (kort i tidslinje, poäng i årtal).
  Future<void> setMode(GameMode m) async {
    final room = _room;
    if (room == null || !isHost) return;
    try {
      await repo.updateMode(code: room.code, mode: m);
      await repo.updateTargetCards(
          code: room.code, target: m == GameMode.year ? 25 : 10);
    } catch (e) {
      _setError(e);
    }
  }

  /// TIDSLINJELÄGE: placerar den nu spelande låten på [position] i den
  /// agerande spelarens tidslinje. Hanterar gissningsfas och steal-fas.
  Future<void> placeCurrentTrack(int position) async {
    final room = _room;
    final round = room?.currentRound;
    final player = me;
    if (room == null || round == null || player == null || !canAct) return;
    if (mode != GameMode.timeline) return;

    try {
      final correct =
          Scoring.isCorrectPlacement(player.timeline, round.track, position);

      if (round.phase == RoundPhase.guessing) {
        if (correct) {
          final updated = player.copyWith(
            timeline: Scoring.insertSorted(player.timeline, round.track),
            score: player.score + 1,
          );
          await _advanceTurn(room, round, updated);
          await _reportFeedback('Rätt! Kortet är ditt 🎉', good: true);
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
          await _reportFeedback(
              'Fel plats! Nästa spelare får chansen att stjäla.',
              good: false);
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
        await _reportFeedback(
            correct ? 'Stöld! Du snodde kortet 😎' : 'Missade stölden — kortet försvinner.',
            good: correct,
            steal: correct);
      }
    } catch (e) {
      _setError(e);
    }
  }

  /// ÅRTALSLÄGE: den aktiva spelaren gissar utgivningsåret (poäng 5/3/1).
  Future<void> submitYearGuess(int year) async {
    final room = _room;
    final round = room?.currentRound;
    final player = me;
    if (room == null || round == null || player == null || !canAct) return;
    if (mode != GameMode.year) return;

    try {
      final points = Scoring.yearGuessPoints(round.track.year, year);
      final updated = player.copyWith(
        timeline: Scoring.insertSorted(player.timeline, round.track),
        score: player.score + points,
      );
      await _advanceTurn(room, round, updated);
      final actual = round.track.year;
      final msg = switch (points) {
        5 => '🎯 Full träff! Rätt år var $actual. +5 poäng',
        3 => 'Nära! Rätt år var $actual. +3 poäng',
        1 => 'Rätt år var $actual. +1 poäng',
        _ => 'Fel — rätt år var $actual. 0 poäng',
      };
      await _reportFeedback(msg, good: points > 0);
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

    final reached = room.mode == GameMode.year
        ? updatedActor.score >= room.targetCards
        : updatedActor.timeline.length >= room.targetCards;
    if (reached) {
      await repo.finishGame(room.code);
    }
  }

  /// Play/paus-knapp för jukeboxen (värden styr rummets ljud).
  Future<void> togglePlayback() async {
    if (!isHost) return;
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
