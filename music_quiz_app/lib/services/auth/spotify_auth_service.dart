import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

/// Sköter anslutning till Spotify-appen på enheten via Spotify SDK.
///
/// Setup som krävs (se README):
///  - SPOTIFY_CLIENT_ID och SPOTIFY_REDIRECT_URI i .env
///  - Redirect URI registrerad i Spotify-dashboarden
///  - På Android: appens SHA-1-fingeravtryck registrerat i dashboarden
///  - Spotify-appen installerad + Premium på enheten
class SpotifyAuthService {
  String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  String get _redirectUri => dotenv.env['SPOTIFY_REDIRECT_URI'] ?? '';

  String? _accessToken;
  String? get accessToken => _accessToken;
  bool get isConnected => _accessToken != null;

  /// Kopplar upp mot Spotify-appen och hämtar en access-token för Web API-anrop.
  Future<bool> connect() async {
    if (_clientId.isEmpty || _redirectUri.isEmpty) {
      throw StateError(
        'Saknar SPOTIFY_CLIENT_ID / SPOTIFY_REDIRECT_URI. Fyll i .env (se README).',
      );
    }

    final connected = await SpotifySdk.connectToSpotifyRemote(
      clientId: _clientId,
      redirectUrl: _redirectUri,
    );
    if (!connected) return false;

    _accessToken = await SpotifySdk.getAccessToken(
      clientId: _clientId,
      redirectUrl: _redirectUri,
      // Räcker för spellistor och uppspelning.
      scope: 'app-remote-control,streaming,playlist-read-private',
    );
    return _accessToken != null;
  }

  Future<void> disconnect() async {
    await SpotifySdk.disconnect();
    _accessToken = null;
  }
}
