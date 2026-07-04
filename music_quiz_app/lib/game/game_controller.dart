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
import 'question.dart';
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

  // --- Klassiskt läge ---
  static const int answerSeconds = 15;
  static const int _answerMs = answerSeconds * 1000;
  static const int revealSeconds = 4;
  static const int introSeconds = 5;

  bool _classicRunning = false;

  /// Mitt valda svarsalternativ i den aktuella rundan (null = ej svarat).
  int? _myAnswer;
  int? get myAnswer => _myAnswer;
  int _lastSeenRound = -1;

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

    final round = room.currentRound;

    // Klassiskt läge: nollställ mitt svar vid ny runda. Uppspelning + poäng
    // sköts av värdens loop (_runClassicLoop), inte här.
    if (room.mode == GameMode.classic) {
      if (round != null && round.roundNumber != _lastSeenRound) {
        _lastSeenRound = round.roundNumber;
        _myAnswer = null;
      }
      return;
    }

    if (round == null) return;

    // Värden hoppar över en spelare som lämnat mitt i sin tur (annars fastnar spelet).
    if (isHost && !room.players.containsKey(round.actorId)) {
      await _skipMissingActor(room, round);
      return;
    }

    // Värden är "jukebox": spelar rundans låt högt i rummet, oavsett vems tur
    // det är. Andra klienter (t.ex. webbanslutna) behöver då inget eget ljud.
    if (isHost && round.track.id != _lastPlayedTrackId) {
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
      if (room.mode == GameMode.classic) {
        await repo.startClassicGame(code: room.code, deck: _deck);
        _runClassicLoop(); // lång loop — inte await:ad
      } else {
        await repo.startGame(
          code: room.code,
          playerIds: room.players.keys.toList(),
          deck: _deck,
        );
      }
    } catch (e) {
      _setError(e);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// KLASSISKT LÄGE: värden driver rundorna — spelar låten, väntar ut svarstiden,
  /// poängsätter (rätt + snabbhetsbonus + streak) och visar facit.
  Future<void> _runClassicLoop() async {
    if (_classicRunning) return;
    _classicRunning = true;
    final rnd = Random.secure();
    try {
      final total = _room?.targetCards ?? 10;
      for (var roundNumber = 1; roundNumber <= total; roundNumber++) {
        final room = _room;
        if (room == null || room.status != RoomStatus.playing || _deck.isEmpty) {
          break;
        }
        final track = _deck[(roundNumber - 1) % _deck.length];
        final clue = room.clueStyle;
        // I omslagsläget frågar vi efter artisten (omslaget är ledtråden).
        final q = QuestionGenerator.generate(track, _deck, rnd,
            forceType: clue == 'cover' ? 'artist' : null);

        await repo.clearAnswers(room.code);
        final deadline = DateTime.now().millisecondsSinceEpoch + _answerMs;
        await repo.updateRound(
          code: room.code,
          round: GameRound(
            track: track,
            questionType: q.type,
            options: q.options,
            correctIndex: -1, // döljs tills facit
            deadlineMs: deadline,
            roundNumber: roundNumber,
          ),
        );

        // Ljud: omslagsläget är tyst; annars spelas låten (intro pausas efter 5 s).
        if (clue != 'cover') {
          try {
            await music.play(track);
          } catch (e) {
            _setError(e);
          }
        }
        if (clue == 'intro') {
          await Future.delayed(const Duration(seconds: introSeconds));
          try {
            await music.pause();
          } catch (_) {}
          await Future.delayed(
              const Duration(milliseconds: _answerMs - introSeconds * 1000 + 400));
        } else {
          await Future.delayed(const Duration(milliseconds: _answerMs + 400));
        }
        if (!_classicRunning) break;

        await _scoreClassicRound(room.code, q, roundNumber, deadline);
        await Future.delayed(const Duration(seconds: revealSeconds));
      }
      final code = _room?.code;
      if (code != null) await repo.finishGame(code);
    } catch (e) {
      _setError(e);
    } finally {
      _classicRunning = false;
    }
  }

  Future<void> _scoreClassicRound(
      String code, QuizQuestion q, int roundNumber, int deadline) async {
    final room = _room;
    if (room == null) return;
    final answers = await repo.readAnswers(code);
    final updated = <String, Player>{};

    for (final p in room.players.values) {
      final a = answers[p.id];
      final correct = a != null && a.choice == q.correctIndex;
      var points = 0;
      if (correct) {
        final remaining = (deadline - a.at).clamp(0, _answerMs);
        points = 100 + (100 * remaining / _answerMs).round(); // snabbhetsbonus
      }
      final newStreak = correct ? p.streak + 1 : 0;
      final st = p.stats;
      final newStats = correct
          ? st.copyWith(
              perfect: st.perfect + 1,
              bestStreak: max(st.bestStreak, newStreak))
          : st.copyWith(misses: st.misses + 1);
      updated[p.id] =
          p.copyWith(score: p.score + points, streak: newStreak, stats: newStats);
    }

    await repo.applyClassicScores(
      code: code,
      updated: updated,
      revealedRound: GameRound(
        track: room.currentRound?.track ?? _deck[(roundNumber - 1) % _deck.length],
        questionType: q.type,
        options: q.options,
        correctIndex: q.correctIndex,
        deadlineMs: deadline,
        revealed: true,
        roundNumber: roundNumber,
      ),
    );
  }

  /// En spelare skickar sitt svar i klassiskt läge.
  Future<void> submitAnswer(int choice) async {
    final room = _room;
    final round = room?.currentRound;
    if (room == null || round == null || mode != GameMode.classic) return;
    if (round.revealed || _myAnswer != null) return;
    if (round.deadlineMs > 0 &&
        DateTime.now().millisecondsSinceEpoch > round.deadlineMs) {
      return;
    }
    _myAnswer = choice;
    notifyListeners();
    try {
      await repo.submitAnswer(
        code: room.code,
        playerId: myPlayerId,
        choice: choice,
        atMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      _setError(e);
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

  /// Värden byter ledtrådsstil i klassiskt läge (audio/intro/cover).
  Future<void> setClueStyle(String style) async {
    final room = _room;
    if (room == null || !isHost) return;
    try {
      await repo.updateClueStyle(code: room.code, style: style);
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
            stats: player.stats.copyWith(perfect: player.stats.perfect + 1),
          );
          await _advanceTurn(room, round, updated);
          await _reportFeedback('Rätt! Kortet är ditt 🎉', good: true);
        } else {
          // Fel gissning → nästa spelare får chansen att stjäla samma låt.
          final next = _nextPresentTurn(room);
          final stealer = next?.$2 ?? round.activePlayerId;
          await repo.updateRound(
            code: room.code,
            round: GameRound(
              track: round.track,
              activePlayerId: round.activePlayerId,
              phase: RoundPhase.stealing,
              stealerId: stealer,
            ),
          );
          await repo.updatePlayerStats(
            code: room.code,
            playerId: player.id,
            stats: player.stats.copyWith(misses: player.stats.misses + 1),
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
                stats: player.stats.copyWith(
                  perfect: player.stats.perfect + 1,
                  steals: player.stats.steals + 1,
                ),
              )
            : player.copyWith(
                stats: player.stats.copyWith(misses: player.stats.misses + 1),
              );
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
      final s = player.stats;
      final newStats = switch (points) {
        5 => s.copyWith(perfect: s.perfect + 1),
        3 => s.copyWith(threes: s.threes + 1),
        1 => s.copyWith(ones: s.ones + 1),
        _ => s.copyWith(misses: s.misses + 1),
      };
      final updated = player.copyWith(
        timeline: Scoring.insertSorted(player.timeline, round.track),
        score: player.score + points,
        stats: newStats,
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

  /// Nästa tur (index, spelar-id) där spelaren fortfarande är kvar i rummet,
  /// eller null om ingen är kvar. Hoppar alltså över spelare som lämnat.
  (int, String)? _nextPresentTurn(GameRoom room) {
    final order = room.turnOrder;
    if (order.isEmpty) return null;
    for (var step = 1; step <= order.length; step++) {
      final idx = room.turnIndex + step;
      final id = order[idx % order.length];
      if (room.players.containsKey(id)) return (idx, id);
    }
    return null;
  }

  /// Lämnar över turen och sätter nästa låt. Avslutar spelet vid vinst.
  Future<void> _advanceTurn(
      GameRoom room, GameRound round, Player updatedActor) async {
    final next = _nextPresentTurn(room);
    if (next == null) {
      await repo.finishGame(room.code);
      return;
    }
    final (nextTurnIndex, nextActive) = next;
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

  /// Värden hoppar över en spelare som lämnat mitt i sin tur.
  bool _skipping = false;
  Future<void> _skipMissingActor(GameRoom room, GameRound round) async {
    if (_skipping) return;
    _skipping = true;
    try {
      final next = _nextPresentTurn(room);
      if (next == null) {
        await repo.finishGame(room.code);
        return;
      }
      final (idx, active) = next;
      final track = _deck.isEmpty ? round.track : _deck[idx % _deck.length];
      await repo.advanceOnly(
        code: room.code,
        nextTurnIndex: idx,
        nextRound: GameRound(track: track, activePlayerId: active),
      );
    } finally {
      _skipping = false;
    }
  }

  /// Värden sätter en spelares handikapp (minuspoäng).
  Future<void> setHandicap(String playerId, int handicap) async {
    final room = _room;
    if (room == null || !isHost) return;
    try {
      await repo.setHandicap(
          code: room.code, playerId: playerId, handicap: handicap);
    } catch (e) {
      _setError(e);
    }
  }

  /// Lämnar spelet. Om värden lämnar under pågående spel avslutas matchen.
  Future<void> leaveGame() async {
    final room = _room;
    if (room == null) return;
    try {
      _classicRunning = false; // stoppa ev. värd-loop
      if (isHost && room.status == RoomStatus.playing) {
        await repo.finishGame(room.code);
      }
      await repo.leaveRoom(code: room.code, playerId: myPlayerId);
    } catch (e) {
      _setError(e);
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
    _classicRunning = false;
    _roomSub?.cancel();
    _playbackSub?.cancel();
    _connectionSub?.cancel();
    music.stop();
    super.dispose();
  }
}
