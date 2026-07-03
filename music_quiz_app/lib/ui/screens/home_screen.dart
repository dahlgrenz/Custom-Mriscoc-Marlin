import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../services/auth/spotify_auth_service.dart';
import '../../services/multiplayer/game_repository.dart';
import '../../models/playlist_info.dart';
import '../../services/music/music_source.dart';
import 'lobby_screen.dart';
import 'playlist_picker_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _myId => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _connectSpotify() async {
    final auth = context.read<SpotifyAuthService>();
    await _run(() => auth.connect());
  }

  Future<void> _createRoom() async {
    if (!_validate()) return;

    // Låt värden välja spellista innan rummet skapas.
    final playlist = await Navigator.of(context).push<PlaylistInfo>(
      MaterialPageRoute(builder: (_) => const PlaylistPickerScreen()),
    );
    if (playlist == null || !mounted) return; // avbröt valet

    final repo = context.read<GameRepository>();
    await _run(() async {
      final code = await repo.createRoom(
        hostId: _myId,
        hostName: _nameController.text.trim(),
        playlistId: playlist.id,
        playlistName: playlist.name,
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
    if (!context.read<SpotifyAuthService>().isConnected) {
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<SpotifyAuthService>();
    final connected = auth.state == SpotifyConnectionState.connected;
    final connecting = auth.state == SpotifyConnectionState.connecting;

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
                onPressed: (_busy || connecting || connected)
                    ? null
                    : _connectSpotify,
                icon: connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(connected ? Icons.check_circle : Icons.music_note),
                label: Text(connected
                    ? 'Spotify anslutet'
                    : connecting
                        ? 'Ansluter…'
                        : 'Anslut Spotify'),
              ),
              if (auth.state == SpotifyConnectionState.error &&
                  auth.lastError != null) ...[
                const SizedBox(height: 8),
                Text(auth.lastError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13)),
              ],
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
