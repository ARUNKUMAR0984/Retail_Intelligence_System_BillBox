import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:retail_intelligence_system/presentation/screens/Billing/billing_details.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  List<Map<String, dynamic>> bills = [];
  List<Map<String, dynamic>> filteredBills = [];
  String searchQuery = '';
  String filterPeriod = 'All Time';
  String filterPayment = 'All';

  @override
  void initState() {
    super.initState();
    loadBills();
  }

  Future<void> loadBills() async {
    setState(() => isLoading = true);

    try {
      final shop = await supabase
          .from('shops')
          .select('id')
          .eq('user_id', supabase.auth.currentUser!.id)
          .single();

      final shopId = shop['id'];

      final data = await supabase
          .from('bills')
          .select()
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      setState(() {
        bills = List<Map<String, dynamic>>.from(data);
        _applyFilters();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Error loading bills: ${e.toString()}');
    }
  }

  void _applyFilters() {
    filteredBills = bills.where((bill) {
      // Search filter
      final billId = bill['id'].toString().toLowerCase();
      final matchesSearch = searchQuery.isEmpty || billId.contains(searchQuery.toLowerCase());

      // Payment method filter
      final matchesPayment = filterPayment == 'All' || bill['payment_method'] == filterPayment;

      // Period filter
      bool matchesPeriod = true;
      if (filterPeriod != 'All Time') {
        final billDate = DateTime.parse(bill['created_at']);
        final now = DateTime.now();
        
        switch (filterPeriod) {
          case 'Today':
            matchesPeriod = billDate.year == now.year &&
                billDate.month == now.month &&
                billDate.day == now.day;
            break;
          case 'This Week':
            final weekStart = now.subtract(Duration(days: now.weekday - 1));
            matchesPeriod = billDate.isAfter(weekStart);
            break;
          case 'This Month':
            matchesPeriod = billDate.year == now.year && billDate.month == now.month;
            break;
        }
      }

      return matchesSearch && matchesPayment && matchesPeriod;
    }).toList();
  }

  double get totalRevenue {
    return filteredBills.fold(0.0, (sum, bill) => sum + (bill['total'] as num).toDouble());
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    DateTime dt;
    if (value is DateTime) {
      dt = value;
    } else {
      dt = DateTime.parse(value.toString());
    }
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  String _formatCurrency(double amount) {
    if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amount.toStringAsFixed(0)}';
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
          "Bill History",
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.filter_list,
                color: Color(0xFF1F2937),
                size: 22,
              ),
            ),
            onPressed: _showFilterOptions,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadBills,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Stats Header
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Search Bar
                        TextField(
                          onChanged: (value) {
                            setState(() {
                              searchQuery = value;
                              _applyFilters();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by Bill ID...',
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() {
                                        searchQuery = '';
                                        _applyFilters();
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
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
                        ),
                        const SizedBox(height: 16),

                        // Stats Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.receipt_long_outlined,
                                label: 'Total Bills',
                                value: filteredBills.length.toString(),
                                color: const Color(0xFF6366F1),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                icon: Icons.currency_rupee,
                                label: 'Total Revenue',
                                value: _formatCurrency(totalRevenue),
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Active Filters
                  if (filterPeriod != 'All Time' || filterPayment != 'All')
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (filterPeriod != 'All Time')
                            Chip(
                              label: Text(filterPeriod),
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: () {
                                setState(() {
                                  filterPeriod = 'All Time';
                                  _applyFilters();
                                });
                              },
                              backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                              labelStyle: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (filterPayment != 'All')
                            Chip(
                              label: Text(filterPayment),
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: () {
                                setState(() {
                                  filterPayment = 'All';
                                  _applyFilters();
                                });
                              },
                              backgroundColor: const Color(0xFF10B981).withOpacity(0.1),
                              labelStyle: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Bills List
                  Expanded(
                    child: filteredBills.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  searchQuery.isNotEmpty
                                      ? 'No bills found'
                                      : 'No bills yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  searchQuery.isNotEmpty
                                      ? 'Try different search terms'
                                      : 'Create your first bill',
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
                            itemCount: filteredBills.length,
                            itemBuilder: (_, i) => _buildBillCard(filteredBills[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> bill) {
    final paymentMethod = bill['payment_method'];
    Color paymentColor;
    IconData paymentIcon;

    switch (paymentMethod) {
      case 'Cash':
        paymentColor = const Color(0xFF10B981);
        paymentIcon = Icons.money;
        break;
      case 'UPI':
        paymentColor = const Color(0xFF6366F1);
        paymentIcon = Icons.qr_code;
        break;
      case 'Card':
        paymentColor = const Color(0xFFF59E0B);
        paymentIcon = Icons.credit_card;
        break;
      default:
        paymentColor = Colors.grey;
        paymentIcon = Icons.payment;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BillDetailsScreen(billId: bill['id']),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Bill Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF6366F1),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // Bill Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${bill['total'].toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: paymentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                paymentIcon,
                                size: 14,
                                color: paymentColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                paymentMethod,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: paymentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatDate(bill['created_at']),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.tag,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            bill['id'].toString().substring(0, 8),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Bills',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            filterPeriod = 'All Time';
                            filterPayment = 'All';
                            _applyFilters();
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Period',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['All Time', 'Today', 'This Week', 'This Month']
                        .map((period) => ChoiceChip(
                              label: Text(period),
                              selected: filterPeriod == period,
                              onSelected: (selected) {
                                setModalState(() {
                                  filterPeriod = period;
                                });
                                setState(() {
                                  filterPeriod = period;
                                  _applyFilters();
                                });
                              },
                              selectedColor: const Color(0xFF6366F1),
                              backgroundColor: Colors.grey[200],
                              labelStyle: TextStyle(
                                color: filterPeriod == period
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Payment Method',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['All', 'Cash', 'UPI', 'Card']
                        .map((payment) => ChoiceChip(
                              label: Text(payment),
                              selected: filterPayment == payment,
                              onSelected: (selected) {
                                setModalState(() {
                                  filterPayment = payment;
                                });
                                setState(() {
                                  filterPayment = payment;
                                  _applyFilters();
                                });
                              },
                              selectedColor: const Color(0xFF10B981),
                              backgroundColor: Colors.grey[200],
                              labelStyle: TextStyle(
                                color: filterPayment == payment
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}