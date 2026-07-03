import 'package:flutter/material.dart';

import '../../models/game_room.dart';
import '../../models/player.dart';

/// Interaktiv leaderboard som visar spelarna rankade efter poäng/kort.
/// Uppdateras automatiskt eftersom rummet strömmas i realtid.
class Leaderboard extends StatelessWidget {
  final GameRoom room;
  final String? myId;

  /// Kompakt = en rad högst upp i spelet; annars full lista (t.ex. resultat).
  final bool compact;

  const Leaderboard({
    super.key,
    required this.room,
    this.myId,
    this.compact = false,
  });

  static const _medals = ['🥇', '🥈', '🥉'];

  String _unit(int value) =>
      room.mode == GameMode.year ? '$value p' : '$value kort';

  @override
  Widget build(BuildContext context) {
    final ranking = room.ranking;
    if (compact) return _compact(context, ranking);
    return _full(context, ranking);
  }

  Widget _compact(BuildContext context, List<Player> ranking) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < ranking.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Chip(
                visualDensity: VisualDensity.compact,
                avatar: Text(i < 3 ? _medals[i] : '${ranking[i].avatar}',
                    style: const TextStyle(fontSize: 16)),
                label: Text('${ranking[i].name} · ${_unit(room.rankValue(ranking[i]))}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _full(BuildContext context, List<Player> ranking) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < ranking.length; i++)
          _Row(
            rank: i,
            player: ranking[i],
            value: _unit(room.rankValue(ranking[i])),
            isMe: ranking[i].id == myId,
            medal: i < 3 ? _medals[i] : null,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final int rank;
  final Player player;
  final String value;
  final bool isMe;
  final String? medal;

  const _Row({
    required this.rank,
    required this.player,
    required this.value,
    required this.isMe,
    required this.medal,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Animerad rad så att omflyttningar efter varje omgång känns levande.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rank == 0
            ? scheme.primaryContainer
            : isMe
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: isMe ? Border.all(color: scheme.primary, width: 1.5) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(medal ?? '${rank + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(player.avatar, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              player.name + (isMe ? ' (du)' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: rank == 0 ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
