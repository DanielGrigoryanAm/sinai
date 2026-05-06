// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [ChatScreen]
class ChatRoute extends PageRouteInfo<ChatRouteArgs> {
  ChatRoute({Key? key, required String chatCode, List<PageRouteInfo>? children})
      : super(
          ChatRoute.name,
          args: ChatRouteArgs(key: key, chatCode: chatCode),
          initialChildren: children,
        );

  static const String name = 'ChatRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ChatRouteArgs>();
      return ChatScreen(key: args.key, chatCode: args.chatCode);
    },
  );
}

class ChatRouteArgs {
  const ChatRouteArgs({this.key, required this.chatCode});

  final Key? key;

  final String chatCode;

  @override
  String toString() {
    return 'ChatRouteArgs{key: $key, chatCode: $chatCode}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ChatRouteArgs) return false;
    return key == other.key && chatCode == other.chatCode;
  }

  @override
  int get hashCode => key.hashCode ^ chatCode.hashCode;
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
