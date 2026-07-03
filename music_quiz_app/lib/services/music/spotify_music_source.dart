import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:spotify_sdk/spotify_sdk.dart';
// Visa bara PlayerState så Spotifys egen Track-modell inte krockar med vår.
import 'package:spotify_sdk/models/player_state.dart' show PlayerState;

import '../../core/app_exception.dart';
import '../../models/playlist_info.dart';
import '../../models/track.dart';
import '../auth/spotify_auth_service.dart';
import 'music_source.dart';

/// Spotify-implementation av [MusicSource].
/// Metadata hämtas via Web API; uppspelning sker via Spotify SDK (kräver Premium).
///
/// Alla operationer säkerställer först en giltig anslutning via
/// [SpotifyAuthService.ensureConnected] och översätter fel till [AppException].
class SpotifyMusicSource implements MusicSource {
  final SpotifyAuthService auth;
  SpotifyMusicSource(this.auth);

  static const _apiBase = 'https://api.spotify.com/v1';

  @override
  Future<List<PlaylistInfo>> fetchPlaylists() async {
    final token = await auth.ensureConnected();
    final playlists = <PlaylistInfo>[];
    var url = Uri.parse('$_apiBase/me/playlists?limit=50');

    try {
      while (true) {
        final res =
            await http.get(url, headers: {'Authorization': 'Bearer $token'});
        if (res.statusCode == 401) {
          throw const AppException(
              'Spotify-sessionen gick ut. Anslut igen och försök på nytt.');
        }
        if (res.statusCode != 200) {
          throw AppException(
              'Kunde inte hämta dina spellistor (fel ${res.statusCode}).');
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final item in (body['items'] as List)) {
          if (item == null) continue;
          final p = Map<String, dynamic>.from(item as Map);
          final images = (p['images'] as List?) ?? [];
          final tracks = p['tracks'] as Map?;
          final owner = p['owner'] as Map?;
          playlists.add(PlaylistInfo(
            id: p['id'] as String,
            name: p['name'] as String? ?? 'Namnlös spellista',
            imageUrl: images.isEmpty ? null : images.first['url'] as String?,
            trackCount: (tracks?['total'] as num?)?.toInt() ?? 0,
            ownerName: owner?['display_name'] as String? ?? '',
          ));
        }
        final next = body['next'];
        if (next == null) break;
        url = Uri.parse(next as String);
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException.from(e);
    }
    return playlists;
  }

  @override
  Future<List<Track>> fetchPlaylistTracks(String playlistId) async {
    final token = await auth.ensureConnected();

    final tracks = <Track>[];
    var url = Uri.parse(
      '$_apiBase/playlists/$playlistId/tracks'
      '?fields=next,items(track(id,uri,name,artists(name),album(release_date,images)))'
      '&limit=100',
    );

    try {
      // Spotify paginerar; följ "next" tills den är null.
      while (true) {
        final res =
            await http.get(url, headers: {'Authorization': 'Bearer $token'});
        if (res.statusCode == 401) {
          throw const AppException(
              'Spotify-sessionen gick ut. Anslut igen och försök på nytt.');
        }
        if (res.statusCode == 404) {
          throw const AppException(
              'Spellistan hittades inte. Kontrollera spellistans ID.');
        }
        if (res.statusCode != 200) {
          throw AppException(
              'Kunde inte hämta spellistan (fel ${res.statusCode}).');
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
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException.from(e);
    }

    if (tracks.isEmpty) {
      throw const AppException(
          'Spellistan innehåller inga spelbara låtar med årtal.');
    }
    return tracks;
  }

  Track? _trackFromJson(Map<String, dynamic> t) {
    final album = t['album'] as Map?;
    final releaseDate =
        album?['release_date'] as String?; // "1975", "1975-11" el. "1975-11-21"
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
  Future<void> play(Track track) async {
    await auth.ensureConnected();
    try {
      await SpotifySdk.play(spotifyUri: track.uri);
    } catch (e) {
      // Ett vanligt fall: fjärranslutningen tappades. Försök återansluta en gång.
      try {
        await auth.ensureConnected();
        await SpotifySdk.play(spotifyUri: track.uri);
      } catch (e2) {
        throw AppException.from(e2);
      }
    }
  }

  @override
  Future<void> resume() async {
    try {
      await SpotifySdk.resume();
    } catch (e) {
      throw AppException.from(e);
    }
  }

  @override
  Future<void> pause() async {
    try {
      await SpotifySdk.pause();
    } catch (e) {
      throw AppException.from(e);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await SpotifySdk.pause();
    } catch (_) {
      // Tyst — inget att göra om vi redan är frånkopplade.
    }
  }

  @override
  Stream<PlaybackState> playbackStates() {
    return SpotifySdk.subscribePlayerState().map((PlayerState s) => PlaybackState(
          isPaused: s.isPaused,
          trackUri: s.track?.uri,
        ));
  }
}
