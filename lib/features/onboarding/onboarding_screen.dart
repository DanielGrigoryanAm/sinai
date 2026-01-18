import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatBloc(),
      child: OnboardingScreenView(),
    );
  }
}

class OnboardingScreenView extends StatefulWidget {
  const OnboardingScreenView({super.key});

  @override
  State<OnboardingScreenView> createState() => _OnboardingScreenViewState();
}

class _OnboardingScreenViewState extends State<OnboardingScreenView> {
  final TextEditingController _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Wellcome to Sinai',
      ),
      backgroundColor: context.colorTheme.backgroundSecondary,
      body: Padding(
        padding: const EdgeInsets.only(top: 100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.colorTheme.secondary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Assets.images.mountain.image(height: 200),
              ),
              SizedBox(height: 50),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50)),
                  hintText: 'Enter your name',
                ),
              ),
              SizedBox(height: 100),
              CustomButton(
                text: 'Start',
                onTap: _onStart,
              ),
              SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  void _onStart() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    context.read<ChatBloc>().add(
          SetUserNameEvent(name),
        );

    context.router.replace(const StartChatRoute());
  }
}
