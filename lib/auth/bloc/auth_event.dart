import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class SendPhoneNumber extends AuthEvent {
  final String phoneNumber;

  const SendPhoneNumber(this.phoneNumber);
}

class VerifySmsCode extends AuthEvent {
  final String smsCode;
  final String verificationId;

  const VerifySmsCode(this.smsCode, this.verificationId);
}

class PhoneNumberSentEvent extends AuthEvent {
  final String verificationId;

  const PhoneNumberSentEvent(this.verificationId);

  @override
  List<Object?> get props => [verificationId];
}