import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:sinai/auth/bloc/auth_bloc.dart';
import 'package:sinai/auth/bloc/auth_event.dart';
import 'package:sinai/auth/bloc/auth_state.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _phoneNumber = '';

  void _onEnterPhone() {
    if (_phoneNumber.isNotEmpty) {
      context.read<AuthBloc>().add(SendPhoneNumber(_phoneNumber));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is PhoneNumberSent) {
          context.router.replace(CheckCodeRoute(verificationId: state.verificationId));
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error)),
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: context.colorTheme.background,
          appBar: CustomAppBar(title: 'LogIn'),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(30, 250, 30, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Please Enter your phone number',
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: 40),
                IntlPhoneField(
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (phone) {
                    _phoneNumber = phone.completeNumber.replaceAll(' ', '').replaceAll('-', '');
                  },
                ),
                const SizedBox(height: 50),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthLoading) {
                      return const CircularProgressIndicator();
                    }
                    return CustomButton(
                      text: 'Enter code',
                      onTap: _onEnterPhone,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}