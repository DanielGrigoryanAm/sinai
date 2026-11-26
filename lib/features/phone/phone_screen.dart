import 'dart:async';
import 'package:sinai/common/app_icons.dart';

import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/toast.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:sinai/auth/account_link.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Adds a phone number to the account, or restores an account by its
/// number. Pops with `true` when a number was linked to the current
/// account; switching to another account replaces the whole navigation.
@RoutePage()
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, this.restore = false});

  /// Opened from onboarding to get an existing account back.
  final bool restore;

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final AuthRepository _auth = AuthRepository();
  final TextEditingController _codeController = TextEditingController();

  String _phone = '';
  bool _phoneValid = false;

  /// Set once the SMS was sent; the screen then asks for the code.
  String? _verificationId;
  int? _resendToken;

  bool _busy = false;
  String? _error;

  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void dispose() {
    _codeController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _auth.sendCode(_phone, resendToken: _resendToken);
      if (!mounted) return;
      switch (result) {
        case SmsCodeSent(:final verificationId, :final resendToken):
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _busy = false;
          });
          _startResendTimer();
        case PhoneAutoVerified(:final credential):
          await _complete(credential);
      }
    } on PhoneAuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _confirmCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6 || _verificationId == null) return;
    await _complete(_auth.credentialFor(_verificationId!, code));
  }

  /// Links the number to this account, or offers to switch to the account
  /// that already has it.
  Future<void> _complete(PhoneAuthCredential credential) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final outcome = await linkOrSwitch(
        context,
        credential,
        restore: widget.restore,
        what: 'number',
      );
      if (!mounted) return;
      if (outcome == LinkOutcome.linked) {
        showToast(
            widget.restore
                ? 'Number saved. Now enter your name'
                : 'Phone number added',
            kind: ToastKind.success);
        context.router.maybePop(true);
      } else if (outcome == LinkOutcome.cancelled) {
        setState(() => _busy = false);
      }
    } on PhoneAuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    setState(() {
      _verificationId = null;
      _resendToken = null;
      _codeController.clear();
      _error = null;
      _resendIn = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final askingCode = _verificationId != null;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: CustomAppBar(
          title: widget.restore ? 'Restore account' : 'Phone number',
          showBackButton: true,
        ),
        backgroundColor: colors.backgroundPrimary,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  askingCode
                      ? 'Enter the code we sent to $_phone'
                      : widget.restore
                          ? 'Enter the number you added to your account. '
                              'Your name and chats will come back.'
                          : 'Add your number to keep your name and chats if '
                              'you reinstall the app or change phone.',
                  style: text.bodyLarge.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(AppIcons.lock, size: 16, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Only you can see your number.',
                        style: text.bodySmall
                            .copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                if (!askingCode)
                  IntlPhoneField(
                    initialCountryCode: 'AM',
                    enabled: !_busy,
                    disableLengthCheck: false,
                    invalidNumberMessage: 'Invalid phone number',
                    cursorColor: colors.secondary,
                    decoration: InputDecoration(
                      hintText: 'Phone number',
                      filled: true,
                      fillColor: colors.backgroundSecondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: colors.secondary, width: 2),
                      ),
                    ),
                    onChanged: (phone) {
                      bool valid;
                      try {
                        valid = phone.isValidNumber();
                      } catch (_) {
                        valid = false;
                      }
                      setState(() {
                        _phone = phone.completeNumber;
                        _phoneValid = valid;
                      });
                    },
                  )
                else
                  TextField(
                    controller: _codeController,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: text.titleLarge.copyWith(letterSpacing: 10),
                    cursorColor: colors.secondary,
                    onChanged: (code) {
                      setState(() {});
                      if (code.length == 6) _confirmCode();
                    },
                    decoration: InputDecoration(
                      hintText: '••••••',
                      filled: true,
                      fillColor: colors.backgroundSecondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: colors.secondary, width: 2),
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        text.bodySmall.copyWith(color: const Color(0xFFDC2626)),
                  ),
                ],
                const SizedBox(height: 24),
                CustomButton.primary(
                  text: askingCode ? 'Confirm' : 'Send code',
                  isLoading: _busy,
                  onTap: _busy
                      ? null
                      : askingCode
                          ? (_codeController.text.length == 6
                              ? _confirmCode
                              : null)
                          : (_phoneValid ? _sendCode : null),
                ),
                if (askingCode) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : _changeNumber,
                        child: Text(
                          'Change number',
                          style: text.bodySmall
                              .copyWith(color: colors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy || _resendIn > 0 ? null : _sendCode,
                        child: Text(
                          _resendIn > 0
                              ? 'Resend in $_resendIn s'
                              : 'Resend code',
                          style: text.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _resendIn > 0
                                ? colors.textSecondary
                                : colors.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
