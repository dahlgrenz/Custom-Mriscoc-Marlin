import '../../models/track.dart';

/// Källoberoende uppspelningsstatus.
class PlaybackState {
  final bool isPaused;
  final String? trackUri;
  const PlaybackState({required this.isPaused, this.trackUri});
}

/// Abstraktion över musikkällan. Spellogiken beror bara på detta gränssnitt —
/// aldrig på Spotify direkt — så att källan kan bytas (Deezer, iTunes-previews,
/// egna licensierade klipp) utan att röra spelet.
abstract class MusicSource {
  /// Hämtar låtarna i en spellista, med metadata (inkl. utgivningsår) ifyllt.
  /// Kastar [AppException] vid fel.
  Future<List<Track>> fetchPlaylistTracks(String playlistId);

  /// Startar uppspelning av [track] på enheten. Kastar [AppException] vid fel.
  Future<void> play(Track track);

  /// Återupptar pausad uppspelning.
  Future<void> resume();

  /// Pausar pågående uppspelning.
  Future<void> pause();

  /// Stoppar och släpper eventuella resurser.
  Future<void> stop();

  /// Ström av uppspelningsstatus (spelar/pausad) för UI:t.
  Stream<PlaybackState> playbackStates();
}
