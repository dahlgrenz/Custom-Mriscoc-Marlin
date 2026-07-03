import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';

import '../../models/track.dart';
import '../auth/spotify_auth_service.dart';
import 'music_source.dart';

/// Spotify-implementation av [MusicSource].
/// Metadata hämtas via Web API; uppspelning sker via Spotify SDK (kräver Premium).
class SpotifyMusicSource implements MusicSource {
  final SpotifyAuthService auth;
  SpotifyMusicSource(this.auth);

  static const _apiBase = 'https://api.spotify.com/v1';

  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) async {
    final token = auth.accessToken;
    if (token == null) {
      throw StateError('Inte inloggad på Spotify.');
    }

    final tracks = <Track>[];
    var url = Uri.parse(
      '$_apiBase/playlists/$playlistId/tracks'
      '?fields=next,items(track(id,uri,name,artists(name),album(release_date,images)))'
      '&limit=100',
    );

    // Spotify paginerar; följ "next" tills den är null.
    while (true) {
      final res = await http.get(url, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode != 200) {
        throw http.ClientException(
            'Spotify API ${res.statusCode}: ${res.body}', url);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final item in (body['items'] as List)) {
        final t = item['track'];
        if (t == null) continue;
        final track = _trackFromJson(Map<String, dynamic>.from(t as Map));
        if (track != null) tracks.add(track);
      }
      final next = body['next'];
      if (next == null) break;
      url = Uri.parse(next as String);
    }
    return tracks;
  }

  Track? _trackFromJson(Map<String, dynamic> t) {
    final album = t['album'] as Map?;
    final releaseDate = album?['release_date'] as String?; // "1975", "1975-11" el. "1975-11-21"
    if (releaseDate == null || releaseDate.isEmpty) return null;
    final year = int.tryParse(releaseDate.split('-').first);
    if (year == null) return null;

    final artists = (t['artists'] as List?) ?? [];
    final images = (album?['images'] as List?) ?? [];

    return Track(
      id: t['id'] as String,
      uri: t['uri'] as String,
      title: t['name'] as String,
      artist: artists.isEmpty ? 'Okänd' : (artists.first['name'] as String),
      year: year,
      albumArtUrl: images.isEmpty ? null : images.first['url'] as String?,
    );
  }

  @override
  Future<void> play(Track track) => SpotifySdk.play(spotifyUri: track.uri);

  @override
  Future<void> pause() => SpotifySdk.pause();

  @override
  Future<void> stop() => SpotifySdk.pause();
}
