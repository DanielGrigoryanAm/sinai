import 'package:sinai/api/api_client.dart';

/// Id of the signed-in user, as messages, reactions and members name it.
String? currentUserId() => ApiClient.instance.userId;
