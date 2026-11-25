import 'package:firebase_auth/firebase_auth.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';

/// Id of the signed-in user as messages, reactions and members name them:
/// the backend's id once the app runs on it, the Firebase uid before.
String? currentUserId() => ApiConfig.useBackend
    ? ApiClient.instance.userId
    : FirebaseAuth.instance.currentUser?.uid;
