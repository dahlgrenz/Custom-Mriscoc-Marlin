import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/game_controller.dart';
import '../../game/track_filter.dart';
import '../../models/track.dart';

/// Låter värden begränsa vilka låtar som ingår (decennium, artist, genre,
/// popularitet, kuraterade taggar) med en live-räknare för hur många matchar.
class FilterScreen extends StatefulWidget {
  final String playlistId;
  const FilterScreen({super.key, required this.playlistId});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late Set<int> _decades;
  late Set<String> _genres;
  late Set<String> _tags;
  late String _artist;
  late int _minPop;

  @override
  void initState() {
    super.initState();
    final f = context.read<GameController>().filter;
    _decades = {...f.decades};
    _genres = {...f.genres};
    _tags = {...f.tags};
    _artist = f.artistQuery;
    _minPop = f.minPopularity;
    // Ladda låtarna för att kunna visa tillgängliga val + räkna träffar.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<GameController>().loadTracksForFilter(widget.playlistId));
  }

  TrackFilter get _current => TrackFilter(
        decades: _decades,
        genres: _genres,
        tags: _tags,
        artistQuery: _artist,
        minPopularity: _minPop,
      );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GameController>();
    final tracks = controller.allTracks;
    final loading = controller.loadingTracks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filter'),
        actions: [
          TextButton(
            onPressed: _hasAny
                ? () => setState(() {
                      _decades = {};
                      _genres = {};
                      _tags = {};
                      _artist = '';
                      _minPop = 0;
                    })
                : null,
            child: const Text('Rensa'),
          ),
        ],
      ),
      body: loading && tracks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : tracks.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Kunde inte ladda låtarna. Gå tillbaka och försök igen.',
                        textAlign: TextAlign.center),
                  ),
                )
              : _buildForm(context, tracks),
      bottomNavigationBar: (loading && tracks.isEmpty)
          ? null
          : _ApplyBar(
              matching: _current.apply(tracks).length,
              total: tracks.length,
              onApply: () {
                controller.setFilter(_current);
                Navigator.of(context).pop();
              },
            ),
    );
  }

  bool get _hasAny =>
      _decades.isNotEmpty ||
      _genres.isNotEmpty ||
      _tags.isNotEmpty ||
      _artist.isNotEmpty ||
      _minPop > 0;

  Widget _buildForm(BuildContext context, List<Track> tracks) {
    // Tillgängliga val härledda ur de laddade låtarna.
    final decades = <int>{};
    final genreCount = <String, int>{};
    final tagSet = <String>{};
    for (final t in tracks) {
      decades.add(t.decade);
      for (final g in t.genres) {
        genreCount[g] = (genreCount[g] ?? 0) + 1;
      }
      tagSet.addAll(t.tags);
    }
    final decadeList = decades.toList()..sort();
    // Vanligaste genrerna först, max 30 för att hålla listan hanterbar.
    final genreList = genreCount.keys.toList()
      ..sort((a, b) => genreCount[b]!.compareTo(genreCount[a]!));
    final topGenres = genreList.take(30).toList();
    final tagList = tagSet.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Årtionde'),
        Wrap(
          spacing: 8,
          children: [
            for (final d in decadeList)
              FilterChip(
                label: Text('$d-tal'),
                selected: _decades.contains(d),
                onSelected: (v) => setState(() =>
                    v ? _decades.add(d) : _decades.remove(d)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _section('Artist'),
        TextFormField(
          initialValue: _artist,
          decoration: const InputDecoration(
            hintText: 't.ex. abba',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _artist = v),
        ),
        const SizedBox(height: 16),
        _section('Popularitet (Spotify)'),
        Text(_minPop == 0 ? 'Alla' : 'Minst $_minPop / 100'),
        Slider(
          value: _minPop.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: _minPop == 0 ? 'Alla' : '$_minPop',
          onChanged: (v) => setState(() => _minPop = v.round()),
        ),
        if (topGenres.isNotEmpty) ...[
          const SizedBox(height: 8),
          _section('Genre'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final g in topGenres)
                FilterChip(
                  label: Text(g),
                  selected: _genres.contains(g),
                  onSelected: (v) =>
                      setState(() => v ? _genres.add(g) : _genres.remove(g)),
                ),
            ],
          ),
        ],
        if (tagList.isNotEmpty) ...[
          const SizedBox(height: 16),
          _section('Egna taggar'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in tagList)
                FilterChip(
                  label: Text(tag),
                  selected: _tags.contains(tag),
                  onSelected: (v) =>
                      setState(() => v ? _tags.add(tag) : _tags.remove(tag)),
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            'Inga egna taggar hittades. Lägg till tag_data/tags.csv för filter som '
            'Melodifestivalen, land eller placering (se tag_data/README.md).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}

class _ApplyBar extends StatelessWidget {
  final int matching;
  final int total;
  final VoidCallback onApply;
  const _ApplyBar(
      {required this.matching, required this.total, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final tooFew = matching < 4;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$matching av $total låtar matchar',
                style: TextStyle(
                    color: tooFew ? Theme.of(context).colorScheme.error : null)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: tooFew ? null : onApply,
              child: Text(tooFew ? 'För få låtar' : 'Använd filter'),
            ),
          ],
        ),
      ),
    );
  }
}
