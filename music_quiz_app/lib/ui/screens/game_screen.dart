import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../models/game_room.dart';
import '../../models/player.dart';
import '../../models/track.dart';

/// Huvudskärmen under spel: den spelande låten och din tidslinje med
/// insättningsplatser. På din tur placerar du låten; annars ser du på.
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final room = controller.room;
    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (room.status == RoomStatus.finished) {
      return _WinnerView(room: room);
    }

    final me = controller.me;
    final round = room.currentRound;
    final activeName = room.players[round?.activePlayerId]?.name ?? '–';

    // Visa eventuella fel som en SnackBar och rensa dem sedan.
    final error = controller.lastError;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        controller.clearError();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Först till ${room.targetCards} kort'),
        actions: [_ScoreSummary(room: room)],
      ),
      body: Column(
        children: [
          _NowPlaying(
            track: round?.track,
            myTurn: controller.isMyTurn,
            activeName: activeName,
            isPaused: controller.isPaused,
            onToggle: controller.togglePlayback,
          ),
          const Divider(height: 1),
          Expanded(
            child: me == null
                ? const Center(child: Text('Laddar din tidslinje…'))
                : _Timeline(
                    player: me,
                    canPlace: controller.isMyTurn,
                    onPlace: (pos) => controller.placeCurrentTrack(pos),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final Track? track;
  final bool myTurn;
  final String activeName;
  final bool isPaused;
  final VoidCallback onToggle;

  const _NowPlaying({
    required this.track,
    required this.myTurn,
    required this.activeName,
    required this.isPaused,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Text(myTurn ? 'Din tur — var i tiden hör låten hemma?' : '$activeName spelar',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Icon(Icons.album, size: 48),
          const SizedBox(height: 8),
          // Årtalet döljs medvetet — det är det man ska gissa.
          Text(track?.title ?? '—',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          Text(track?.artist ?? '',
              style: Theme.of(context).textTheme.bodyMedium),
          if (myTurn) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onToggle,
              icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
              label: Text(isPaused ? 'Spela' : 'Pausa'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final Player player;
  final bool canPlace;
  final void Function(int position) onPlace;

  const _Timeline({
    required this.player,
    required this.canPlace,
    required this.onPlace,
  });

  @override
  Widget build(BuildContext context) {
    final timeline = player.timeline;
    // Bygg en rad med insättningsknappar mellan varje kort: [+] kort [+] kort [+]
    final children = <Widget>[];
    for (var i = 0; i <= timeline.length; i++) {
      children.add(_InsertSlot(
        enabled: canPlace,
        onTap: () => onPlace(i),
      ));
      if (i < timeline.length) children.add(_CardTile(track: timeline[i]));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Din tidslinje',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _InsertSlot extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _InsertSlot({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add),
        label: const Text('Placera här'),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            style: BorderStyle.solid,
          ),
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final Track track;
  const _CardTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${track.year}')),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _ScoreSummary extends StatelessWidget {
  final GameRoom room;
  const _ScoreSummary({required this.room});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Text(
          room.players.values
              .map((p) => '${p.name}: ${p.timeline.length}')
              .join('  •  '),
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _WinnerView extends StatelessWidget {
  final GameRoom room;
  const _WinnerView({required this.room});

  @override
  Widget build(BuildContext context) {
    final winner = room.winner;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 16),
            Text('${winner?.name ?? "Ingen"} vann!',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('${winner?.timeline.length ?? 0} kort i rätt ordning'),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .popUntil((route) => route.isFirst),
              child: const Text('Tillbaka till start'),
            ),
          ],
        ),
      ),
    );
  }
}
