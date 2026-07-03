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
│   ├── theme.dart                Färger, typografi
│   └── app_exception.dart        Typade fel → svenska användarmeddelanden
├── models/                       Rena datamodeller (immutable, JSON till/från Firebase)
│   ├── track.dart
│   ├── player.dart
│   ├── playlist_info.dart
│   └── game_room.dart
├── services/
│   ├── music/
│   │   ├── music_source.dart          Abstrakt gränssnitt (bytbar musikkälla)
│   │   └── spotify_music_source.dart  Spotify-implementation (Web API + SDK)
│   ├── auth/
│   │   └── spotify_auth_service.dart  OAuth/PKCE + SDK-anslutning
│   ├── multiplayer/
│   │   └── game_repository.dart       Firebase Realtime DB: rum, turer, poäng
│   ├── lan_server_service.dart        LAN-webbserver som serverar web_client/
│   └── sound_service.dart             Ljud/haptik vid rätt/fel/stöld
├── game/
│   ├── scoring.dart              Ren spellogik: är placeringen rätt?
│   └── game_controller.dart      Speltillstånd (ChangeNotifier) som binder ihop allt
└── ui/
    └── screens/                  Home, PlaylistPicker, Lobby, Game
```

**Designprinciper**
- **Musikkällan är utbytbar.** Spellogiken beror bara på `MusicSource`, aldrig på Spotify
  direkt. Byt implementation utan att röra spelet.
- **Servern är sanningskällan.** Rummets tillstånd (turordning, poäng, tidslinjer) lever i
  Firebase; klienterna renderar det. Det gör realtidssynk och fusk-skydd enklare.
- **Ren spellogik.** `scoring.dart` är rena funktioner utan beroenden — enkelt att testa.

## Gå med via QR / webben (ingen app-installation)
Värdens Android-telefon är "jukebox": den spelar musiken högt via Spotify och
**startar en liten webbserver på det lokala nätverket**. I väntrummet visas en
**QR-kod** som pekar på `http://<telefonens-ip>:8080/?code=ABCD`. Alla på samma
Wi-Fi — iPhone, Android, dator — skannar den, öppnar webbklienten
(`web_client/`) i webbläsaren och ansluter till samma spelrum via Firebase.

- Webbspelare **hör musiken i rummet** (från värdens telefon) och placerar sina
  gissningar i webbläsaren — de behöver inget eget Spotify.
- Webbklientens spellogik speglar `lib/game/` och skriver till samma Firebase-DB.
- Förutsättningar/begränsningar (internet krävs för Firebase, samma Wi-Fi, http):
  se `web_client/README.md`.

### Konfiguration
1. Fyll i din Firebase-webbkonfiguration i `web_client/firebase-config.js`
   (samma projekt som mobilappen).
2. Klart — `web_client/` buntas som assets och serveras automatiskt av värden.

### Samma rum (LAN) eller på distans (Firebase Hosting)
Värden kan i väntrummet välja vart QR-koden pekar:
- **Samma rum:** `http://<telefonens-ip>:8080/?code=…` — enheter på samma Wi-Fi.
- **På distans:** en publik Hosting-URL — funkar var som helst, över https.

För distansläget: sätt `HOSTING_URL` i `.env` (t.ex. `https://ditt-projekt.web.app`)
och deploya webbklienten en gång:
```bash
npm i -g firebase-tools
firebase login
cd music_quiz_app && firebase deploy --only hosting   # använder firebase.json → public: web_client
```
Är `HOSTING_URL` tom visas bara LAN-läget.

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
- [x] Val av spellista: värden bläddrar bland sina Spotify-spellistor och väljer
  en innan rummet skapas (`ui/screens/playlist_picker_screen.dart`); namnet visas
  i lobbyn.
- [x] Fas 3: Realtids-UI — dra-och-släpp av låten till rätt plats i tidslinjen,
  animerade kort och poäng, samt offline-banner med automatisk återanslutning.
- [x] Fas 4: "Steal" (gissar den aktiva spelaren fel får nästa spelare stjäla
  kortet), val av mål-antal kort i lobbyn, emoji-avatarer per spelare, och
  ljud-/haptic-återkoppling vid rätt/fel/stöld (`services/sound_service.dart`).
- [x] Gå med via QR/webben: värden delar en QR-kod till en LAN-serverad
  webbklient (`web_client/` + `services/lan_server_service.dart`); iOS/Android/
  dator kan ansluta utan app. Värden blev "jukebox" (spelar musiken högt).
- [x] Interaktiv leaderboard (`ui/widgets/leaderboard.dart`) som uppdateras
  varje omgång och visar vem som leder — i spelet, i en bottensheet och på
  resultatskärmen. Speglad i webbklienten.
- [x] Årtalsläge: nytt spelläge (välj i lobbyn) där man gissar utgivningsåret
  med ett reglage; poäng efter träffsäkerhet — **5** för exakt, **3** för 1–2
  år fel, **1** för 3–5 år fel, annars 0 (`Scoring.yearGuessPoints`). Vinst på
  poängmål i stället för antal kort.
- [x] Slumpat namn vid QR-anslutning: webbspelare får ett förifyllt, redigerbart
  namn direkt.
- [x] Filter för att skapa varierade quiz (`game/track_filter.dart` +
  `ui/screens/filter_screen.dart`): decennium, artist, genre och popularitet
  direkt från Spotify, plus kuraterade taggar (Melodifestivalen, land,
  placering) via `tag_data/*.csv` (`services/tag_repository.dart`). Live-räknare
  "X av Y låtar matchar" i lobbyn.
- [ ] Fas 5: iOS-polish, App Store / Play Store-publicering.

### Steal-mekaniken
Den aktiva spelaren gissar var låten hör hemma. Blir det **rätt** behåller hen
kortet och turen går vidare. Blir det **fel** går rundan in i steal-fasen: nästa
spelare får en chans att placera samma låt i sin egen tidslinje och stjäla kortet.
Rundans fas (`guessing`/`stealing`) och vem som får stjäla lever i rummet, så alla
klienter är överens om läget.
