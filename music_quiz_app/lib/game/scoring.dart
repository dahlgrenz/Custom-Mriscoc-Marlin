import '../models/track.dart';

/// Ren spellogik — inga beroenden, lätt att enhetstesta.
class Scoring {
  /// Kontrollerar om [candidate] placerad på [position] i en tidslinje sorterad
  /// efter år (stigande) är kronologiskt korrekt.
  ///
  /// [position] är index där kortet skulle sättas in: 0 = före allt,
  /// timeline.length = efter allt. Placeringen är rätt om årtalet är >= året
  /// för kortet före positionen och <= året för kortet efter positionen.
  static bool isCorrectPlacement(
    List<Track> timeline,
    Track candidate,
    int position,
  ) {
    if (position < 0 || position > timeline.length) return false;
    final before = position > 0 ? timeline[position - 1].year : null;
    final after = position < timeline.length ? timeline[position].year : null;
    if (before != null && candidate.year < before) return false;
    if (after != null && candidate.year > after) return false;
    return true;
  }

  /// Returnerar en ny tidslinje med [candidate] insatt på rätt kronologisk plats.
  static List<Track> insertSorted(List<Track> timeline, Track candidate) {
    final result = List<Track>.from(timeline);
    var i = 0;
    while (i < result.length && result[i].year <= candidate.year) {
      i++;
    }
    result.insert(i, candidate);
    return result;
  }
}
