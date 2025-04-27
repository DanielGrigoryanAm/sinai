import 'package:bloc/bloc.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<SendPhoneNumber>(_onSendPhoneNumber);
    on<VerifySmsCode>(_onVerifySmsCode);
  }

  Future<void> _onSendPhoneNumber(
      SendPhoneNumber event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await authRepository.sendPhoneNumber(
        phoneNumber: event.phoneNumber,
        onCodeSent: (verificationId) {
          emit(PhoneNumberSent(verificationId));
        },
      );
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onVerifySmsCode(
      VerifySmsCode event, Emitter<AuthState> emit) async {
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