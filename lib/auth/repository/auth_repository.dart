import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Result of asking Firebase to verify a phone number.
sealed class PhoneCodeResult {
  const PhoneCodeResult();
}

/// An SMS code was sent; the user types it in.
class SmsCodeSent extends PhoneCodeResult {
  const SmsCodeSent(this.verificationId, this.resendToken);

  final String verificationId;
  final int? resendToken;
}

/// Android read the SMS by itself; no code to type.
class PhoneAutoVerified extends PhoneCodeResult {
  const PhoneAutoVerified(this.credential);

  final PhoneAuthCredential credential;
}

/// A readable reason phone verification failed.
class PhoneAuthFailure implements Exception {
  const PhoneAuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The number already belongs to another account. [credential] signs in
/// to that account.
class PhoneNumberInUse implements Exception {
  const PhoneNumberInUse(this.credential);

  final AuthCredential credential;
}

/// Phone number sign-in, used only to keep an account: the app signs in
/// anonymously, and a phone number can be added later to restore the
/// account after a reinstall or on a new phone.
///
/// The number lives only in Firebase Authentication. It is never written to
/// Firestore, so other users have no way to see it.
class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// The current user's number, or null when none is linked.
  String? get phoneNumber {
    final number = _auth.currentUser?.phoneNumber;
    return number == null || number.isEmpty ? null : number;
  }

  /// Sends an SMS code to [phoneNumber] (international format, with +).
  Future<PhoneCodeResult> sendCode(String phoneNumber, {int? resendToken}) {
    final completer = Completer<PhoneCodeResult>();

    _auth
        .verifyPhoneNumber(
          phoneNumber: phoneNumber,
          forceResendingToken: resendToken,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (credential) {
            if (!completer.isCompleted) {
              completer.complete(PhoneAutoVerified(credential));
            }
          },
          verificationFailed: (e) {
            if (!completer.isCompleted) {
              completer.completeError(PhoneAuthFailure(_describe(e)));
            }
          },
          codeSent: (verificationId, token) {
            if (!completer.isCompleted) {
              completer.complete(SmsCodeSent(verificationId, token));
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        )
        .catchError((Object e) {
      if (!completer.isCompleted) {
        completer.completeError(
          PhoneAuthFailure(
            e is FirebaseAuthException ? _describe(e) : 'Could not send code',
          ),
        );
      }
    });

    return completer.future;
  }

  PhoneAuthCredential credentialFor(String verificationId, String code) =>
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );

  /// Adds the number to the current account, keeping its chats and name.
  /// Throws [PhoneNumberInUse] when the number has an account already.
  Future<void> link(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw const PhoneAuthFailure('Not signed in');

    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'account-exists-with-different-credential') {
        throw PhoneNumberInUse(e.credential ?? credential);
      }
      throw PhoneAuthFailure(_describe(e));
    }
  }

  /// Switches to the account the number belongs to.
  Future<void> signIn(AuthCredential credential) async {
    try {
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw PhoneAuthFailure(_describe(e));
    }
  }

  static String _describe(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => 'This phone number is not valid',
        'invalid-verification-code' => 'Wrong code',
        'invalid-verification-id' ||
        'session-expired' =>
          'The code has expired. Send a new one',
        'too-many-requests' => 'Too many attempts. Try again later',
        'quota-exceeded' => 'SMS limit reached. Try again later',
        'network-request-failed' => 'No internet connection',
        'operation-not-allowed' =>
          'Phone sign-in is not enabled for this app yet',
        _ => e.message ?? 'Something went wrong',
      };
}
