import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

class SimpleForecastingScreen extends StatefulWidget {
  final String barcode;
  final String productName;
  final int currentStock;

  const SimpleForecastingScreen({
    super.key,
    required this.barcode,
    required this.productName,
    required this.currentStock,
  });

  @override
  State<SimpleForecastingScreen> createState() =>
      _SimpleForecastingScreenState();
}

class _SimpleForecastingScreenState extends State<SimpleForecastingScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  int selectedDays = 7; // 7, 14, or 30 days

  // Historical Data
  List<DailySale> historicalSales = [];
  Map<int, double> weekdayAverage = {};
  
  // Forecasting Results
  List<ForecastDay> forecast = [];
  double avgDailySales = 0;
  double trendDirection = 0; // positive = increasing, negative = decreasing
  int estimatedStockAfterForecast = 0;
  int daysUntilStockout = 0;
  
  // Insights
  int bestSellingDay = 1;
  int worstSellingDay = 1;
  double salesGrowth = 0;
  bool isStockCritical = false;

  @override
  void initState() {
    super.initState();
    loadSalesData();
  }

  // ======================== DATA LOADING =====================================

  Future<void> loadSalesData() async {
    setState(() => loading = true);

    try {
      final today = DateTime.now();
      final fromDate = today.subtract(const Duration(days: 90));

      final data = await supabase
          .from('bill_items_with_date')
          .select('qty, created_at')
          .eq('barcode', widget.barcode)
          .gte('created_at', fromDate.toIso8601String())
          .order('created_at', ascending: true);

      // Group by date
      final Map<String, int> grouped = {};
      for (var row in data) {
        final date = DateTime.parse(row['created_at']);
        final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        final qty = (row['qty'] as num).toInt();
        grouped[dateStr] = (grouped[dateStr] ?? 0) + qty;
      }

      // Fill in missing dates with 0
      historicalSales = [];
      DateTime current = fromDate;
      while (current.isBefore(today) || current.isAtSameMomentAs(today)) {
        final dateStr = "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}";
        historicalSales.add(DailySale(
          date: current,
          quantity: grouped[dateStr] ?? 0,
        ));
        current = current.add(const Duration(days: 1));
      }

      calculateForecast();
      calculateInsights();
    } catch (e) {
      print('Error loading sales data: $e');
    }

    setState(() => loading = false);
  }

  // ======================== FORECASTING ======================================

  void calculateForecast() {
    if (historicalSales.isEmpty) return;

    // Calculate weekday patterns
    Map<int, List<int>> weekdaySales = {};
    for (var sale in historicalSales) {
      final weekday = sale.date.weekday;
      weekdaySales.putIfAbsent(weekday, () => []);
      weekdaySales[weekday]!.add(sale.quantity);
    }

    weekdayAverage = {};
    weekdaySales.forEach((weekday, sales) {
      if (sales.isNotEmpty) {
        weekdayAverage[weekday] = sales.reduce((a, b) => a + b) / sales.length;
      }
    });

    // Calculate overall average (last 30 days)
    final recent30Days = historicalSales.length >= 30
        ? historicalSales.sublist(historicalSales.length - 30)
        : historicalSales;
    avgDailySales = recent30Days.fold(0, (sum, sale) => sum + sale.quantity) /
        recent30Days.length;

    // Calculate trend (compare last 14 days vs previous 14 days)
    if (historicalSales.length >= 28) {
      final last14 = historicalSales.sublist(historicalSales.length - 14);
      final prev14 = historicalSales.sublist(
          historicalSales.length - 28, historicalSales.length - 14);
      
      final last14Avg = last14.fold(0, (sum, s) => sum + s.quantity) / 14;
      final prev14Avg = prev14.fold(0, (sum, s) => sum + s.quantity) / 14;
      
      trendDirection = last14Avg - prev14Avg;
    }

    // Generate forecast
    forecast = [];
    DateTime lastDate = historicalSales.last.date;
    int runningStock = widget.currentStock;
    bool stockoutFound = false;

    for (int i = 1; i <= selectedDays; i++) {
      final forecastDate = lastDate.add(Duration(days: i));
      
      // Use weekday average if available, otherwise use overall average
      double predicted = weekdayAverage[forecastDate.weekday] ?? avgDailySales;
      
      // Apply trend adjustment (small influence)
      predicted = predicted + (trendDirection * 0.1);
      predicted = math.max(0, predicted);

      // Update running stock
      runningStock = math.max(0, runningStock - predicted.round());

      // Track days until stockout
      if (!stockoutFound && runningStock == 0) {
        daysUntilStockout = i;
        stockoutFound = true;
      }

      forecast.add(ForecastDay(
        date: forecastDate,
        predictedSales: predicted,
        estimatedStock: runningStock,
      ));
    }

    if (!stockoutFound) {
      daysUntilStockout = selectedDays + 1; // More than forecast period
    }

    estimatedStockAfterForecast = runningStock;
  }

  void calculateInsights() {
    // Find best and worst selling days
    if (weekdayAverage.isNotEmpty) {
      var sorted = weekdayAverage.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      bestSellingDay = sorted.first.key;
      worstSellingDay = sorted.last.key;
    }

    // Calculate sales growth rate
    if (historicalSales.length >= 60) {
      final last30 = historicalSales.sublist(historicalSales.length - 30);
      final prev30 = historicalSales.sublist(
          historicalSales.length - 60, historicalSales.length - 30);
      
      final last30Total = last30.fold(0, (sum, s) => sum + s.quantity);
      final prev30Total = prev30.fold(0, (sum, s) => sum + s.quantity);
      
      if (prev30Total > 0) {
        salesGrowth = ((last30Total - prev30Total) / prev30Total) * 100;
      }
    }

    // Check if stock is critical
    isStockCritical = daysUntilStockout <= 7;
  }

  String _weekdayName(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  String _weekdayShort(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  // ============================= UI ==========================================

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Forecast',
              style: TextStyle(
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.productName,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.date_range, color: Color(0xFF6366F1)),
            onSelected: (value) {
              setState(() {
                selectedDays = value;
                calculateForecast();
                calculateInsights();
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 7,
                child: Row(
                  children: [
                    if (selectedDays == 7)
                      const Icon(Icons.check, size: 16, color: Color(0xFF6366F1)),
                    if (selectedDays == 7) const SizedBox(width: 8),
                    const Text('7 Days'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 14,
                child: Row(
                  children: [
                    if (selectedDays == 14)
                      const Icon(Icons.check, size: 16, color: Color(0xFF6366F1)),
                    if (selectedDays == 14) const SizedBox(width: 8),
                    const Text('14 Days'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 30,
                child: Row(
                  children: [
                    if (selectedDays == 30)
                      const Icon(Icons.check, size: 16, color: Color(0xFF6366F1)),
                    if (selectedDays == 30) const SizedBox(width: 8),
                    const Text('30 Days'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadSalesData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Critical Alert
                    if (isStockCritical) _criticalAlert(),
                    if (isStockCritical) const SizedBox(height: 16),

                    // Summary Cards
                    _summaryCards(),
                    const SizedBox(height: 24),

                    // Stock Projection Chart
                    _sectionTitle('Stock Level Projection ($selectedDays Days)'),
                    const SizedBox(height: 12),
                    _stockLevelChart(),
                    const SizedBox(height: 24),

                    // Forecast Metrics
                    _forecastMetrics(),
                    const SizedBox(height: 24),

                    // Weekly Pattern
                    if (weekdayAverage.isNotEmpty) ...[
                      _sectionTitle('Weekly Sales Pattern'),
                      const SizedBox(height: 12),
                      _weeklyPatternChart(),
                      const SizedBox(height: 24),
                    ],

                    // Sales History
                    _sectionTitle('Recent Sales History'),
                    const SizedBox(height: 12),
                    _historicalChart(),
                    const SizedBox(height: 24),

                    // Forecast Table
                    _sectionTitle('Detailed Forecast'),
                    const SizedBox(height: 12),
                    _forecastTable(),
                    const SizedBox(height: 24),

                    // Recommendations
                    _sectionTitle('Smart Recommendations'),
                    const SizedBox(height: 12),
                    _recommendations(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _criticalAlert() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning, color: Colors.red, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Critical Stock Alert',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  daysUntilStockout == 0
                      ? 'Stock will deplete today!'
                      : 'Stock will deplete in $daysUntilStockout day${daysUntilStockout == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                'Current Stock',
                widget.currentStock.toString(),
                Icons.inventory_2,
                const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                'Avg Daily Sales',
                avgDailySales.toStringAsFixed(1),
                Icons.shopping_cart,
                const Color(0xFF10B981),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _summaryCard(
                'Stock After $selectedDays Days',
                estimatedStockAfterForecast.toString(),
                Icons.schedule,
                estimatedStockAfterForecast < 10 
                    ? const Color(0xFFEF4444) 
                    : const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                'Days to Stockout',
                daysUntilStockout > selectedDays ? '$selectedDays+' : daysUntilStockout.toString(),
                Icons.timer,
                daysUntilStockout <= 7 
                    ? const Color(0xFFEF4444) 
                    : const Color(0xFF10B981),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
            child: Icon(icon, color: color, size: 20),
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
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockLevelChart() {
    if (forecast.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('No forecast data available'),
      );
    }

    List<FlSpot> spots = [
      FlSpot(0, widget.currentStock.toDouble()),
      ...forecast.asMap().entries.map(
        (e) => FlSpot((e.key + 1).toDouble(), e.value.estimatedStock.toDouble()),
      ),
    ];

    return Container(
      height: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: widget.currentStock > 50 ? 10 : 5,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[200]!,
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
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: selectedDays > 14 ? 5 : 2,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() == 0) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Now', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'D${value.toInt()}',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF6366F1),
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 3,
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
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toInt()} units',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _forecastMetrics() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _metricRow(
            'Total Forecast Sales',
            '${forecast.fold(0.0, (sum, f) => sum + f.predictedSales).toStringAsFixed(0)} units',
            Icons.trending_up,
            const Color(0xFFEC4899),
          ),
          const Divider(height: 24),
          _metricRow(
            'Sales Trend',
            trendDirection > 0.5 
                ? '📈 Growing (+${trendDirection.toStringAsFixed(1)}/day)'
                : trendDirection < -0.5
                    ? '📉 Declining (${trendDirection.toStringAsFixed(1)}/day)'
                    : '➡️ Stable',
            Icons.show_chart,
            trendDirection > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
          if (salesGrowth != 0) ...[
            const Divider(height: 24),
            _metricRow(
              'Sales Growth (30 days)',
              '${salesGrowth > 0 ? '+' : ''}${salesGrowth.toStringAsFixed(1)}%',
              Icons.auto_graph,
              salesGrowth > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _weeklyPatternChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: weekdayAverage.values.reduce(math.max) * 1.2,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                  if (value.toInt() >= 0 && value.toInt() < days.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        days[value.toInt()],
                        style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 2,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[200]!,
                strokeWidth: 1,
              );
            },
          ),
          barGroups: weekdayAverage.entries.map((entry) {
            final isBest = entry.key == bestSellingDay;
            return BarChartGroupData(
              x: entry.key - 1,
              barRods: [
                BarChartRodData(
                  toY: entry.value,
                  color: isBest ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                  width: 32,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _historicalChart() {
  if (historicalSales.isEmpty) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('No sales data available'),
    );
  }

  // Show last 60 days
  final displaySales = historicalSales.length >= 60
      ? historicalSales.sublist(historicalSales.length - 60)
      : historicalSales;

  return Container(
    height: 220,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey[200]!,
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
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: displaySales.length / 4,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < displaySales.length) {
                  final date = displaySales[value.toInt()].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${date.month}/${date.day}',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: displaySales
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.quantity.toDouble()))
                .toList(),
            isCurved: true,
            color: const Color(0xFF10B981),
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF10B981).withOpacity(0.3),
                  const Color(0xFF10B981).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                if (index >= 0 && index < displaySales.length) {
                  final sale = displaySales[index];
                  return LineTooltipItem(
                    '${sale.date.month}/${sale.date.day}\n${spot.y.toInt()} units',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }
                return null;
              }).toList();
            },
          ),
        ),
      ),
    ),
  );
}

  Widget _forecastTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(child: Text('Sales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                Expanded(child: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right)),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: forecast.length,
              itemBuilder: (context, index) {
                final f = forecast[index];
                final isLowStock = f.estimatedStock < 10;
                final isStockout = f.estimatedStock == 0;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isStockout
                        ? Colors.red.withOpacity(0.08)
                        : isLowStock
                            ? Colors.orange.withOpacity(0.08)
                            : null,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey[200]!,
                        width: index == forecast.length - 1 ? 0 : 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${f.date.day} ${_getMonthName(f.date.month)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _weekdayShort(f.date.weekday),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          f.predictedSales.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFEC4899),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isStockout)
                              const Icon(Icons.error, size: 16, color: Colors.red),
                            if (isStockout) const SizedBox(width: 4),
                            Text(
                              f.estimatedStock.toString(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isStockout
                                    ? Colors.red
                                    : isLowStock
                                        ? Colors.orange
                                        : const Color(0xFF6366F1),
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendations() {
    List<Widget> recs = [];

    // Stockout warning
    if (daysUntilStockout <= 7) {
      final urgency = daysUntilStockout <= 3 ? 'URGENT' : 'Important';
      recs.add(_recommendationCard(
        urgency,
        'Restock Immediately',
        'Stock will run out in $daysUntilStockout day${daysUntilStockout == 1 ? '' : 's'}. Order now to avoid stockout.',
        Icons.error,
        Colors.red,
      ));
    } else if (daysUntilStockout <= 14) {
      recs.add(_recommendationCard(
        'Plan Ahead',
        'Restock Soon',
        'Stock sufficient for $daysUntilStockout days. Consider ordering within the week.',
        Icons.schedule,
        Colors.orange,
      ));
    }

    // Trend recommendations
    if (trendDirection > 1) {
      recs.add(_recommendationCard(
        'Growth Alert',
        'Demand Increasing',
        'Sales are trending upward. Consider increasing order quantities.',
        Icons.trending_up,
        const Color(0xFF10B981),
      ));
    } else if (trendDirection < -1) {
      recs.add(_recommendationCard(
        'Slow Sales',
        'Demand Decreasing',
        'Sales are declining. Monitor closely and adjust inventory.',
        Icons.trending_down,
        const Color(0xFF6B7280),
      ));
    }

    // Weekly pattern recommendation
    if (weekdayAverage.isNotEmpty && weekdayAverage.length >= 7) {
      final bestDay = _weekdayName(bestSellingDay);
      final worstDay = _weekdayName(worstSellingDay);
      recs.add(_recommendationCard(
        'Sales Pattern',
        'Weekly Insights',
        'Peak sales on $bestDay. Lowest on $worstDay. Stock accordingly.',
        Icons.calendar_today,
        const Color(0xFF6366F1),
      ));
    }

    // Optimal order suggestion
    final totalForecast = forecast.fold(0.0, (sum, f) => sum + f.predictedSales);
    final suggestedOrder = (totalForecast * 1.2).round(); // 20% buffer
    if (estimatedStockAfterForecast < 20) {
      recs.add(_recommendationCard(
        'Order Suggestion',
        'Recommended Order',
        'Order approximately $suggestedOrder units to cover $selectedDays days + safety buffer.',
        Icons.shopping_bag,
        const Color(0xFFEC4899),
      ));
    }

    if (recs.isEmpty) {
      recs.add(_recommendationCard(
        'All Good',
        'Stock Levels Healthy',
        'Your inventory is well-stocked. Continue monitoring regularly.',
        Icons.check_circle,
        const Color(0xFF10B981),
      ));
    }

    return Column(children: recs);
  }

  Widget _recommendationCard(
    String badge,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1F2937),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}

// ======================== DATA MODELS ========================================

class DailySale {
  final DateTime date;
  final int quantity;

  DailySale({required this.date, required this.quantity});
}

class ForecastDay {
  final DateTime date;
  final double predictedSales;
  final int estimatedStock;

  ForecastDay({
    required this.date,
    required this.predictedSales,
    required this.estimatedStock,
  });
}