import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
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
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: context.colorTheme.background,
          appBar: CustomAppBar(
            title: 'LogIn',
          ),
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
                  pickerDialogStyle: PickerDialogStyle(
                    backgroundColor: context.colorTheme.background,
                    padding: EdgeInsets.only(
                        top: 30, left: 30, right: 30, bottom: 10),
                    countryCodeStyle: context.textTheme.bodyLarge,
                    countryNameStyle: context.textTheme.bodyLarge,
                    searchFieldCursorColor: context.colorTheme.textSecondary,
                    listTilePadding: EdgeInsets.symmetric(horizontal: 0),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    fillColor: context.colorTheme.textPrimary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (phone) {
                    print('Полный номер: ${phone.completeNumber}');
                  },
                  onCountryChanged: (country) {
                    print('Страна изменилась: ${country.name}');
                  },
                ),
                SizedBox(height: 50),
                CustomButton(
                  text: 'Enter code',
                  onTap: () {
                    context.router.push(CheckCodeRoute());
                  },
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
