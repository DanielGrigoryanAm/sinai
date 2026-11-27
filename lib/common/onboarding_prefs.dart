import 'package:shared_preferences/shared_preferences.dart';

/// Stores whether the user has got through onboarding, i.e. signed in.
///
/// The key keeps its old name: people who confirmed their name before
/// sign-in became required stay past onboarding.
class OnboardingPrefs {
  static const _signedInKey = 'name_confirmed';

  static Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_signedInKey) ?? false;
  }

  static Future<void> setSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_signedInKey, true);
  }
}
