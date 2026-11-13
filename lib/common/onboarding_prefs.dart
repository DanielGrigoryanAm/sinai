import 'package:shared_preferences/shared_preferences.dart';

/// Stores whether the user has confirmed their name on the onboarding screen.
class OnboardingPrefs {
  static const _nameConfirmedKey = 'name_confirmed';

  static Future<bool> isNameConfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_nameConfirmedKey) ?? false;
  }

  static Future<void> setNameConfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nameConfirmedKey, true);
  }
}
