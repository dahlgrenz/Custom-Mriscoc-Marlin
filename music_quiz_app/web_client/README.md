# Webbklient

En fristående webbsida (ren HTML/JS + Firebase Web SDK) som **värdens
Android-telefon serverar över det lokala nätverket**. Andra enheter — iPhone,
Android, dator — öppnar QR-länken (`http://<telefonens-ip>:8080/?code=ABCD`) i
webbläsaren och ansluter till spelet. Ingen app-installation krävs.

## Hur det hänger ihop
- Mobilappens `LanServerService` startar en HTTP-server och serverar den här
  mappen (buntad som Flutter-assets under `web_client/`).
- Webbklienten pratar **direkt med samma Firebase-databas** som mobilappen, så
  webbspelare hamnar i samma spelrum. Den lokala servern distribuerar bara sidan.
- Låten spelas **högt på värdens telefon** (jukebox). Webbspelare hör alltså
  musiken i rummet och gissar — de behöver inget eget Spotify.

## Konfiguration
Öppna `firebase-config.js` och klistra in din Firebase-webbkonfiguration (samma
projekt som mobilappen). Nycklarna är publika till sin natur; säkerheten ligger i
databasreglerna (`../firebase/database.rules.json`).

## Begränsningar
- **Internet krävs** för Firebase (realtidssynk), även om sidan serveras lokalt.
- **Samma Wi-Fi:** alla enheter måste vara på samma nätverk som värdtelefonen.
  Vissa gäst-/företagsnät blockerar enhet-till-enhet-trafik ("client isolation").
- **HTTP (inte HTTPS):** Firebase fungerar över http-origin, men webbläsar-
  funktioner som kräver "secure context" (t.ex. Spotify Web Playback) gör inte
  det — därför spelar värdtelefonen musiken, inte webbklienten.
- Håll spellogiken här i synk med `lib/game/` om du ändrar reglerna.
