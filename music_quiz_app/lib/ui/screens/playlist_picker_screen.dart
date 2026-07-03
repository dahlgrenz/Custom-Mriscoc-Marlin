import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_exception.dart';
import '../../models/playlist_info.dart';
import '../../services/music/music_source.dart';

/// Låter värden välja vilken spellista spelet ska använda.
/// Poppar tillbaka den valda [PlaylistInfo] (eller null om man backar).
class PlaylistPickerScreen extends StatefulWidget {
  const PlaylistPickerScreen({super.key});

  @override
  State<PlaylistPickerScreen> createState() => _PlaylistPickerScreenState();
}

class _PlaylistPickerScreenState extends State<PlaylistPickerScreen> {
  late Future<List<PlaylistInfo>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context.read<MusicSource>().fetchPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Välj spellista')),
      body: FutureBuilder<List<PlaylistInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorRetry(
              message: AppException.from(snapshot.error!).message,
              onRetry: () => setState(_load),
            );
          }
          final playlists = snapshot.data ?? [];
          if (playlists.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Inga spellistor hittades på ditt konto. Skapa en i Spotify '
                  'och kom tillbaka.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = playlists[i];
              return ListTile(
                leading: p.imageUrl == null
                    ? const CircleAvatar(child: Icon(Icons.queue_music))
                    : CircleAvatar(backgroundImage: NetworkImage(p.imageUrl!)),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${p.trackCount} låtar'
                  '${p.ownerName.isEmpty ? '' : ' • ${p.ownerName}'}',
                ),
                trailing: p.trackCount < 10
                    ? const Tooltip(
                        message: 'Kort spellista — minst ~10 låtar rekommenderas',
                        child: Icon(Icons.warning_amber, size: 18),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pop(p),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Försök igen')),
          ],
        ),
      ),
    );
  }
}
