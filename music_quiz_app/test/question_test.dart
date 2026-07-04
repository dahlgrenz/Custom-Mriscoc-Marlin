import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_quiz/game/question.dart';
import 'package:music_quiz/models/track.dart';

Track t(String id, String artist, String title, int year) =>
    Track(id: id, uri: 'uri:$id', title: title, artist: artist, year: year);

void main() {
  final deck = [
    t('1', 'ABBA', 'Waterloo', 1974),
    t('2', 'Queen', 'Bohemian Rhapsody', 1975),
    t('3', 'Nirvana', 'Come as You Are', 1991),
    t('4', 'Kent', 'Utan dina andetag', 2000),
  ];

  test('artist-fråga: rätt svar finns bland alternativen', () {
    final q = QuestionGenerator.generate(deck[0], deck, Random(1), forceType: 'artist');
    expect(q.type, 'artist');
    expect(q.options[q.correctIndex], 'ABBA');
    expect(q.options.length, 4);
    expect(q.options.toSet().length, q.options.length); // inga dubbletter
  });

  test('år-fråga: rätt index pekar på rätt år', () {
    final q = QuestionGenerator.generate(deck[2], deck, Random(2), forceType: 'year');
    expect(q.options[q.correctIndex], '1991');
  });

  test('låt-fråga: rätt titel', () {
    final q = QuestionGenerator.generate(deck[1], deck, Random(3), forceType: 'song');
    expect(q.options[q.correctIndex], 'Bohemian Rhapsody');
  });

  test('färre alternativ när leken är liten', () {
    final small = [t('a', 'A', 'Song A', 1990), t('b', 'B', 'Song B', 1991)];
    final q = QuestionGenerator.generate(small[0], small, Random(4), forceType: 'song');
    expect(q.options.length, 2);
    expect(q.options[q.correctIndex], 'Song A');
  });
}
