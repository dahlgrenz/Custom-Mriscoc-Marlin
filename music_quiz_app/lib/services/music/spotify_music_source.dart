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

    // (Track, artistId) — artist-id:t används för att hämta genrer efteråt.
    final parsed = <(Track, String?)>[];
    var url = Uri.parse(
      '$_apiBase/playlists/$playlistId/tracks'
      '?fields=next,items(track(id,uri,name,popularity,artists(id,name),album(release_date,images)))'
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
          final p = _parseTrack(Map<String, dynamic>.from(t as Map));
          if (p != null) parsed.add(p);
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

    if (parsed.isEmpty) {
      throw const AppException(
          'Spellistan innehåller inga spelbara låtar med årtal.');
    }

    // Berika med genrer (best effort — filtret klarar sig utan om det misslyckas).
    final genresByArtist = await _fetchArtistGenres(
      token,
      parsed.map((p) => p.$2).whereType<String>().toSet(),
    );

    return [
      for (final (track, artistId) in parsed)
        (artistId != null && genresByArtist.containsKey(artistId))
            ? track.copyWith(genres: genresByArtist[artistId])
            : track,
    ];
  }

  (Track, String?)? _parseTrack(Map<String, dynamic> t) {
    final album = t['album'] as Map?;
    final releaseDate =
        album?['release_date'] as String?; // "1975", "1975-11" el. "1975-11-21"
    if (releaseDate == null || releaseDate.isEmpty) return null;
    final year = int.tryParse(releaseDate.split('-').first);
    if (year == null) return null;

    final artists = (t['artists'] as List?) ?? [];
    final images = (album?['images'] as List?) ?? [];
    final firstArtist = artists.isEmpty ? null : artists.first as Map;

    final track = Track(
      id: t['id'] as String,
      uri: t['uri'] as String,
      title: t['name'] as String,
      artist: firstArtist == null ? 'Okänd' : (firstArtist['name'] as String),
      year: year,
      albumArtUrl: images.isEmpty ? null : images.first['url'] as String?,
      popularity: (t['popularity'] as num?)?.toInt() ?? 0,
    );
    return (track, firstArtist?['id'] as String?);
  }

  /// Hämtar genrer per artist-id via /artists (batchar 50 åt gången).
  /// Genrer är valfria: vid fel returneras helt enkelt färre/inga.
  Future<Map<String, List<String>>> _fetchArtistGenres(
      String token, Set<String> ids) async {
    final result = <String, List<String>>{};
    final list = ids.toList();
    try {
      for (var i = 0; i < list.length; i += 50) {
        final end = (i + 50 > list.length) ? list.length : i + 50;
        final chunk = list.sublist(i, end);
        final res = await http.get(
          Uri.parse('$_apiBase/artists?ids=${chunk.join(",")}'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final a in (body['artists'] as List? ?? [])) {
          if (a == null) continue;
          final m = Map<String, dynamic>.from(a as Map);
          result[m['id'] as String] =
              (m['genres'] as List?)?.map((g) => '$g').toList() ?? [];
        }
      }
    } catch (_) {
      // Genrer är valfria — ignorera fel.
    }
    return result;
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
