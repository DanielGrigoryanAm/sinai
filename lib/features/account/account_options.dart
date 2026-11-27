import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/auth/account_link.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/common/feature_flags.dart';
import 'package:sinai/common/settings_section.dart';
import 'package:sinai/common/toast.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';

/// Onboarding: signs in with a Google account. The first time it makes a
/// Sinai account; after that it brings the same one back, chats included.
Future<void> signInWithGoogle(BuildContext context) async {
  final auth = AuthRepository();
  try {
    final credential = await auth.googleCredential();
    if (!context.mounted) return;
    await signInWith(context, credential);
  } on SignInCancelled {
    // Closed the Google window: nothing to say.
  } on PhoneAuthFailure catch (e) {
    showToast(e.message, kind: ToastKind.error);
  }
}

/// How the user signs in, on their own profile: the Google account (and,
/// once phone sign-in is on, a button to add a number).
class AccountSection extends StatefulWidget {
  const AccountSection({super.key});

  /// Whether there is anything to show.
  static bool get enabled =>
      FeatureFlags.googleSignIn || FeatureFlags.phoneSignIn;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  final _auth = AuthRepository();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final google = _auth.googleEmail;
    final phone = _auth.phoneNumber;

    return SettingsSection(
      label: 'Account',
      caption: 'You sign in with this. Use it after a reinstall or on a new '
          'phone to get your name and chats back. Only you can see it.',
      rows: [
        if (FeatureFlags.googleSignIn)
          SettingsRow(
            leading: const GoogleMark(),
            trailing: Icon(AppIcons.check, size: 18, color: colors.secondary),
            child: Text(google ?? 'Google'),
          ),
        if (FeatureFlags.phoneSignIn)
          SettingsRow(
            leading: const Icon(AppIcons.phone),
            trailing: phone == null
                ? null
                : Icon(AppIcons.check, size: 18, color: colors.secondary),
            onTap: phone != null
                ? null
                : () async {
                    await context.router.push(PhoneRoute());
                    if (mounted) setState(() {});
                  },
            child: Text(phone ?? 'Add phone number'),
          ),
      ],
    );
  }
}

/// Google's "G", in its blue.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});

  @override
  Widget build(BuildContext context) => const Text(
        'G',
        style: TextStyle(
          fontSize: 20,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
        ),
      );
}
