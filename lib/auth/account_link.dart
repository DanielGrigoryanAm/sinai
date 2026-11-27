import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/common/onboarding_prefs.dart';
import 'package:sinai/features/chat/draft_store.dart';
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
    await signInWith(context, e.credential);
    return LinkOutcome.switched;
  }
}

/// Signs in to the account [credential] belongs to (Google makes one the
/// first time), moves the backend session, notifications and live socket
/// over to it, and opens the chats list.
///
/// The backend finds the account by its Firebase uid, or makes a new one.
/// Throws [PhoneAuthFailure] with a readable message.
Future<void> signInWith(
  BuildContext context,
  AuthCredential credential,
) async {
  final auth = AuthRepository();
  final hadAccount = FirebaseAuth.instance.currentUser != null;
  try {
    // This phone's notifications belong to the account being left.
    if (hadAccount) {
      await NotificationService.instance.removeTokenFromCurrentUser();
    }
    await auth.signIn(credential);
    // The backend session follows the Firebase account.
    await AuthApi.instance.switchToFirebaseAccount();
    await NotificationService.instance.addTokenToCurrentUser();
    QuickReactionsStore.instance.start();
  } on PhoneAuthFailure {
    // Put this phone's notifications back on the current account.
    if (hadAccount) await NotificationService.instance.addTokenToCurrentUser();
    rethrow;
  } catch (e) {
    debugPrint('Sign-in failed: $e');
    if (hadAccount) await NotificationService.instance.addTokenToCurrentUser();
    throw const PhoneAuthFailure('Could not sign in. Check the internet');
  }

  await OnboardingPrefs.setSignedIn();

  if (!context.mounted) return;
  context.router.replaceAll([const ChatsRoute()]);
}

/// Signs out of this account on this phone: its notifications stop, the
/// backend session ends, its drafts go, and onboarding asks to sign in
/// again (with the same Google account or another).
Future<void> signOut(BuildContext context) async {
  try {
    // While still signed in, so the backend can forget this phone.
    await NotificationService.instance.removeTokenFromCurrentUser();
    await LiveSocket.instance.stop();
    await AuthApi.instance.signOut();
    await FirebaseAuth.instance.signOut();
  } catch (e) {
    // Signed out here either way; the next sign-in replaces the rest.
    debugPrint('Signing out: $e');
  }
  await OnboardingPrefs.clear();
  await DraftStore.instance.clear();

  if (!context.mounted) return;
  context.router.replaceAll([const OnboardingRoute()]);
}
