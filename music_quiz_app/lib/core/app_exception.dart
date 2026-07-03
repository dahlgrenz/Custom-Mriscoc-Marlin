import 'package:flutter/services.dart';

/// Ett fel med ett meddelande som är tänkt att visas direkt för användaren
/// (på svenska), plus valfri teknisk orsak för loggning.
class AppException implements Exception {
  final String message;
  final Object? cause;
  const AppException(this.message, [this.cause]);

  @override
  String toString() => message;

  /// Översätter råa fel (särskilt Spotify-SDK:ns [PlatformException]) till
  /// begripliga svenska meddelanden.
  factory AppException.from(Object error) {
    if (error is AppException) return error;

    if (error is PlatformException) {
      final code = error.code;
      final details = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();

      if (code.contains('NotLoggedIn') || details.contains('not logged in')) {
        return AppException(
            'Du är inte inloggad på Spotify. Anslut och försök igen.', error);
      }
      if (code.contains('Authentication') || details.contains('auth')) {
        return AppException(
            'Spotify-inloggningen misslyckades. Kontrollera kontot och försök igen.',
            error);
      }
      if (details.contains('premium')) {
        return AppException(
            'Uppspelning i appen kräver Spotify Premium.', error);
      }
      if (code.contains('SpotifyDisconnected') ||
          details.contains('disconnect')) {
        return AppException(
            'Tappade kontakten med Spotify. Kontrollera att Spotify-appen är öppen.',
            error);
      }
      if (details.contains('no active device') ||
          details.contains('no device')) {
        return AppException(
            'Ingen aktiv Spotify-enhet. Öppna Spotify-appen och spela något kort.',
            error);
      }
      return AppException(
          'Ett Spotify-fel uppstod: ${error.message ?? code}', error);
    }

    return AppException('Något gick fel: $error', error);
  }
}
