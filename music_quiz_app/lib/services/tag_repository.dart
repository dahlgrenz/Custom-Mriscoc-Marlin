import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';

/// En rad ur en taggfil: artist + titel (normaliserade för matchning) + taggar.
class _TagEntry {
  final String artist;
  final String title;
  final List<String> tags;
  const _TagEntry(this.artist, this.title, this.tags);
}

/// Läser kuraterade taggfiler (tag_data/*.csv) och hänger taggarna på de låtar
/// som hämtats från Spotify. Se tag_data/README.md för format.
class TagRepository {
  final List<_TagEntry> _entries = [];
  // Index: normaliserad titel → rader (snabb uppslagning per låt).
  final Map<String, List<_TagEntry>> _byTitle = {};
  bool _loaded = false;

  bool get hasTags => _entries.isNotEmpty;

  /// Läser in alla tag_data/*.csv (ej *.example.csv). Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final files = manifest.listAssets().where((a) =>
          a.startsWith('tag_data/') &&
          a.endsWith('.csv') &&
          !a.contains('.example.'));
      for (final file in files) {
        final content = await rootBundle.loadString(file);
        _parse(content);
      }
      for (final e in _entries) {
        _byTitle.putIfAbsent(e.title, () => []).add(e);
      }
      debugPrint('Taggar inlästa: ${_entries.length} rader');
    } catch (e) {
      debugPrint('Kunde inte läsa taggfiler: $e');
    }
  }

  void _parse(String content) {
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(';');
      if (parts.length < 3) continue;
      final artist = parts[0].trim();
      final title = parts[1].trim();
      if (artist.toLowerCase() == 'artist') continue; // rubrikrad
      final tags = parts[2]
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (artist.isEmpty || title.isEmpty || tags.isEmpty) continue;
      _entries.add(_TagEntry(_norm(artist), _norm(title), tags));
    }
  }

  /// Returnerar låtarna med matchande taggar påhängda (oförändrade om ingen träff).
  List<Track> applyTo(List<Track> tracks) {
    if (_entries.isEmpty) return tracks;
    return [
      for (final t in tracks) _withTags(t),
    ];
  }

  Track _withTags(Track t) {
    final candidates = _byTitle[_norm(t.title)];
    if (candidates == null) return t;
    final artist = _norm(t.artist);
    final matched = <String>{};
    for (final e in candidates) {
      // Artistmatchning är "förlåtande": räcker att namnet finns med.
      if (artist.contains(e.artist) || e.artist.contains(artist)) {
        matched.addAll(e.tags);
      }
    }
    return matched.isEmpty ? t : t.copyWith(tags: matched.toList());
  }

  /// Normaliserar text för matchning: gemener, tar bort "(...)", "feat. …" och
  /// skiljetecken, och slår ihop mellanslag.
  static String _norm(String s) {
    var out = s.toLowerCase();
    out = out.replaceAll(RegExp(r'\(.*?\)'), ' '); // (Radio Edit) etc.
    out = out.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*'), ' ');
    out = out.replaceAll(RegExp(r'[^a-z0-9åäöéèü ]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }
}
