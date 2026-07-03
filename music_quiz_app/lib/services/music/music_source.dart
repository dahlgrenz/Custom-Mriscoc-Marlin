import '../../models/track.dart';

/// Abstraktion över musikkällan. Spellogiken beror bara på detta gränssnitt —
/// aldrig på Spotify direkt — så att källan kan bytas (Deezer, iTunes-previews,
/// egna licensierade klipp) utan att röra spelet.
abstract class MusicSource {
  /// Hämtar låtarna i en spellista, med metadata (inkl. utgivningsår) ifyllt.
  Future<List<Track>> fetchPlaylistTracks(String playlistId);

  /// Startar uppspelning av [track] på enheten.
  Future<void> play(Track track);

  /// Pausar pågående uppspelning.
  Future<void> pause();

  /// Stoppar och släpper eventuella resurser.
  Future<void> stop();
}
