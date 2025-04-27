import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/custom_app_bar.dart';

@RoutePage()
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Home',
      ),
      body: Container(
        
      ),
    );
  }
}
