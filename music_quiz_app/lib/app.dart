import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/auth/spotify_auth_service.dart';
import 'services/lan_server_service.dart';
import 'services/multiplayer/game_repository.dart';
import 'services/music/music_source.dart';
import 'services/music/spotify_music_source.dart';
import 'services/sound_service.dart';
import 'services/tag_repository.dart';
import 'ui/screens/home_screen.dart';

class MusicQuizApp extends StatelessWidget {
  const MusicQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Enkel dependency injection via provider. Byt SpotifyMusicSource här om du
    // vill använda en annan musikkälla — inget annat behöver ändras.
    final auth = SpotifyAuthService();
    return MultiProvider(
      providers: [
        // ChangeNotifier så UI:t kan lyssna på anslutnings-/felstatus.
        ChangeNotifierProvider<SpotifyAuthService>.value(value: auth),
        Provider<GameRepository>(create: (_) => GameRepository()),
        Provider<MusicSource>(create: (_) => SpotifyMusicSource(auth)),
        Provider<SoundService>(create: (_) => SoundService()),
        Provider<TagRepository>(create: (_) => TagRepository()),
        Provider<LanServerService>(
          create: (_) => LanServerService(),
          dispose: (_, s) => s.stop(),
        ),
      ],
      child: MaterialApp(
        title: 'Musikquiz',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
