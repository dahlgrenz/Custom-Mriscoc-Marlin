import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../game/game_controller.dart';
import '../../models/game_room.dart';
import '../../services/lan_server_service.dart';
import 'filter_screen.dart';
import 'game_screen.dart';

/// Vart QR-koden pekar: LAN (samma Wi-Fi) eller en publik Firebase Hosting-URL.
enum JoinMode { lan, hosting }

/// Väntrummet: visar rumskoden, en QR-kod att dela, och anslutna spelare.
/// Värdens telefon startar en LAN-webbserver så andra kan gå med via webben.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _starting = false;
  String? _serverUrl;
  String? _serverError;
  JoinMode _mode = JoinMode.lan;

  String get _hostingUrl => (dotenv.env['HOSTING_URL'] ?? '').trim();
  bool get _hostingConfigured => _hostingUrl.isNotEmpty;

  Future<void> _ensureServer() async {
    if (_starting || _serverUrl != null) return;
    _starting = true;
    try {
      final url = await context.read<LanServerService>().start();
      if (mounted) setState(() => _serverUrl = url);
    } catch (e) {
      if (mounted) setState(() => _serverError = '$e');
    } finally {
      _starting = false;
    }
  }

  String _modeLabel(GameMode m) => switch (m) {
        GameMode.year => 'Årtal',
        GameMode.classic => 'Klassisk',
        GameMode.timeline => 'Tidslinje',
      };

  List<int> _targetOptions(GameMode m) => switch (m) {
        GameMode.year => const [15, 25, 40],
        GameMode.classic => const [10, 15, 20],
        GameMode.timeline => const [5, 10, 15],
      };

  String _targetUnit(GameMode m) => switch (m) {
        GameMode.year => 'poäng',
        GameMode.classic => 'frågor',
        GameMode.timeline => 'kort',
      };

  Future<void> _setHandicap(BuildContext context, GameController controller,
      String playerId, String name, int current) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Handikapp för $name'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('Dra av minuspoäng för en riktigt duktig spelare.',
                style: TextStyle(fontSize: 12)),
          ),
          for (final v in const [0, 1, 2, 3, 5])
            RadioListTile<int>(
              value: v,
              groupValue: current,
              title: Text(v == 0 ? 'Inget handikapp' : '−$v poäng'),
              onChanged: (x) => Navigator.pop(context, x),
            ),
        ],
      ),
    );
    if (value != null) controller.setHandicap(playerId, value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final room = controller.room;

    // Värden startar LAN-servern bara när LAN-läget är valt.
    if (controller.isHost && _mode == JoinMode.lan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureServer());
    }

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

    // QR-mål beroende på valt läge.
    String? joinUrl;
    if (_mode == JoinMode.lan) {
      joinUrl = _serverUrl == null ? null : '$_serverUrl/?code=${room.code}';
    } else if (_hostingConfigured) {
      final base = _hostingUrl.replaceAll(RegExp(r'/+$'), '');
      joinUrl = '$base/?code=${room.code}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Väntrum'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Lämna',
            onPressed: () async {
              await controller.leaveGame();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
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
            if (room.playlistName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.queue_music, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Spellista: ${room.playlistName}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            if (controller.isHost)
              _ShareCard(
                joinUrl: joinUrl,
                error: _mode == JoinMode.lan ? _serverError : null,
                mode: _mode,
                hostingConfigured: _hostingConfigured,
                onModeChanged: (m) => setState(() => _mode = m),
              ),
            const SizedBox(height: 16),
            Text('Spelare (${players.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: players.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = players[i];
                  final isHostRow = p.id == room.hostId;
                  return ListTile(
                    leading: CircleAvatar(
                      child:
                          Text(p.avatar, style: const TextStyle(fontSize: 20)),
                    ),
                    title: Text(p.name),
                    subtitle: p.handicap > 0
                        ? Text('Handikapp: −${p.handicap} p',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))
                        : null,
                    trailing: isHostRow
                        ? const Chip(label: Text('Värd'))
                        : (controller.isHost
                            ? const Icon(Icons.tune, size: 18)
                            : null),
                    // Värden kan ge en spelare handikapp (minuspoäng).
                    onTap: controller.isHost
                        ? () => _setHandicap(context, controller, p.id, p.name,
                            p.handicap)
                        : null,
                  );
                },
              ),
            ),
            // Spelläge: värden väljer.
            Row(
              children: [
                const Icon(Icons.style, size: 18),
                const SizedBox(width: 8),
                Text('Läge:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 12),
                if (controller.isHost)
                  Expanded(
                    child: SegmentedButton<GameMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: GameMode.timeline, label: Text('Tidslinje')),
                        ButtonSegment(
                            value: GameMode.year, label: Text('Årtal')),
                        ButtonSegment(
                            value: GameMode.classic, label: Text('Klassisk')),
                      ],
                      selected: {room.mode},
                      onSelectionChanged: (s) => controller.setMode(s.first),
                    ),
                  )
                else
                  Text(_modeLabel(room.mode),
                      style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            // Vinstmål (kort i tidslinje, poäng i årtal, antal frågor i klassisk).
            Row(
              children: [
                const Icon(Icons.flag, size: 18),
                const SizedBox(width: 8),
                Text('Mål:', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 12),
                if (controller.isHost)
                  ..._targetOptions(room.mode).map((n) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('$n'),
                          selected: room.targetCards == n,
                          onSelected: (_) => controller.setTargetCards(n),
                        ),
                      ))
                else
                  Text('${room.targetCards} ${_targetUnit(room.mode)}',
                      style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 12),
            // Filter (värden): begränsa vilka låtar som ingår.
            if (controller.isHost) ...[
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider<GameController>.value(
                    value: controller,
                    child: FilterScreen(playlistId: room.playlistId),
                  ),
                )),
                icon: const Icon(Icons.filter_list),
                label: Text(controller.filter.isActive
                    ? 'Ändra filter'
                    : 'Filter (alla låtar)'),
              ),
              if (controller.filter.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(controller.filter.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
            ],
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

/// Kort som visar QR-koden (och en dela-knapp) till webbklienten.
/// Värden kan välja om QR:en pekar på LAN-adressen eller en Hosting-URL.
class _ShareCard extends StatelessWidget {
  final String? joinUrl;
  final String? error;
  final JoinMode mode;
  final bool hostingConfigured;
  final ValueChanged<JoinMode> onModeChanged;

  const _ShareCard({
    required this.joinUrl,
    required this.error,
    required this.mode,
    required this.hostingConfigured,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final desc = mode == JoinMode.lan
        ? 'Skanna QR-koden med en enhet på samma Wi-Fi.'
        : 'Skanna QR-koden — funkar var som helst (på distans).';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Låt andra gå med',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            // Välj vart QR:en pekar. Hosting visas bara om HOSTING_URL är satt.
            if (hostingConfigured)
              SegmentedButton<JoinMode>(
                segments: const [
                  ButtonSegment(
                      value: JoinMode.lan,
                      icon: Icon(Icons.wifi),
                      label: Text('Samma rum')),
                  ButtonSegment(
                      value: JoinMode.hosting,
                      icon: Icon(Icons.public),
                      label: Text('På distans')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => onModeChanged(s.first),
              )
            else
              const Text(
                '💡 Sätt HOSTING_URL i .env för att kunna dela en distanslänk.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            const SizedBox(height: 8),
            Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            if (error != null)
              Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))
            else if (joinUrl == null)
              const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()))
            else ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: joinUrl!,
                  version: QrVersions.auto,
                  size: 150,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(joinUrl!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => Share.share('Gå med i mitt musikquiz: $joinUrl'),
                icon: const Icon(Icons.share),
                label: const Text('Dela länk'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
