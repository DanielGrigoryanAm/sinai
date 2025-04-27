import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/auth/bloc/auth_bloc.dart';
import 'package:sinai/auth/bloc/auth_event.dart';
import 'package:sinai/auth/bloc/auth_state.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class CheckCodeScreen extends StatefulWidget {
  final String verificationId;

  const CheckCodeScreen({super.key, required this.verificationId});

  @override
  State<CheckCodeScreen> createState() => _CheckCodeScreenState();
}

class _CheckCodeScreenState extends State<CheckCodeScreen> {
  final TextEditingController _codeController = TextEditingController();

  void _onCheckCode() {
    final smsCode = _codeController.text.trim();
    if (smsCode.isNotEmpty) {
      context
          .read<AuthBloc>()
          .add(VerifySmsCode(smsCode, widget.verificationId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthSuccess) {
          context.router.replace(HomeRoute());
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
          appBar: CustomAppBar(title: 'Check Code'),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(30, 250, 30, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Please Enter code',
                  style: context.textTheme.titleSmall,
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Enter code',
                    hintText: '_ _ _ _',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 50),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthLoading) {
                      return const CircularProgressIndicator();
                    }
                    return CustomButton(
                      text: 'Check code',
                      onTap: _onCheckCode,
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

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
