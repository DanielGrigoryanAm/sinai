/// Features that are built but switched off in the UI.
abstract final class FeatureFlags {
  /// Adding a phone number in the profile and restoring an account by it
  /// on onboarding. Off because each SMS costs money; the code in
  /// lib/features/phone and AuthRepository stays ready.
  static const phoneSignIn = false;

  /// Keeping and restoring an account with a Google account. Needs the
  /// Google provider on in Firebase and the apps' configs downloaded again.
  static const googleSignIn = true;
}
