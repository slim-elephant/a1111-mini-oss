import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// False when the build has no Firebase config (e.g. an open-source checkout
/// without GoogleService-Info.plist). Accounts, analytics and feature
/// requests are hidden then; generation works the same.
bool get firebaseReady => _ready;
bool _ready = false;

Future<void> initFirebase() async {
  try {
    await Firebase.initializeApp();
    _ready = true;
  } catch (e) {
    debugPrint('Firebase not configured, running without it: $e');
  }
}
