import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

import '../../core/app_exception.dart';

enum SpotifyConnectionState { disconnected, connecting, connected, error }

/// Sköter anslutning till Spotify-appen på enheten via Spotify SDK.
///
/// Är en [ChangeNotifier] så att UI:t kan reagera på anslutnings- och felstatus.
/// Hanterar även att access-token går ut (~1 h) genom att förnya vid behov.
///
/// Setup som krävs (se README):
///  - SPOTIFY_CLIENT_ID och SPOTIFY_REDIRECT_URI i .env
///  - Redirect URI registrerad i Spotify-dashboarden
///  - På Android: appens SHA-1-fingeravtryck registrerat i dashboarden
///  - Spotify-appen installerad + Premium på enheten
class SpotifyAuthService extends ChangeNotifier {
  static const _scope =
      'app-remote-control,streaming,playlist-read-private,playlist-read-collaborative';

  // Förnya token en stund innan den faktiskt går ut, för marginal.
  static const _tokenLifetime = Duration(minutes: 55);

  String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  String get _redirectUri => dotenv.env['SPOTIFY_REDIRECT_URI'] ?? '';

  SpotifyConnectionState _state = SpotifyConnectionState.disconnected;
  SpotifyConnectionState get state => _state;

  String? _lastError;
  String? get lastError => _lastError;

  String? _accessToken;
  DateTime? _tokenExpiry;

  bool get isConnected => _state == SpotifyConnectionState.connected;

  bool get _tokenValid =>
      _accessToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  void _setState(SpotifyConnectionState s, {String? error}) {
    _state = s;
    _lastError = error;
    notifyListeners();
  }

  /// Kopplar upp mot Spotify-appen och hämtar en access-token för Web API-anrop.
  /// Returnerar true vid lyckad anslutning.
  Future<bool> connect() async {
    if (_clientId.isEmpty || _redirectUri.isEmpty) {
      _setState(SpotifyConnectionState.error,
          error:
              'Saknar SPOTIFY_CLIENT_ID / SPOTIFY_REDIRECT_URI. Fyll i .env (se README).');
      return false;
    }

    _setState(SpotifyConnectionState.connecting);
    try {
      final connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: _clientId,
        redirectUrl: _redirectUri,
      );
      if (!connected) {
        _setState(SpotifyConnectionState.error,
            error: 'Kunde inte ansluta till Spotify. Är appen installerad?');
        return false;
      }
      await _refreshToken();
      _setState(SpotifyConnectionState.connected);
      return true;
    } catch (e) {
      _setState(SpotifyConnectionState.error,
          error: AppException.from(e).message);
      return false;
    }
  }

  /// Ser till att vi är uppkopplade med en giltig token — förnyar/återansluter
  /// vid behov. Kastar [AppException] om det inte går. Anropa före API/uppspelning.
  Future<String> ensureConnected() async {
    if (isConnected && _tokenValid) return _accessToken!;

    if (_state != SpotifyConnectionState.connected) {
      final ok = await connect();
      if (!ok) throw AppException(_lastError ?? 'Kunde inte ansluta till Spotify.');
      return _accessToken!;
    }

    // Uppkopplad men token utgången → förnya bara token.
    await _refreshToken();
    return _accessToken!;
  }

  Future<void> _refreshToken() async {
    final token = await SpotifySdk.getAccessToken(
      clientId: _clientId,
      redirectUrl: _redirectUri,
      scope: _scope,
    );
    _accessToken = token;
    _tokenExpiry = DateTime.now().add(_tokenLifetime);
  }

  Future<void> disconnect() async {
    try {
      await SpotifySdk.disconnect();
    } catch (_) {
      // Ignorera fel vid frånkoppling — vi nollställer ändå.
    }
    _accessToken = null;
    _tokenExpiry = null;
    _setState(SpotifyConnectionState.disconnected);
  }
}
