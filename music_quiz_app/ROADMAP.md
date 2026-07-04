# Roadmap & genomförbarhet

En bedömning av den stora funktionslistan, uppdelad i **faser**. Varje punkt är
märkt efter hur genomförbar den är med vår nuvarande stack (Flutter + Firebase +
Spotify).

## Genomförbarhets-legend
- ✅ **Går nu** — med Spotify Web API / SDK + vår kod.
- 🟡 **Går med egen data** — kräver kuraterade filer (`tag_data/`) eller en extra tjänst.
- 🔴 **Går inte (rimligt)** — Spotify tillhandahåller det inte, eller stängde det
  för nya appar i nov 2024.

### Viktiga Spotify-begränsningar (avgör mycket nedan)
- 🔴 **Audio Features** (BPM, energi, dansbarhet, valens, akustisk nivå) —
  **borttaget** för nya appar. → filter på tempo/energi/mood går inte.
- 🔴 **Rekommendationer / relaterade artister / "Discover Weekly"-motorn** — borttaget.
- 🔴 **Låttexter (lyrics)** — finns inte i API:t (Spotify licensierar från Musixmatch).
- 🔴 **Musikvideo / TikTok** — inte Spotify (skulle kräva YouTube m.m.).
- 🔴 **Exakt antal spelningar per låt** och **Spotify Wrapped** — exponeras inte.
- 🔴 **Artistens land / kön / Grammys / producent / bildningsår** — inte i API:t.
- ✅ **Går bra:** spellistor, gillade/sparade låtar, **topplåtar/toppartister**
  (`/me/top/*`), **nyligen spelade**, genrer (via artist), albumomslag,
  popularitet, och uppspelning med **seek** (→ introtävling).

---

## Fas 6 — Frågemotor & klassiska lägen ✅ **KLAR**
Grunden för väldigt många lägen nedan. Implementerat: nytt läge **Klassisk**
(`GameMode.classic`), värddriven rundloop, samtidiga svar, timer och poäng.
- ✅ **Flervalsfrågor (4 alternativ)** — distraktorer genereras ur spellistan
  (`game/question.dart`): "Vilken låt/artist/år?"
- ✅ **Rondtimer** (15 s) + **snabbast-svar-poäng** (100 + upp till 100 i bonus)
- ✅ **Streak / flest rätt i rad** (bästa svit sparas som statistik)
- ⏳ Kvar i denna kategori: Alla mot alla / Eliminering / Last Man Standing som
  egna varianter ovanpå frågemotorn.

## Fas 7 — Fler frågetyper ur Spotify-data ✅ / 🟡
- ✅ **Introtävling** (spela 2–10 s från början via SDK-seek)
- ✅ **Gissa albumomslag** (bild; suddig/zoomad = klientfilter)
- ✅ Gissa **år / genre**
- 🟡 Gissa **land** (kräver `tag_data`)
- 🔴 Refräng / gitarrsolo / trumfill (kräver audio-analys som är borttagen)
- 🔴 Vad kommer nästa textrad? / lyrics-lägen (ingen lyrics-API)
- 🔴 Live eller studio? (ingen tillförlitlig signal)

## Fas 8 — Personliga Spotify-quiz ✅
Kräver fler Spotify-scopes (user-library-read, user-top-read, user-read-recently-played).
- ✅ **Endast gillade låtar** (`/me/tracks`), sparade album, mina spellistor
- ✅ **Mina topplåtar / toppartister / toppgenrer** (`/me/top/*`)
- ✅ **Nyligen spelade** (`/me/player/recently-played`)
- 🔴 Discover Weekly/Release Radar-motorn, "mest spelade genom tiderna" (exakta counts)

## Fas 9 — "Vem känner vem bäst?" (viral idé) ✅ *(delvis)*
Varje spelare loggar in med Spotify; appen jämför deras `/me/top/*`.
- ✅ "Vem har den här artisten i sin topp 10?"
- ✅ "Vem lyssnar mest på rock?" (härleds ur toppartisternas genrer)
- ✅ "Vilka två har mest lik musiksmak?" (överlapp i topplistor)
- ✅ "Vilken låt passar bara en av er?"
- 🔴 "Vem har spelat låten flest gånger?" / "vem upptäckte artisten först?"
  (exakta counts/tidsstämplar finns inte — kan approximeras med topp-ranking)

## Fas 10 — Partyfunktioner & specialronder ✅
- ✅ Bonusrunda, **dubbelpoäng**, straffrunda, **joker**, stjäl poäng,
  slumpkategori, **Mystery Song**, Wheel of Fortune

## Fas 11 — Sociala funktioner ✅ / 🔴
- ✅ Privata/publika rum (finns), **emoji-reaktioner**, **chatt**, jubel/burop,
  publikomröstningar (Firebase)
- 🔴 **Röstchat** (kräver WebRTC + TURN-server — separat, stort projekt)

## Fas 12 — Statistik, achievements & ranking ✅
Kräver att vi sparar spelarprofiler i Firebase.
- ✅ Efter-spel-statistik (rätt%, reaktionstid, bästa/sämsta kategori)
- ✅ **Achievements** (10 raka, Popkung, Introexpert …)
- ✅ **Ranking** (vänner/lokal/global), **ELO-rating**

## Fas 13 — Säsonger & teman 🟡
- ✅ **80-tal / 90-tal** (decennium-filter finns redan)
- 🟡 **Melodifestivalen / Eurovision / Jul** (kuraterade `tag_data`-listor)

## Fas 14 — AI-funktioner ✅ *(kräver backend + API-nyckel)*
Via en LLM (t.ex. Claude API) genom en liten server.
- ✅ AI genererar tema/frågor, ledtrådar, matchkommentarer, svårighetsanpassning
- Obs: en LLM-nyckel får inte ligga i klienten — kräver en enkel proxy/backend.

## Lägen som skalar men behöver mer arbete
- 🟡 **Lag / Battle 1v1 / Turnering / Co-op** — bygger på Fas 6, men mer UI/logik.
- 🟡 **Royal Rumble (100 spelare)** — Firebase klarar det, men kräver
  prestanda-/kostnadsöversyn och robustare rums-hantering.
- 🟡 **Musikbingo / Jeopardy / Escape Room / Beat the AI** — egna större lägen.

---

## Sammanfattning
Ungefär **70–80 %** av listan går att bygga. Det som **inte** går faller nästan
alltid på tre saker: borttagna Spotify-endpoints (tempo/energi/rekommendationer),
avsaknad av lyrics/video-API, och data Spotify inte har (land/kön/trivia/counts) —
och de flesta av dem kan ändå lösas med **kuraterade `tag_data`-filer** eller en
extra tjänst.

**Rekommenderad ordning:** Fas 6 (frågemotorn) först — den låser upp flest andra
lägen. Därefter Fas 8/9 (personliga Spotify-quiz + "Vem känner vem bäst?") som är
det som gör appen unik och delningsbar.
