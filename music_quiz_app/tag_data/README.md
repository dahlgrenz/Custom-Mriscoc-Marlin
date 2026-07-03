# Egna taggar (extra statistik Spotify saknar)

Här lägger du textfiler med data som Spotify inte har — t.ex. deltagande i
**Melodifestivalen**, artistens **land** eller **listplacering** — så att spelet
kan filtrera på det.

## Kom igång
1. Kopiera `tags.example.csv` → `tags.csv`.
2. Fyll på med dina egna rader (se syntaxen i exempelfilen).
3. Filen buntas som asset och läses in vid start (lägg till i `pubspec.yaml`:
   `assets: - tag_data/tags.csv`).

> Obs: mappen heter `tag_data/` (inte `tags/`) eftersom det omgivande repots
> `.gitignore` blockerar namnet `tags` (reserverat för ctags).

Du kan ha flera filer (t.ex. `melodifestivalen.csv`, `usa.csv`) — lägg till var
och en under `assets:`.

## Format (sammanfattning)
```
artist;titel;taggar
Loreen;Euphoria;melodifestivalen,land=se,ar=2012,placering=1,vinnare
```
- `;` skiljer de tre kolumnerna: **artist**, **titel**, **taggar**.
- Taggar är kommaseparerade och kan vara **etiketter** (`melodifestivalen`) eller
  **nyckel=värde** (`land=se`, `ar=2012`, `placering=1`). Egna nycklar blir
  automatiskt filtrerbara.
- Rader som börjar med `#` är kommentarer.

## Hur matchningen fungerar
Appen normaliserar både din rad och Spotify-låten (gör om till gemener, tar bort
`feat. …`, parenteser och skiljetecken) och jämför **artist + titel**. Hittas en
träff hängs taggarna på den låten. Matchningen är avsiktligt "förlåtande" så att
små skillnader i stavning inte spelar roll — men dubbelkolla ovanliga titlar.

> Tips: vill du vara exakt kan formatet utökas med en `spotify_uri`-kolumn (då
> matchas låten på id i stället för text). Säg till så lägger jag till det.

## Vad som händer sen
När taggfilen finns dyker taggarna upp som **filterval** (t.ex. "Bara
Melodifestivalen", "Svenska bidrag", "Vinnare", "Topp 3") i lobbyn, utöver de
Spotify-baserade filtren (decennium, artist, genre, popularitet, längd …).

> Själva inläsningen och filtren är inte inkopplade i koden ännu — den här mallen
> definierar formatet. Nästa steg är att bygga taggläsaren + filter-UI:t.
