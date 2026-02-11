import 'package:supabase_flutter/supabase_flutter.dart';
class AuthRepository {
  final _client = Supabase.instance.client;

  Future<void> signUp(
    String email,
    String password,
    String ownerName,
    String shopName,
    String phone,
  ) async {
    // 1. Register user
    final res = await _client.auth.signUp(
      email: email,
      password: password,
    );

    if (res.user == null) {
      throw Exception("Signup failed");
    }

    final userId = res.user!.id;

    // 2. Insert shop
    await _client.from('shops').insert({
      'user_id': userId,
      'owner_name': ownerName,
      'shop_name': shopName,
      'phone': phone,
    });

    // 3. Auto login
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }


  Future<void> login(String email, String password) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (res.user == null) {
      throw Exception("Login failed");
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
