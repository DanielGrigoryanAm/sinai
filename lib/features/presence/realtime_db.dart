import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// The Realtime Database holding short-lived state: who is online and who
/// is typing. It is used for this rather than Firestore because it can
/// clear that state by itself when an app disconnects (onDisconnect).
abstract final class RealtimeDb {
  /// URL of the project's Realtime Database, shown at the top of its Data
  /// tab in the Firebase console.
  static const url =
      'https://sinai-2c9b2-default-rtdb.europe-west1.firebasedatabase.app';

  static FirebaseDatabase get instance =>
      FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: url);

  /// `presence/{uid}`: {online, lastSeen}.
  static DatabaseReference presence(String uid) =>
      instance.ref('presence/$uid');

  /// `typing/{chatId}/{uid}`: {name, at}.
  static DatabaseReference typing(String chatId) =>
      instance.ref('typing/$chatId');
}
