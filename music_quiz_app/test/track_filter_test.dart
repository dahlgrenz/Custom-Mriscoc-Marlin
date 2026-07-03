import 'package:flutter_test/flutter_test.dart';
import 'package:music_quiz/game/track_filter.dart';
import 'package:music_quiz/models/track.dart';

Track t({
  String id = 'x',
  String artist = 'A',
  String title = 'T',
  int year = 1990,
  List<String> genres = const [],
  int popularity = 0,
  List<String> tags = const [],
}) =>
    Track(
      id: id,
      uri: 'uri:$id',
      title: title,
      artist: artist,
      year: year,
      genres: genres,
      popularity: popularity,
      tags: tags,
    );

void main() {
  final tracks = [
    t(id: '1', artist: 'ABBA', title: 'Waterloo', year: 1974, genres: ['swedish pop'], popularity: 80, tags: ['eurovision', 'land=se']),
    t(id: '2', artist: 'Loreen', title: 'Euphoria', year: 2012, genres: ['pop'], popularity: 70, tags: ['melodifestivalen', 'land=se']),
    t(id: '3', artist: 'Nirvana', title: 'Come as You Are', year: 1991, genres: ['rock', 'grunge'], popularity: 60),
    t(id: '4', artist: 'Kent', title: 'Music Non Stop', year: 2002, genres: ['swedish rock'], popularity: 40),
  ];

  test('tomt filter släpper igenom allt', () {
    expect(const TrackFilter().apply(tracks).length, 4);
    expect(const TrackFilter().isActive, isFalse);
  });

  test('decennium', () {
    final r = const TrackFilter(decades: {1990}).apply(tracks);
    expect(r.map((e) => e.id), ['3']);
  });

  test('decennium (flera)', () {
    final r = const TrackFilter(decades: {1970, 2010}).apply(tracks);
    expect(r.map((e) => e.id).toSet(), {'1', '2'});
  });

  test('artistfritext (skiftlägesokänslig, delsträng)', () {
    expect(const TrackFilter(artistQuery: 'abba').apply(tracks).single.id, '1');
  });

  test('genre (någon matchar)', () {
    final r = const TrackFilter(genres: {'rock'}).apply(tracks);
    expect(r.single.id, '3');
  });

  test('popularitet minst', () {
    final r = const TrackFilter(minPopularity: 70).apply(tracks);
    expect(r.map((e) => e.id).toSet(), {'1', '2'});
  });

  test('taggar', () {
    expect(const TrackFilter(tags: {'melodifestivalen'}).apply(tracks).single.id, '2');
    expect(const TrackFilter(tags: {'land=se'}).apply(tracks).length, 2);
  });

  test('kombination (AND mellan dimensioner)', () {
    final r = const TrackFilter(tags: {'land=se'}, minPopularity: 75).apply(tracks);
    expect(r.single.id, '1');
  });
}
