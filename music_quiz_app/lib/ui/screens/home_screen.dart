import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../services/auth/spotify_auth_service.dart';
import '../../services/multiplayer/game_repository.dart';
import '../../services/music/music_source.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  // Standardspellista — byt gärna. (Detta är Spotifys "Top 50 – Global".)
  static const _defaultPlaylist = '37i9dQZEVXbMDoHDwVN2tF';

  bool _busy = false;
  bool _spotifyConnected = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _myId => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _connectSpotify() async {
    final auth = context.read<SpotifyAuthService>();
    await _run(() async {
      final ok = await auth.connect();
      setState(() => _spotifyConnected = ok);
      if (!ok) _toast('Kunde inte ansluta till Spotify.');
    });
  }

  Future<void> _createRoom() async {
    if (!_validate()) return;
    final repo = context.read<GameRepository>();
    await _run(() async {
      final code = await repo.createRoom(
        hostId: _myId,
        hostName: _nameController.text.trim(),
        playlistId: _defaultPlaylist,
      );
      _openLobby(code);
    });
  }

  Future<void> _joinRoom() async {
    if (!_validate()) return;
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return _toast('Ange en rumskod.');
    final repo = context.read<GameRepository>();
    await _run(() async {
      await repo.joinRoom(
        code: code,
        playerId: _myId,
        playerName: _nameController.text.trim(),
      );
      _openLobby(code);
    });
  }

  void _openLobby(String code) {
    final controller = GameController(
      repo: context.read<GameRepository>(),
      music: context.read<MusicSource>(),
      myPlayerId: _myId,
    )..bindRoom(code);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: controller,
        child: const LobbyScreen(),
      ),
    ));
  }

  bool _validate() {
    if (_nameController.text.trim().isEmpty) {
      _toast('Skriv ditt namn först.');
      return false;
    }
    if (!_spotifyConnected) {
      _toast('Anslut till Spotify först.');
      return false;
    }
    return true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text('🎵 Musikquiz',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              Text('Placera låten rätt i tiden — snabbast vinner!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 40),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Ditt namn',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _connectSpotify,
                icon: Icon(_spotifyConnected ? Icons.check_circle : Icons.music_note),
                label: Text(_spotifyConnected ? 'Spotify anslutet' : 'Anslut Spotify'),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : _createRoom,
                child: const Text('Skapa spel'),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Rumskod',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: _busy ? null : _joinRoom,
                  child: const Text('Gå med'),
                ),
              ]),
              const Spacer(),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
