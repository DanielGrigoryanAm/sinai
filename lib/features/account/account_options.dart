import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/auth/account_link.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/feature_flags.dart';
import 'package:sinai/common/toast.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Picks a Google account and adds it to this account, or moves to the
/// account it belongs to. True when it was added here.
Future<bool> continueWithGoogle(BuildContext context,
    {required bool restore}) async {
  final auth = AuthRepository();
  try {
    final credential = await auth.googleCredential();
    if (!context.mounted) return false;
    final outcome = await linkOrSwitch(context, credential,
        restore: restore, what: 'Google account');
    if (outcome == LinkOutcome.linked) {
      showToast(
        restore ? 'Google account saved. Now enter your name' : 'Google added',
        kind: ToastKind.success,
      );
      return true;
    }
  } on SignInCancelled {
    // Closed the Google window: nothing to say.
  } on PhoneAuthFailure catch (e) {
    showToast(e.message, kind: ToastKind.error);
  }
  return false;
}

/// The ways to keep the account, on the user's own profile: each shows
/// what is added, or a button to add it.
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
  bool _busy = false;

  Future<void> _google() async {
    setState(() => _busy = true);
    await continueWithGoogle(context, restore: false);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final google = _auth.googleEmail;
    final phone = _auth.phoneNumber;
    final saved = google != null || phone != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            saved
                ? 'Your account is saved. Sign in with any of these after '
                    'a reinstall or on a new phone. Only you can see them.'
                : 'Add a way to sign in to keep your name and chats if you '
                    'reinstall the app or change phone. Only you can see it.',
            style: text.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (FeatureFlags.googleSignIn)
            _Option(
              mark: const GoogleMark(),
              label: google ?? 'Add Google',
              added: google != null,
              onTap: _busy || google != null ? null : _google,
            ),
          if (FeatureFlags.phoneSignIn)
            _Option(
              mark: Icon(AppIcons.phone, size: 20, color: colors.secondary),
              label: phone ?? 'Add phone number',
              added: phone != null,
              onTap: _busy || phone != null
                  ? null
                  : () async {
                      await context.router.push(PhoneRoute());
                      if (mounted) setState(() {});
                    },
            ),
        ],
      ),
    );
  }
}

/// Getting an existing account back on a fresh install.
@RoutePage()
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  bool _busy = false;

  Future<void> _google() async {
    setState(() => _busy = true);
    final added = await continueWithGoogle(context, restore: true);
    if (!mounted) return;
    setState(() => _busy = false);
    // A Google account new to Sinai: back to onboarding for the name.
    if (added) context.router.maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Restore account',
        showBackButton: true,
      ),
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 30),
          children: [
            Text(
              'Sign in the way you saved your account. Your name and chats '
              'will come back.',
              style: text.bodyLarge.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 28),
            if (FeatureFlags.googleSignIn)
              _Option(
                mark: const GoogleMark(),
                label: 'Continue with Google',
                onTap: _busy ? null : _google,
              ),
            if (FeatureFlags.phoneSignIn)
              _Option(
                mark: Icon(AppIcons.phone, size: 20, color: colors.secondary),
                label: 'Continue with phone number',
                onTap: _busy
                    ? null
                    : () => context.router.push(PhoneRoute(restore: true)),
              ),
          ],
        ),
      ),
    );
  }
}

/// One way of signing in: a white row with its mark, or a check once
/// added.
class _Option extends StatelessWidget {
  const _Option({
    required this.mark,
    required this.label,
    required this.onTap,
    this.added = false,
  });

  final Widget mark;
  final String label;
  final VoidCallback? onTap;
  final bool added;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                SizedBox.square(dimension: 24, child: Center(child: mark)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge.copyWith(
                      fontWeight: added ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ),
                if (added)
                  Icon(AppIcons.check, size: 18, color: colors.secondary),
              ],
            ),
          ),
        ),
      ),
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
