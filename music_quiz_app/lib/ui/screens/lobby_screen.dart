import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../models/game_room.dart';
import 'game_screen.dart';

/// Väntrummet: visar rumskoden och anslutna spelare. Värden startar spelet.
class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final room = controller.room;

    // Visa fel (t.ex. misslyckad spelstart) och rensa dem sedan.
    final error = controller.lastError;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        controller.clearError();
      });
    }

    // Navigera till spelet så fort värden startar.
    if (room?.status == RoomStatus.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: controller,
            child: const GameScreen(),
          ),
        ));
      });
    }

    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final players = room.players.values.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Väntrum')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rumskod', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(room.code,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 4),
            const Text('Dela koden — kompisar går med från startskärmen.'),
            const SizedBox(height: 24),
            Text('Spelare (${players.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: players.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = players[i];
                  final isHost = p.id == room.hostId;
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(p.name),
                    trailing: isHost
                        ? const Chip(label: Text('Värd'))
                        : null,
                  );
                },
              ),
            ),
            if (controller.isHost)
              FilledButton.icon(
                onPressed: (players.length < 2 || controller.busy)
                    ? null
                    : () => controller.hostStartGame(room.playlistId),
                icon: controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(controller.busy
                    ? 'Laddar spellista…'
                    : players.length < 2
                        ? 'Vänta på fler spelare…'
                        : 'Starta spelet'),
              )
            else
              const Center(child: Text('Väntar på att värden startar…')),
          ],
        ),
      ),
    );
  }
}
