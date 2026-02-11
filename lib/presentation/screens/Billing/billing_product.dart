import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:retail_intelligence_system/logic/barcode/barcode_scanner.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final supabase = Supabase.instance.client;

  bool isLoading = false;
  List<Map<String, dynamic>> cart = [];
  double total = 0;
  double discount = 0;
  String paymentMethod = "Cash";
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String _extractMessage(dynamic e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  Future<String> getShopId() async {
    final user = supabase.auth.currentUser;
    final data = await supabase
        .from("shops")
        .select("id")
        .eq("user_id", user!.id)
        .single();
    return data["id"];
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (!mounted) return;

    if (result != null && result is String) {
      await _addItemToCart(result);
    }
  }

  Future<void> _addItemToCart(String barcode) async {
    safeSetState(() => isLoading = true);

    try {
      final shopId = await getShopId();

      final data = await supabase
          .from("inventory")
          .select("selling_price, stock_qty, master_products(product_name, brand)")
          .eq("shop_id", shopId)
          .eq("barcode", barcode)
          .maybeSingle();

      if (data == null) {
        _showError("Product not found in inventory");
        safeSetState(() => isLoading = false);
        return;
      }

      if (data["stock_qty"] <= 0) {
        _showError("Product is out of stock");
        safeSetState(() => isLoading = false);
        return;
      }

      // Check if item already in cart
      final existingIndex = cart.indexWhere((item) => item["barcode"] == barcode);
      
      if (existingIndex != -1) {
        // Update quantity if already in cart
        safeSetState(() {
          cart[existingIndex]["qty"]++;
          cart[existingIndex]["subtotal"] = 
              cart[existingIndex]["qty"] * cart[existingIndex]["price"];
          _calculateTotal();
          isLoading = false;
        });
      } else {
        // Add new item to cart
        safeSetState(() {
          cart.add({
            "barcode": barcode,
            "name": data["master_products"]["product_name"],
            "brand": data["master_products"]["brand"] ?? "",
            "price": data["selling_price"],
            "qty": 1,
            "subtotal": data["selling_price"],
          });
          _calculateTotal();
          isLoading = false;
        });
      }
    } catch (e) {
      _showError("Error adding product: ${_extractMessage(e)}");
      safeSetState(() => isLoading = false);
    }
  }

  void _increaseQty(int i) {
    safeSetState(() {
      cart[i]["qty"]++;
      cart[i]["subtotal"] = cart[i]["qty"] * cart[i]["price"];
      _calculateTotal();
    });
  }

  void _decreaseQty(int i) {
    safeSetState(() {
      if (cart[i]["qty"] > 1) {
        cart[i]["qty"]--;
        cart[i]["subtotal"] = cart[i]["qty"] * cart[i]["price"];
        _calculateTotal();
      }
    });
  }

  void _removeItem(int i) {
    safeSetState(() {
      cart.removeAt(i);
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    total = cart.fold(0, (sum, item) => sum + item["subtotal"]);
  }

  void _applyDiscount() {
    final discountValue = double.tryParse(_discountController.text) ?? 0;
    safeSetState(() {
      discount = discountValue;
    });
  }

  double get finalTotal => total - discount;

  Future<void> _saveBill() async {
    if (cart.isEmpty) {
      _showError("Cart is empty. Add products to continue.");
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ₹${total.toStringAsFixed(2)}'),
            if (discount > 0) Text('Discount: ₹${discount.toStringAsFixed(2)}'),
            Text(
              'Final Amount: ₹${finalTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text('Payment: $paymentMethod'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    safeSetState(() => isLoading = true);

    try {
      final shopId = await getShopId();

      final bill = await supabase
          .from("bills")
          .insert({
            "shop_id": shopId,
            "total": finalTotal,
            "payment_method": paymentMethod,
          })
          .select('*')
          .single();

      final billId = bill["id"];

      for (var item in cart) {
        await supabase.from("bill_items").insert({
          "bill_id": billId,
          "barcode": item["barcode"],
          "qty": item["qty"],
          "price": item["price"],
          "subtotal": item["subtotal"],
        });

        await supabase.rpc(
          "decrement_stock",
          params: {
            "p_shop_id": shopId,
            "p_barcode": item["barcode"],
            "p_qty": item["qty"],
          },
        );
      }

      _showSuccess("Bill saved successfully!");

      safeSetState(() {
        cart.clear();
        total = 0;
        discount = 0;
        _customerNameController.clear();
        _customerPhoneController.clear();
        _discountController.clear();
        isLoading = false;
      });
    } catch (e) {
      _showError("Error saving bill: ${_extractMessage(e)}");
      safeSetState(() => isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "New Bill",
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (cart.isNotEmpty)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFEF4444),
                  size: 22,
                ),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text('Clear Cart?'),
                    content: const Text('Are you sure you want to clear all items?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          safeSetState(() {
                            cart.clear();
                            total = 0;
                            discount = 0;
                            _discountController.clear();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Scan Button
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _scanBarcode,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                      label: const Text(
                        'Scan Product',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),

                // Cart Items
                Expanded(
                  child: cart.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Cart is Empty',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Scan products to add them to cart',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: cart.length,
                          itemBuilder: (_, i) {
                            final item = cart[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    // Product Icon
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.shopping_bag_outlined,
                                        color: Color(0xFF10B981),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Product Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item["name"],
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                          if (item["brand"] != null && 
                                              item["brand"].toString().isNotEmpty)
                                            const SizedBox(height: 4),
                                          if (item["brand"] != null && 
                                              item["brand"].toString().isNotEmpty)
                                            Text(
                                              item["brand"],
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Text(
                                                '₹${item["price"]}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ),
                                              const Text(' × '),
                                              Text(
                                                '${item["qty"]}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const Text(' = '),
                                              Text(
                                                '₹${item["subtotal"].toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF1F2937),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Quantity Controls
                                    Column(
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6366F1)
                                                    .withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.remove,
                                                  size: 18,
                                                ),
                                                color: const Color(0xFF6366F1),
                                                onPressed: () => _decreaseQty(i),
                                                constraints: const BoxConstraints(
                                                  minWidth: 36,
                                                  minHeight: 36,
                                                ),
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981)
                                                    .withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 18,
                                                ),
                                                color: const Color(0xFF10B981),
                                                onPressed: () => _increaseQty(i),
                                                constraints: const BoxConstraints(
                                                  minWidth: 36,
                                                  minHeight: 36,
                                                ),
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        InkWell(
                                          onTap: () => _removeItem(i),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444)
                                                  .withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Remove',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFFEF4444),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Bottom Section
                if (cart.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Discount Section
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _discountController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Discount',
                                    hintText: 'Enter discount amount',
                                    prefixIcon: const Icon(
                                      Icons.local_offer_outlined,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF6366F1),
                                        width: 2,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  onChanged: (_) => _applyDiscount(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: _applyDiscount,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Apply'),
                              ),
                            ],
                          ),
                        ),

                        // Payment Method
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.payment_outlined,
                                  color: Color(0xFF6366F1),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Payment:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    children: [
                                      _buildPaymentChip('Cash'),
                                      _buildPaymentChip('UPI'),
                                      _buildPaymentChip('Card'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Total Section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Subtotal',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                  Text(
                                    '₹${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (discount > 0) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Discount',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                    Text(
                                      '- ₹${discount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Amount',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  Text(
                                    '₹${finalTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Submit Button
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _saveBill,
                              icon: const Icon(Icons.check_circle_outline, size: 24),
                              label: const Text(
                                'Complete Bill',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildPaymentChip(String method) {
    final isSelected = paymentMethod == method;
    return ChoiceChip(
      label: Text(method),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          safeSetState(() => paymentMethod = method);
        }
      },
      selectedColor: const Color(0xFF6366F1),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF1F2937),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? const Color(0xFF6366F1) : Colors.grey[300]!,
        ),
      ),
    );
  }
}