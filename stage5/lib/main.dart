import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/firebase_options.dart';

Future<void> main() async {
  await initializeMercedesApp();
  runApp(const ProviderScope(child: MercedesApp()));
}

Future<void> initializeMercedesApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (browserSmokeConfig.emulatorsEnabled) {
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    }
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
  }
}
