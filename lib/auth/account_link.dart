import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/common/onboarding_prefs.dart';
import 'package:sinai/features/chat/quick_reactions_store.dart';
import 'package:sinai/notifications/notification_service.dart';
import 'package:sinai/router/app_router.dart';

/// What adding a way of signing in ended with.
enum LinkOutcome {
  /// Added to this account; it keeps its chats and name.
  linked,

  /// It belonged to another account, and the app moved to that one.
  switched,

  /// The user changed their mind.
  cancelled,
}

/// Adds [credential] to the current account. When it already belongs to
/// another account, offers to sign in to that one instead ([restore]: on a
/// fresh install, without asking) and replaces the navigation.
///
/// Throws [PhoneAuthFailure] with a readable message.
Future<LinkOutcome> linkOrSwitch(
  BuildContext context,
  AuthCredential credential, {
  required bool restore,
  required String what,
}) async {
  final auth = AuthRepository();
  try {
    await auth.link(credential);
    return LinkOutcome.linked;
  } on CredentialInUse catch (e) {
    if (!context.mounted) return LinkOutcome.cancelled;
    final confirmed = restore ||
        await showConfirmDialog(
          context,
          title: 'Switch account?',
          message: 'This $what already belongs to another Sinai account. '
              'Signing in to it replaces your current account on this '
              'phone, and its chats will no longer be available here.',
          confirmLabel: 'Sign in',
        );
    if (!confirmed || !context.mounted) return LinkOutcome.cancelled;
    await _switchAccount(context, e.credential);
    return LinkOutcome.switched;
  }
}

Future<void> _switchAccount(
  BuildContext context,
  AuthCredential credential,
) async {
  final auth = AuthRepository();
  try {
    // This phone's notifications belong to the account being left.
    await NotificationService.instance.removeTokenFromCurrentUser();
    await auth.signIn(credential);
    // The backend session follows the Firebase account.
    await AuthApi.instance.switchToFirebaseAccount();
    await NotificationService.instance.addTokenToCurrentUser();
    QuickReactionsStore.instance.start();
  } on PhoneAuthFailure {
    // Put this phone's notifications back on the current account.
    await NotificationService.instance.addTokenToCurrentUser();
    rethrow;
  }

  final hasName =
      FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ??
          false;
  if (hasName) await OnboardingPrefs.setNameConfirmed();

  if (!context.mounted) return;
  context.router.replaceAll([
    if (hasName) const ChatsRoute() else const OnboardingRoute(),
  ]);
}
