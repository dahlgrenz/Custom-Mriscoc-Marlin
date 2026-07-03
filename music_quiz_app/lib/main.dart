import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
// Genereras lokalt av `flutterfire configure` (se README).
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Läs in Spotify-nycklar från .env.
  await dotenv.load(fileName: '.env');

  // Starta Firebase och logga in anonymt (ger varje spelare ett stabilt uid).
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.signInAnonymously();

  runApp(const MusicQuizApp());
}
