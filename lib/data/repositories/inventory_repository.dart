import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryRepository {
  final supabase = Supabase.instance.client;

  Future<String> getShopId() async {
    final user = supabase.auth.currentUser;
    final data = await supabase
        .from('shops')
        .select('id')
        .eq('user_id', user!.id)
        .single();

    return data['id'];
  }
Future<void> deleteInventoryItem(String id) async {
  await supabase.from('inventory').delete().eq('id', id);
}

  Future<List<Map<String, dynamic>>> loadInventory() async {
    final shopId = await getShopId();

    final data = await supabase
        .from('inventory')
        .select('id, selling_price, stock_qty, master_products (product_name, brand, mrp)')
        .eq('shop_id', shopId);

    return List<Map<String, dynamic>>.from(data);
  }
}
