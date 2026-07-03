import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../models/game_room.dart';
import '../../models/player.dart';
import '../../models/track.dart';
import '../widgets/leaderboard.dart';

/// Huvudskärmen under spel. Två lägen:
///  - Tidslinje: dra låten till rätt plats.
///  - Årtal: gissa utgivningsåret (poäng 5/3/1).
/// En interaktiv leaderboard visar vem som leder och uppdateras varje omgång.
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
      return _WinnerView(room: room, myId: controller.myPlayerId);
    }

    final me = controller.me;
    final round = room.currentRound;
    final isYear = room.mode == GameMode.year;

    // Fel + resultat-återkoppling som SnackBars.
    final error = controller.lastError;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        controller.clearError();
      });
    }
    final feedback = controller.feedback;
    if (feedback != null) {
      final good = controller.feedbackGood;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(feedback),
          backgroundColor: good
              ? Colors.green.shade700
              : Theme.of(context).colorScheme.error,
        ));
        controller.clearFeedback();
      });
    }

    final goal = isYear
        ? 'Först till ${room.targetCards} poäng'
        : 'Först till ${room.targetCards} kort';

    return Scaffold(
      appBar: AppBar(
        title: Text(goal),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Ställning',
            onPressed: () => _showLeaderboard(context, room, controller.myPlayerId),
          ),
        ],
      ),
      body: Column(
        children: [
          _OfflineBanner(visible: !controller.isOnline),
          // Interaktiv ställning högst upp — uppdateras efter varje omgång.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Leaderboard(
                room: room, myId: controller.myPlayerId, compact: true),
          ),
          _NowPlaying(
            track: round?.track,
            header: _header(controller),
            isStealPhase: controller.isStealPhase,
            draggable: controller.canAct && !isYear,
            isHost: controller.isHost,
            isPaused: controller.isPaused,
            onToggle: controller.togglePlayback,
          ),
          const Divider(height: 1),
          Expanded(
            child: me == null
                ? const Center(child: Text('Laddar…'))
                : isYear
                    ? _YearMode(
                        player: me,
                        canAct: controller.canAct,
                        onGuess: controller.submitYearGuess,
                      )
                    : _Timeline(
                        player: me,
                        canPlace: controller.canAct,
                        onPlace: controller.placeCurrentTrack,
                      ),
          ),
        ],
      ),
    );
  }

  String _header(GameController c) {
    final isYear = c.mode == GameMode.year;
    if (c.canAct && c.isStealPhase) {
      return 'STEAL! 😎 Placera låten rätt och stjäl kortet';
    }
    if (c.canAct) {
      return isYear
          ? 'Din tur — gissa utgivningsåret'
          : 'Din tur — dra låten till rätt plats i tiden';
    }
    if (c.isStealPhase) return '${c.actorName} försöker stjäla kortet…';
    return isYear ? '${c.actorName} gissar årtalet' : '${c.actorName} spelar';
  }

  void _showLeaderboard(BuildContext context, GameRoom room, String myId) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ställning', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Leaderboard(room: room, myId: myId),
          ],
        ),
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
                          color:
                              Theme.of(context).colorScheme.onErrorContainer)),
                ],
              ),
            ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final Track? track;
  final String header;
  final bool isStealPhase;
  final bool draggable;
  final bool isHost;
  final bool isPaused;
  final VoidCallback onToggle;

  const _NowPlaying({
    required this.track,
    required this.header,
    required this.isStealPhase,
    required this.draggable,
    required this.isHost,
    required this.isPaused,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      color: isStealPhase
          ? Theme.of(context).colorScheme.tertiaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Text(header,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _MysteryCard(
              key: ValueKey(track?.id ?? 'none'),
              track: track,
              draggable: draggable,
            ),
          ),
          if (isHost) ...[
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
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
          const Icon(Icons.help_outline, size: 32),
          const SizedBox(height: 6),
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

// ---------- Tidslinjeläge ----------

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
    final children = <Widget>[
      Text('Din tidslinje', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
    ];
    for (var i = 0; i <= timeline.length; i++) {
      children.add(_DropSlot(active: canPlace, onDropped: () => onPlace(i)));
      if (i < timeline.length) {
        children.add(
            _CardTile(key: ValueKey(timeline[i].id), track: timeline[i]));
      }
    }
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }
}

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
              width: hovering ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(hovering ? 'Släpp här' : 'Släppzon',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary, fontSize: 12)),
          ),
        );
      },
    );
  }
}

// ---------- Årtalsläge ----------

class _YearMode extends StatelessWidget {
  final Player player;
  final bool canAct;
  final void Function(int year) onGuess;

  const _YearMode({
    required this.player,
    required this.canAct,
    required this.onGuess,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (canAct) _YearPicker(onGuess: onGuess),
        Expanded(child: _MyBoard(player: player)),
      ],
    );
  }
}

class _YearPicker extends StatefulWidget {
  final void Function(int year) onGuess;
  const _YearPicker({required this.onGuess});

  @override
  State<_YearPicker> createState() => _YearPickerState();
}

class _YearPickerState extends State<_YearPicker> {
  static final int _maxYear = DateTime.now().year;
  static const int _minYear = 1950;
  double _year = ((1950 + 2010) / 2).roundToDouble();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('${_year.round()}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
            Slider(
              value: _year.clamp(_minYear.toDouble(), _maxYear.toDouble()),
              min: _minYear.toDouble(),
              max: _maxYear.toDouble(),
              divisions: _maxYear - _minYear,
              label: '${_year.round()}',
              onChanged: (v) => setState(() => _year = v),
            ),
            const SizedBox(height: 4),
            const Text('5 p för exakt • 3 p för 1–2 år • 1 p för 3–5 år',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => widget.onGuess(_year.round()),
              icon: const Icon(Icons.check),
              label: const Text('Gissa'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only lista över spelarens insamlade låtar (med årtal).
class _MyBoard extends StatelessWidget {
  final Player player;
  const _MyBoard({required this.player});

  @override
  Widget build(BuildContext context) {
    final timeline = player.timeline;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Dina låtar (${timeline.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (timeline.isEmpty)
          const Text('Inga låtar än.')
        else
          for (final t in timeline) _CardTile(key: ValueKey(t.id), track: t),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final Track track;
  const _CardTile({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
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

class _WinnerView extends StatelessWidget {
  final GameRoom room;
  final String myId;
  const _WinnerView({required this.room, required this.myId});

  @override
  Widget build(BuildContext context) {
    final winner = room.winner;
    return Scaffold(
      appBar: AppBar(title: const Text('Resultat'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Center(child: Text('🏆', style: TextStyle(fontSize: 72))),
          Center(
            child: Text('${winner?.name ?? "Ingen"} vann!',
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: 24),
          Text('Slutställning', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Leaderboard(room: room, myId: myId),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Tillbaka till start'),
          ),
        ],
      ),
    );
  }
}
