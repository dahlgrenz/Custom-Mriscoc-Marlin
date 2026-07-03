import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../models/game_room.dart';
import '../../models/player.dart';
import '../../models/track.dart';

/// Huvudskärmen under spel: den spelande låten dras till rätt plats i din
/// tidslinje. Realtidssynk, animationer och offline-banner.
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
          _OfflineBanner(visible: !controller.isOnline),
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
                    currentTrack: round?.track,
                    onPlace: (pos) => controller.placeCurrentTrack(pos),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final bool visible;
  const _OfflineBanner({required this.visible});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 18),
                  const SizedBox(width: 8),
                  Text('Ingen anslutning — återansluter…',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer)),
                ],
              ),
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
          Text(
            myTurn ? 'Din tur — dra låten till rätt plats i tiden' : '$activeName spelar',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Kort som byter med en mjuk övergång när ny låt spelas.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _MysteryCard(
              key: ValueKey(track?.id ?? 'none'),
              track: track,
              draggable: myTurn,
            ),
          ),
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

/// Det dragbara "mysteriekortet" — årtalet är dolt (det är det man gissar).
class _MysteryCard extends StatelessWidget {
  final Track? track;
  final bool draggable;
  const _MysteryCard({super.key, required this.track, required this.draggable});

  @override
  Widget build(BuildContext context) {
    final card = _cardBody(context);
    if (track == null || !draggable) return card;

    return Draggable<Track>(
      data: track,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: _cardBody(context, dragging: true)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }

  Widget _cardBody(BuildContext context, {bool dragging = false}) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: dragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.help_outline, size: 36),
          const SizedBox(height: 8),
          Text(track?.title ?? '—',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          Text(track?.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final Player player;
  final bool canPlace;
  final Track? currentTrack;
  final void Function(int position) onPlace;

  const _Timeline({
    required this.player,
    required this.canPlace,
    required this.currentTrack,
    required this.onPlace,
  });

  @override
  Widget build(BuildContext context) {
    final timeline = player.timeline;
    final children = <Widget>[
      Text('Din tidslinje', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
    ];

    // [drop] kort [drop] kort … [drop]
    for (var i = 0; i <= timeline.length; i++) {
      children.add(_DropSlot(
        active: canPlace,
        onDropped: () => onPlace(i),
      ));
      if (i < timeline.length) {
        children.add(_CardTile(key: ValueKey(timeline[i].id), track: timeline[i]));
      }
    }

    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

/// En släppzon mellan två kort. Highlightas när ett kort dras över.
class _DropSlot extends StatelessWidget {
  final bool active;
  final VoidCallback onDropped;
  const _DropSlot({required this.active, required this.onDropped});

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox(height: 8);

    return DragTarget<Track>(
      onAcceptWithDetails: (_) => onDropped(),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 4),
          height: hovering ? 48 : 28,
          decoration: BoxDecoration(
            color: hovering
                ? Theme.of(context).colorScheme.primary.withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              style: BorderStyle.solid,
              width: hovering ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              hovering ? 'Släpp här' : 'Släppzon',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardTile extends StatelessWidget {
  final Track track;
  const _CardTile({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    // Liten "pop in"-animation när kortet läggs till.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
      ),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Text('${track.year}')),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class _ScoreSummary extends StatelessWidget {
  final GameRoom room;
  const _ScoreSummary({required this.room});

  @override
  Widget build(BuildContext context) {
    final text = room.players.values
        .map((p) => '${p.name}: ${p.timeline.length}')
        .join('  •  ');
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        // Mjuk övergång när poängen ändras.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(text,
              key: ValueKey(text),
              style: Theme.of(context).textTheme.labelMedium),
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
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Tillbaka till start'),
            ),
          ],
        ),
      ),
    );
  }
}
