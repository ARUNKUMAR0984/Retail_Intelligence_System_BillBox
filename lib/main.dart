import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:retail_intelligence_system/data/repositories/auth_repository.dart';
import 'package:retail_intelligence_system/logic/blocs/auth/auth_bloc.dart';
import 'package:retail_intelligence_system/presentation/screens/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gdlokvsoyolcidvudmnz.supabase.co',
    anonKey: 'sb_publishable_VXvBU5tzVerQ-ev0JQowJA_WtLWxGHI',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
  providers: [
    BlocProvider(
      create: (_) => AuthBloc(AuthRepository()),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const LoginScreen(),
  ),
);
  }
}