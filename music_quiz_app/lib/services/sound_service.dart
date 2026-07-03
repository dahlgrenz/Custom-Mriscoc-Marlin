import 'package:flutter/services.dart';

/// Enkel återkoppling vid spelhändelser via haptik + systemljud.
///
/// Håller inga binära ljudfiler (så appen fungerar direkt). Vill du ha riktiga
/// ljudeffekter: lägg till `audioplayers` i pubspec, lägg .mp3-filer under
/// `assets/sounds/`, och byt ut kropparna nedan mot AudioPlayer-anrop.
class SoundService {
  Future<void> correct() async {
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
  }

  Future<void> wrong() async {
    await HapticFeedback.heavyImpact();
  }

  Future<void> steal() async {
    await HapticFeedback.selectionClick();
    await SystemSound.play(SystemSoundType.click);
  }
}
