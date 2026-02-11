import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  LoginRequested(this.email, this.password);
}

class SignupRequested extends AuthEvent {
  final String email;
  final String password;
  final String ownerName;
  final String shopName;
  final String phone;

  SignupRequested(
    this.email,
    this.password,
    this.ownerName,
    this.shopName,
    this.phone,
  );
}
