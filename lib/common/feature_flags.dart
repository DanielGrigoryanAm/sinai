/// Features that are built but switched off in the UI.
abstract final class FeatureFlags {
  /// Adding a phone number in the profile and restoring an account by it
  /// on onboarding. Off until the app has its own backend; the code in
  /// lib/features/phone and AuthRepository stays ready.
  static const phoneSignIn = false;
}
