import 'package:flutter_test/flutter_test.dart';
import 'package:music_quiz/game/scoring.dart';
import 'package:music_quiz/models/track.dart';

Track t(int year) =>
    Track(id: '$year', uri: 'uri:$year', title: 'T$year', artist: 'A', year: year);

void main() {
  group('Scoring.isCorrectPlacement', () {
    final timeline = [t(1980), t(1995), t(2010)];

    test('rätt: mellan två kort', () {
      expect(Scoring.isCorrectPlacement(timeline, t(2000), 2), isTrue);
    });

    test('rätt: före allt', () {
      expect(Scoring.isCorrectPlacement(timeline, t(1975), 0), isTrue);
    });

    test('rätt: efter allt', () {
      expect(Scoring.isCorrectPlacement(timeline, t(2020), 3), isTrue);
    });

    test('fel: för sent i tidslinjen', () {
      expect(Scoring.isCorrectPlacement(timeline, t(2000), 1), isFalse);
    });

    test('fel: utanför gränserna', () {
      expect(Scoring.isCorrectPlacement(timeline, t(2000), 9), isFalse);
    });

    test('lika år på gränsen accepteras', () {
      expect(Scoring.isCorrectPlacement(timeline, t(1995), 1), isTrue);
      expect(Scoring.isCorrectPlacement(timeline, t(1995), 2), isTrue);
    });
  });

  group('Scoring.insertSorted', () {
    test('sätter in i kronologisk ordning', () {
      final result = Scoring.insertSorted([t(1980), t(2010)], t(1995));
      expect(result.map((e) => e.year).toList(), [1980, 1995, 2010]);
    });
  });
}
