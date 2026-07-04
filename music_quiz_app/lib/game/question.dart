import 'dart:math';

import '../models/track.dart';

/// En flervalsfråga i klassiskt läge.
class QuizQuestion {
  /// "song" | "artist" | "year".
  final String type;
  final String prompt;
  final List<String> options;
  final int correctIndex;

  const QuizQuestion({
    required this.type,
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });
}

/// Skapar frågor ur den nu spelande låten + resten av leken (för fel-alternativ).
class QuestionGenerator {
  static const _types = ['song', 'artist', 'year'];
  static const _prompts = {
    'song': 'Vilken låt?',
    'artist': 'Vilken artist?',
    'year': 'Vilket år?',
  };

  /// [rnd] injiceras för testbarhet. [forceType] kan låsa frågetypen.
  static QuizQuestion generate(
    Track track,
    List<Track> deck,
    Random rnd, {
    String? forceType,
  }) {
    final type = forceType ?? _types[rnd.nextInt(_types.length)];

    String valueOf(Track t) => switch (type) {
          'artist' => t.artist,
          'year' => '${t.year}',
          _ => t.title,
        };

    final correct = valueOf(track);
    final pool = deck.map(valueOf).toSet().toList()..remove(correct);
    pool.shuffle(rnd);
    final distractors = pool.take(3).toList();

    final options = [correct, ...distractors]..shuffle(rnd);
    return QuizQuestion(
      type: type,
      prompt: _prompts[type]!,
      options: options,
      correctIndex: options.indexOf(correct),
    );
  }
}
