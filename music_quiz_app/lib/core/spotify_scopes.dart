/// En valfri Spotify-behörighet som användaren själv kan bocka i eller ur.
class SpotifyScope {
  /// Spotify-scope-id, t.ex. "user-top-read".
  final String id;
  final String label;
  final String description;

  const SpotifyScope(this.id, this.label, this.description);
}

/// Grundbehörigheter som alltid krävs (uppspelning + läsa dina spellistor).
/// Utan dem kan värden inte spela musik eller hämta en spellista.
const List<String> kBaseScopes = [
  'app-remote-control',
  'streaming',
  'playlist-read-private',
  'playlist-read-collaborative',
];

/// Valfria behörigheter — låser upp personliga quiz (fas 8/9). Användaren
/// väljer själv vilka som ska ges; inget av detta krävs för att spela.
const List<SpotifyScope> kOptionalScopes = [
  SpotifyScope(
    'user-top-read',
    'Topplåtar & toppartister',
    'För personliga quiz om din musiksmak och "Vem känner vem bäst?".',
  ),
  SpotifyScope(
    'user-library-read',
    'Gillade & sparade låtar',
    'Skapa quiz ur ditt eget bibliotek.',
  ),
  SpotifyScope(
    'user-read-recently-played',
    'Nyligen spelade',
    'Quiz om det du lyssnat på senast.',
  ),
];
