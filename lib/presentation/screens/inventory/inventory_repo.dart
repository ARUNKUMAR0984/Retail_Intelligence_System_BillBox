import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryRepository {
  final supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> loadInventory() async {
    try {
      // Get the current user's shop_id (you may need to adjust this based on your auth setup)
      // For now, I'm assuming you store shop_id in user metadata or have a way to get it
      final userId = supabase.auth.currentUser?.id;
      
      if (userId == null) {
        print('No user logged in');
        return [];
      }

      // CRITICAL: Explicitly select 'barcode' from inventory table
      final response = await supabase
          .from('inventory')
          .select('''
            id,
            shop_id,
            barcode,
            selling_price,
            stock_qty,
            updated_at,
            created_at,
            master_products (
              barcode,
              product_name,
              brand,
              mrp,
              gst
            )
          ''')
          // Add filter for shop_id if needed - uncomment and adjust based on your setup
          // .eq('shop_id', shopId)
          .order('updated_at', ascending: false);

      print('=== REPOSITORY DEBUG ===');
      print('Inventory data loaded: ${response.length} items');
      if (response.isNotEmpty) {
        print('First item keys: ${response[0].keys.toList()}');
        print('First item barcode: ${response[0]['barcode']}');
        print('First item: ${response[0]}');
      }
      print('=======================');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error loading inventory: $e');
      return [];
    }
  }

  Future<void> deleteInventoryItem(String id) async {
    try {
      await supabase.from('inventory').delete().eq('id', id);
    } catch (e) {
      print('Error deleting inventory item: $e');
      rethrow;
    }
  }
}