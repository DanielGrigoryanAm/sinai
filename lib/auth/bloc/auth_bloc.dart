import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<SendPhoneNumber>(_onSendPhoneNumber);
    on<VerifySmsCode>(_onVerifySmsCode);
    on<PhoneNumberSentEvent>((event, emit) => emit(PhoneNumberSent(event.verificationId)));
  }

  Future<void> _onSendPhoneNumber(
    SendPhoneNumber event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await authRepository.sendPhoneNumber(
        phoneNumber: event.phoneNumber,
        onCodeSent: (verificationId) {
          add(PhoneNumberSentEvent(verificationId));
        },
      );
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onVerifySmsCode(
    VerifySmsCode event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await authRepository.verifySmsCode(
        verificationId: event.verificationId,
        smsCode: event.smsCode,
      );
      emit(AuthSuccess());
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }
}
