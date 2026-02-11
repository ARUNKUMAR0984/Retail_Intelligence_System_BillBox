import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  String selectedPeriod = 'Last 7 Days';
  late TabController _tabController;

  // Core Analytics Data
  List<Map<String, dynamic>> dailySales = [];
  List<Map<String, dynamic>> monthlySales = [];
  Map<String, double> paymentSplit = {};
  List<Map<String, dynamic>> topProducts = [];
  
  // Advanced Metrics
  double totalRevenue = 0;
  double avgOrderValue = 0;
  int totalOrders = 0;
  int totalProducts = 0;
  double revenueGrowth = 0;
  int lowStockCount = 0;
  double todayRevenue = 0;
  int todayOrders = 0;
  
  // Hourly data for peak hours
  Map<int, double> hourlyRevenue = {};
  
  // Category performance
  Map<String, int> categoryPerformance = {};
  
  // Inventory insights
  double inventoryValue = 0;
  int outOfStockItems = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    loadAnalytics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  Future<void> loadAnalytics() async {
    setState(() => isLoading = true);

    try {
      final shopId = await getShopId();

      // Load RPC functions with error handling
      final daily = await supabase.rpc("daily_sales", params: {"shopid": shopId});
      final monthly = await supabase.rpc("monthly_sales", params: {"shopid": shopId});
      final split = await supabase.rpc("payment_split", params: {"shopid": shopId});
      final products = await supabase.rpc("top_products", params: {"shopid": shopId});

      // Load bills with items for advanced analysis
      final bills = await supabase
          .from('bills')
          .select('id, total, created_at, payment_method')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      // Load inventory with product details
      final inventory = await supabase
          .from('inventory')
          .select('stock_qty, selling_price, master_products(product_name, brand)')
          .eq('shop_id', shopId);

      // Calculate core metrics with null safety
      totalRevenue = bills.fold(0.0, (sum, bill) {
        final total = bill['total'];
        if (total == null) return sum;
        return sum + (total as num).toDouble();
      });
      
      totalOrders = bills.length;
      avgOrderValue = totalOrders > 0 ? totalRevenue / totalOrders : 0;
      totalProducts = inventory.length;
      
      // Calculate inventory metrics with null safety
      inventoryValue = inventory.fold(0.0, (sum, item) {
        try {
          final qty = item['stock_qty'];
          final price = item['selling_price'];
          if (qty == null || price == null) return sum;
          return sum + ((qty as int) * (price as num).toDouble());
        } catch (e) {
          return sum;
        }
      });
      
      lowStockCount = inventory.where((item) {
        final qty = item['stock_qty'];
        if (qty == null) return false;
        final stockQty = qty as int;
        return stockQty < 10 && stockQty > 0;
      }).length;
      
      outOfStockItems = inventory.where((item) {
        final qty = item['stock_qty'];
        if (qty == null) return false;
        return (qty as int) == 0;
      }).length;

      // Calculate today's metrics with null safety
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      final todayBills = bills.where((b) {
        final createdAt = b['created_at'];
        if (createdAt == null) return false;
        try {
          return DateTime.parse(createdAt.toString()).isAfter(todayStart);
        } catch (e) {
          return false;
        }
      }).toList();
      
      todayRevenue = todayBills.fold(0.0, (sum, bill) {
        final total = bill['total'];
        if (total == null) return sum;
        return sum + (total as num).toDouble();
      });
      
      todayOrders = todayBills.length;

      // Calculate hourly revenue for today with null safety
      hourlyRevenue = {};
      for (var bill in todayBills) {
        try {
          final createdAt = bill['created_at'];
          final total = bill['total'];
          if (createdAt == null || total == null) continue;
          
          final hour = DateTime.parse(createdAt.toString()).hour;
          hourlyRevenue[hour] = (hourlyRevenue[hour] ?? 0) + (total as num).toDouble();
        } catch (e) {
          continue;
        }
      }

      // Calculate growth (last 7 days vs previous 7 days) with null safety
      final last7Days = today.subtract(const Duration(days: 7));
      final previous7Days = today.subtract(const Duration(days: 14));

      final recentRevenue = bills.where((b) {
        final createdAt = b['created_at'];
        if (createdAt == null) return false;
        try {
          return DateTime.parse(createdAt.toString()).isAfter(last7Days);
        } catch (e) {
          return false;
        }
      }).fold(0.0, (sum, bill) {
        final total = bill['total'];
        if (total == null) return sum;
        return sum + (total as num).toDouble();
      });

      final previousRevenue = bills.where((b) {
        final createdAt = b['created_at'];
        if (createdAt == null) return false;
        try {
          final date = DateTime.parse(createdAt.toString());
          return date.isAfter(previous7Days) && date.isBefore(last7Days);
        } catch (e) {
          return false;
        }
      }).fold(0.0, (sum, bill) {
        final total = bill['total'];
        if (total == null) return sum;
        return sum + (total as num).toDouble();
      });

      revenueGrowth = previousRevenue > 0 
          ? ((recentRevenue - previousRevenue) / previousRevenue * 100)
          : 0;

      setState(() {
        dailySales = List<Map<String, dynamic>>.from(daily ?? []);
        monthlySales = List<Map<String, dynamic>>.from(monthly ?? []);
        paymentSplit = {
          for (var x in (split ?? [])) 
            (x["payment_method"]?.toString() ?? 'Unknown'): (x["amount"] as num?)?.toDouble() ?? 0.0,
        };
        topProducts = List<Map<String, dynamic>>.from(products ?? []);
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Error loading analytics: ${e.toString()}');
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

  String _formatCurrency(double amount) {
    if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amount.toStringAsFixed(0)}';
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
          "Analytics Dashboard",
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
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.refresh,
                color: Color(0xFF6366F1),
                size: 22,
              ),
            ),
            onPressed: loadAnalytics,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Overview Section
                    _buildOverviewSection(),
                    const SizedBox(height: 8),

                    // Today's Performance
                    _buildTodaySection(),
                    const SizedBox(height: 8),

                    // Tab Navigation
                    Container(
                      color: Colors.white,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF6366F1),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF6366F1),
                        indicatorWeight: 3,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        tabs: const [
                          Tab(icon: Icon(Icons.trending_up), text: 'Revenue'),
                          Tab(icon: Icon(Icons.inventory_2), text: 'Inventory'),
                          Tab(icon: Icon(Icons.payment), text: 'Payments'),
                          Tab(icon: Icon(Icons.star), text: 'Products'),
                        ],
                      ),
                    ),

                    // Tab Content
                    SizedBox(
                      height: 700,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRevenueTab(),
                          _buildInventoryTab(),
                          _buildPaymentTab(),
                          _buildProductsTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOverviewSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Business Overview',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    'Last 7 days performance',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: revenueGrowth >= 0 
                      ? const Color(0xFF10B981).withOpacity(0.1)
                      : const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      revenueGrowth >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 18,
                      color: revenueGrowth >= 0 
                          ? const Color(0xFF10B981) 
                          : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${revenueGrowth.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: revenueGrowth >= 0 
                            ? const Color(0xFF10B981) 
                            : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Revenue',
                  _formatCurrency(totalRevenue),
                  Icons.currency_rupee,
                  const Color(0xFF10B981),
                  '₹${totalRevenue.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'Total Orders',
                  totalOrders.toString(),
                  Icons.shopping_cart_outlined,
                  const Color(0xFF6366F1),
                  '$totalOrders bills',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Avg Order',
                  _formatCurrency(avgOrderValue),
                  Icons.analytics_outlined,
                  const Color(0xFFF59E0B),
                  '₹${avgOrderValue.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  'Inventory Value',
                  _formatCurrency(inventoryValue),
                  Icons.inventory_2_outlined,
                  const Color(0xFF8B5CF6),
                  '₹${inventoryValue.toStringAsFixed(2)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.today,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "Today's Performance",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revenue',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${todayRevenue.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orders',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        todayOrders.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Daily Revenue Trend', Icons.show_chart),
          const SizedBox(height: 16),
          _buildDailyChart(),
          const SizedBox(height: 24),
          _buildSectionHeader('Monthly Performance', Icons.calendar_today),
          const SizedBox(height: 16),
          _buildMonthlyChart(),
          const SizedBox(height: 24),
          _buildSectionHeader('Peak Hours Today', Icons.access_time),
          const SizedBox(height: 16),
          _buildHourlyChart(),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Total Products',
                  totalProducts.toString(),
                  Icons.inventory_2,
                  const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  'Low Stock',
                  lowStockCount.toString(),
                  Icons.warning_amber,
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Out of Stock',
                  outOfStockItems.toString(),
                  Icons.remove_shopping_cart,
                  const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  'Stock Value',
                  _formatCurrency(inventoryValue),
                  Icons.attach_money,
                  const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Stock Status', Icons.pie_chart),
          const SizedBox(height: 16),
          _buildStockStatusChart(),
        ],
      ),
    );
  }

  Widget _buildPaymentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Payment Distribution', Icons.pie_chart),
          const SizedBox(height: 16),
          _buildPaymentSplitChart(),
          const SizedBox(height: 24),
          _buildSectionHeader('Payment Breakdown', Icons.analytics),
          const SizedBox(height: 16),
          _buildPaymentBreakdown(),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Top Selling Products', Icons.star),
          const SizedBox(height: 16),
          _buildTopProductsList(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF6366F1), size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyChart() {
    if (dailySales.isEmpty) {
      return _buildEmptyState('No daily sales data available');
    }

    final spots = dailySales.asMap().entries.map((entry) {
      final revenue = entry.value["revenue"];
      return FlSpot(
        entry.key.toDouble(),
        revenue != null ? (revenue as num).toDouble() : 0.0,
      );
    }).toList();

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[200],
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatCurrency(value),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= dailySales.length) return const Text('');
                  final date = dailySales[value.toInt()]['sale_date'];
                  if (date == null) return const Text('');
                  try {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat('dd/MM').format(DateTime.parse(date.toString())),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                    );
                  } catch (e) {
                    return const Text('');
                  }
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF6366F1),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.white,
                    strokeWidth: 2,
                    strokeColor: const Color(0xFF6366F1),
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.3),
                    const Color(0xFF6366F1).withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyChart() {
    if (monthlySales.isEmpty) {
      return _buildEmptyState('No monthly sales data available');
    }

    final maxRevenue = monthlySales.fold<double>(0, (max, e) {
      final revenue = e["revenue"];
      if (revenue == null) return max;
      final val = (revenue as num).toDouble();
      return val > max ? val : max;
    });

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxRevenue * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1F2937),

              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '₹${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatCurrency(value),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= monthlySales.length) return const Text('');
                  final month = monthlySales[value.toInt()]['sale_month'];
                  if (month == null) return const Text('');
                  try {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat('MMM').format(DateTime.parse('${month.toString()}-01')),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 10,
                        ),
                      ),
                    );
                  } catch (e) {
                    return const Text('');
                  }
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[200],
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          barGroups: monthlySales.asMap().entries.map((entry) {
            final revenue = entry.value["revenue"];
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: revenue != null ? (revenue as num).toDouble() : 0.0,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: 24,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHourlyChart() {
    if (hourlyRevenue.isEmpty) {
      return _buildEmptyState('No sales today yet');
    }

    final sortedHours = hourlyRevenue.keys.toList()..sort();
    final maxRevenue = hourlyRevenue.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: sortedHours.map((hour) {
          final revenue = hourlyRevenue[hour]!;
          final percentage = (revenue / maxRevenue);
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    DateFormat('ha').format(DateTime(2024, 1, 1, hour)),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: percentage,
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '₹${revenue.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
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
        }).toList(),
      ),
    );
  }

  Widget _buildStockStatusChart() {
    final inStock = totalProducts - lowStockCount - outOfStockItems;
    final total = totalProducts.toDouble();

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: [
                  PieChartSectionData(
                    value: inStock.toDouble(),
                    title: '${(inStock / total * 100).toStringAsFixed(1)}%',
                    color: const Color(0xFF10B981),
                    radius: 60,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    value: lowStockCount.toDouble(),
                    title: '${(lowStockCount / total * 100).toStringAsFixed(1)}%',
                    color: const Color(0xFFF59E0B),
                    radius: 60,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  PieChartSectionData(
                    value: outOfStockItems.toDouble(),
                    title: '${(outOfStockItems / total * 100).toStringAsFixed(1)}%',
                    color: const Color(0xFFEF4444),
                    radius: 60,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem('In Stock', inStock, const Color(0xFF10B981)),
                const SizedBox(height: 12),
                _buildLegendItem('Low Stock', lowStockCount, const Color(0xFFF59E0B)),
                const SizedBox(height: 12),
                _buildLegendItem('Out of Stock', outOfStockItems, const Color(0xFFEF4444)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int value, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$value items',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSplitChart() {
    if (paymentSplit.isEmpty) {
      return _buildEmptyState('No payment data available');
    }

    final total = paymentSplit.values.fold(0.0, (sum, value) => sum + value);
    final colors = {
      'Cash': const Color(0xFF10B981),
      'UPI': const Color(0xFF6366F1),
      'Card': const Color(0xFFF59E0B),
    };

    return Container(
      height: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: paymentSplit.entries.map((entry) {
                  final percentage = (entry.value / total * 100).toStringAsFixed(1);
                  return PieChartSectionData(
                    value: entry.value,
                    title: '$percentage%',
                    color: colors[entry.key] ?? Colors.grey,
                    radius: 65,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: paymentSplit.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colors[entry.key] ?? Colors.grey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₹${entry.value.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdown() {
    if (paymentSplit.isEmpty) return const SizedBox();

    final total = paymentSplit.values.fold(0.0, (sum, value) => sum + value);

    return Column(
      children: paymentSplit.entries.map((entry) {
        final percentage = (entry.value / total * 100);
        final icons = {
          'Cash': Icons.money,
          'UPI': Icons.qr_code,
          'Card': Icons.credit_card,
        };
        final colors = {
          'Cash': const Color(0xFF10B981),
          'UPI': const Color(0xFF6366F1),
          'Card': const Color(0xFFF59E0B),
        };

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors[entry.key]!.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icons[entry.key]!,
                  color: colors[entry.key]!,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${entry.value.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors[entry.key]!,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 80,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: percentage / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors[entry.key]!,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTopProductsList() {
    if (topProducts.isEmpty) {
      return _buildEmptyState('No product data available');
    }

    return Column(
      children: topProducts.asMap().entries.map((entry) {
        final index = entry.key;
        final product = entry.value;
        
        final colors = [
          const Color(0xFFFFD700), // Gold
          const Color(0xFFC0C0C0), // Silver
          const Color(0xFFCD7F32), // Bronze
        ];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: index < 3 
                  ? colors[index].withOpacity(0.3) 
                  : Colors.grey[200]!,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: index < 3 
                      ? colors[index].withOpacity(0.2)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: index < 3
                      ? Icon(
                          Icons.emoji_events,
                          color: colors[index],
                          size: 24,
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['product_name'] ?? 'Unknown Product',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sold: ${product['sold_qty']} units',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${product['sold_qty']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}