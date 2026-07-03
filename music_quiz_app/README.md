# Musikquiz (Hitster-stil) — Flutter + Firebase + Spotify

Ett mobilt musikquiz där flera spelare, var och en med sin egen telefon, ansluter till
samma spelrum via en rumskod och tävlar i realtid: en låt spelas, och den aktiva spelaren
placerar den på sin tidslinje efter utgivningsår — precis som Hitster, fast digitalt.

- **Plattform:** Android först, iOS senare (samma kodbas via Flutter).
- **Musik:** Spotify (metadata via Web API, uppspelning via Spotify SDK — kräver Premium).
- **Flerspelare:** Firebase Realtime Database, realtidssynk mellan spelare.

> Detta är **fas 1: grunden**. Auth-, uppspelnings- och synk-flödena är strukturerade och
> kopplade, men kräver att du fyller i dina egna Spotify- och Firebase-uppgifter (se nedan)
> innan appen kan köras skarpt.

---

## Kom igång

### 0. Förutsättningar
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stabil kanal).
- Android Studio + en Android-enhet/emulator.
- Ett **Spotify Premium**-konto (krävs för uppspelning i appen).

### 1. Generera de nativa plattformsmapparna
Den här mappen innehåller Dart-koden och konfigurationen. Kör en gång för att skapa
`android/` och `ios/` (skriver **inte** över `lib/`, `pubspec.yaml` eller `README.md`):

```bash
cd music_quiz_app
flutter create . --platforms=android,ios --org se.derome
flutter pub get
```

### 2. Spotify
1. Skapa en app på <https://developer.spotify.com/dashboard>.
2. Lägg till en Redirect URI, t.ex. `musicquiz://callback`.
3. Notera **Client ID** och din **Redirect URI**.
4. På Android: registrera appens SHA-1-fingeravtryck i Spotify-dashboarden (annars vägrar
   SDK:t ansluta). Se `services/auth/spotify_auth_service.dart` för detaljer.
5. Kopiera `.env.example` → `.env` och fyll i värdena.

> **Obs om katalog/uppspelning:** Full uppspelning kräver att varje spelare har Spotify
> Premium. 30-sekunders `preview_url` från Web API är kraftigt begränsat för nya appar
> sedan nov 2024 och kan inte längre antas fungera. Musikkällan är abstraherad
> (`MusicSource`) så att Spotify kan bytas mot t.ex. Deezer/iTunes-previews eller egna
> licensierade klipp utan att röra spellogiken.

### 3. Firebase
1. Skapa ett projekt på <https://console.firebase.google.com>.
2. Aktivera **Realtime Database** och **Authentication → Anonymous**.
3. Installera FlutterFire och generera `lib/firebase_options.dart`:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
4. Publicera säkerhetsreglerna i `firebase/database.rules.json`.

### 4. Kör
```bash
flutter run
```

---

## Arkitektur

```
lib/
├── main.dart                     App-start: Firebase-init, providers
├── app.dart                      MaterialApp + routing
├── core/
│   └── theme.dart                Färger, typografi
├── models/                       Rena datamodeller (immutable, JSON till/från Firebase)
│   ├── track.dart
│   ├── player.dart
│   └── game_room.dart
├── services/
│   ├── music/
│   │   ├── music_source.dart          Abstrakt gränssnitt (bytbar musikkälla)
│   │   └── spotify_music_source.dart  Spotify-implementation (Web API + SDK)
│   ├── auth/
│   │   └── spotify_auth_service.dart  OAuth/PKCE + SDK-anslutning
│   └── multiplayer/
│       └── game_repository.dart       Firebase Realtime DB: rum, turer, poäng
├── game/
│   ├── scoring.dart              Ren spellogik: är placeringen rätt?
│   └── game_controller.dart      Speltillstånd (ChangeNotifier) som binder ihop allt
└── ui/
    ├── screens/                  Home, Lobby, Game
    └── widgets/                  Tidslinje, spelarlista m.m.
```

**Designprinciper**
- **Musikkällan är utbytbar.** Spellogiken beror bara på `MusicSource`, aldrig på Spotify
  direkt. Byt implementation utan att röra spelet.
- **Servern är sanningskällan.** Rummets tillstånd (turordning, poäng, tidslinjer) lever i
  Firebase; klienterna renderar det. Det gör realtidssynk och fusk-skydd enklare.
- **Ren spellogik.** `scoring.dart` är rena funktioner utan beroenden — enkelt att testa.

## Spelregler (fas 1)
1. Värden skapar ett rum och väljer en spellista + mål-antal kort (t.ex. 10).
2. Spelare ansluter med rumskoden. Alla loggar in på Spotify.
3. Turordning slumpas. Varje spelare har en egen tidslinje (startar med ett kort).
4. På din tur spelas en okänd låt. Du placerar den i din tidslinje där du tror den passar
   kronologiskt (efter utgivningsår).
5. Rätt placering → kortet stannar och du får poäng. Fel → kortet slängs.
6. Först till mål-antalet kort vinner.

## Roadmap
- [x] Fas 1: Projektstruktur, modeller, Firebase-rum, spellogik, kärnskärmar.
- [x] Fas 2: Robust Spotify-auth (anslutningstillstånd, token-förnyelse,
  återanslutning), uppspelning med play/paus, och genomgående felhantering
  med användarvänliga meddelanden (`core/app_exception.dart`).
- [ ] Fas 3: Full realtids-UI (tidslinje-drag & drop, live-poäng, återanslutning).
- [ ] Fas 4: "Steal"/utmaning, spellistval, avatarer, ljud/animationer.
- [ ] Fas 5: iOS-polish, App Store / Play Store-publicering.
