// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [ChatReadyScreen]
class ChatReadyRoute extends PageRouteInfo<ChatReadyRouteArgs> {
  ChatReadyRoute({
    Key? key,
    required String chatCode,
    required String chatName,
    List<PageRouteInfo>? children,
  }) : super(
          ChatReadyRoute.name,
          args: ChatReadyRouteArgs(
            key: key,
            chatCode: chatCode,
            chatName: chatName,
          ),
          initialChildren: children,
        );

  static const String name = 'ChatReadyRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatReadyRouteArgs>();
      return ChatReadyScreen(
        key: args.key,
        chatCode: args.chatCode,
        chatName: args.chatName,
      );
    },
  );
}

class ChatReadyRouteArgs {
  const ChatReadyRouteArgs({
    this.key,
    required this.chatCode,
    required this.chatName,
  });

  final Key? key;

  final String chatCode;

  final String chatName;

  @override
  String toString() {
    return 'ChatReadyRouteArgs{key: $key, chatCode: $chatCode, chatName: $chatName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatReadyRouteArgs) return false;
    return key == other.key &&
        chatCode == other.chatCode &&
        chatName == other.chatName;
  }

  @override
  int get hashCode => key.hashCode ^ chatCode.hashCode ^ chatName.hashCode;
}

/// generated route for
/// [ChatScreen]
class ChatRoute extends PageRouteInfo<ChatRouteArgs> {
  ChatRoute({
    Key? key,
    required String chatCode,
    String? chatName,
    List<PageRouteInfo>? children,
  }) : super(
          ChatRoute.name,
          args: ChatRouteArgs(key: key, chatCode: chatCode, chatName: chatName),
          initialChildren: children,
        );

  static const String name = 'ChatRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatRouteArgs>();
      return ChatScreen(
        key: args.key,
        chatCode: args.chatCode,
        chatName: args.chatName,
      );
    },
  );
}

class ChatRouteArgs {
  const ChatRouteArgs({this.key, required this.chatCode, this.chatName});

  final Key? key;

  final String chatCode;

  final String? chatName;

  @override
  String toString() {
    return 'ChatRouteArgs{key: $key, chatCode: $chatCode, chatName: $chatName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatRouteArgs) return false;
    return key == other.key &&
        chatCode == other.chatCode &&
        chatName == other.chatName;
  }

  @override
  int get hashCode => key.hashCode ^ chatCode.hashCode ^ chatName.hashCode;
}

/// generated route for
/// [ChatsScreen]
class ChatsRoute extends PageRouteInfo<void> {
  const ChatsRoute({List<PageRouteInfo>? children})
      : super(ChatsRoute.name, initialChildren: children);

  static const String name = 'ChatsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ChatsScreen();
    },
  );
}

/// generated route for
/// [CreateChatScreen]
class CreateChatRoute extends PageRouteInfo<void> {
  const CreateChatRoute({List<PageRouteInfo>? children})
      : super(CreateChatRoute.name, initialChildren: children);

  static const String name = 'CreateChatRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const CreateChatScreen();
    },
  );
}

/// generated route for
/// [OnboardingScreen]
class OnboardingRoute extends PageRouteInfo<void> {
  const OnboardingRoute({List<PageRouteInfo>? children})
      : super(OnboardingRoute.name, initialChildren: children);

  static const String name = 'OnboardingRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const OnboardingScreen();
    },
  );
}

/// generated route for
/// [PhoneScreen]
class PhoneRoute extends PageRouteInfo<PhoneRouteArgs> {
  PhoneRoute({Key? key, bool restore = false, List<PageRouteInfo>? children})
      : super(
          PhoneRoute.name,
          args: PhoneRouteArgs(key: key, restore: restore),
          initialChildren: children,
        );

  static const String name = 'PhoneRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<PhoneRouteArgs>(
        orElse: () => const PhoneRouteArgs(),
      );
      return PhoneScreen(key: args.key, restore: args.restore);
    },
  );
}

class PhoneRouteArgs {
  const PhoneRouteArgs({this.key, this.restore = false});

  final Key? key;

  final bool restore;

  @override
  String toString() {
    return 'PhoneRouteArgs{key: $key, restore: $restore}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PhoneRouteArgs) return false;
    return key == other.key && restore == other.restore;
  }

  @override
  int get hashCode => key.hashCode ^ restore.hashCode;
}

/// generated route for
/// [ProfileScreen]
class ProfileRoute extends PageRouteInfo<void> {
  const ProfileRoute({List<PageRouteInfo>? children})
      : super(ProfileRoute.name, initialChildren: children);

  static const String name = 'ProfileRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ProfileScreen();
    },
  );
}

/// generated route for
/// [StartChatScreen]
class StartChatRoute extends PageRouteInfo<void> {
  const StartChatRoute({List<PageRouteInfo>? children})
      : super(StartChatRoute.name, initialChildren: children);

  static const String name = 'StartChatRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const StartChatScreen();
    },
  );
}
