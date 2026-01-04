import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/layouts/authenticated.layout.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedLayout(
      body: Center(
        child: Column(
          children: [
            Text(
              'Welcome home!',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 24),
            const Expanded(child: _GraphQLQueryWidget()),
          ],
        ),
      ),
    );
  }
}

/// Widget that makes a GraphQL query and displays the result as JSON.
///
/// This is a POC widget for testing GraphQL queries.
/// Update the query and variables as needed for your use case.
class _GraphQLQueryWidget extends StatelessWidget {
  const _GraphQLQueryWidget();

  // Example query - update this with your actual GraphQL query
  static const String _query = '''
    query {
      invoices (limit: 20, order_by: {createdAt: desc}) {
        id
        num
        createdAt
        grandTotal
        partner {
          id
          company_name_i18n(args: {field: "company_name"})
        }
      }
    }
  ''';

  @override
  Widget build(BuildContext context) {
    return Query(
      options: QueryOptions(
        document: gql(_query),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
      builder:
          (QueryResult result, {VoidCallback? refetch, FetchMore? fetchMore}) {
            if (result.isLoading) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading GraphQL query...'),
                  ],
                ),
              );
            }

            if (result.hasException) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.exception.toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => refetch?.call(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'GraphQL Response',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        onPressed: () => refetch?.call(),
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _buildLineChart(context, result.data),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const <DataColumn>[
                          DataColumn(label: Text('ID')),
                          DataColumn(label: Text('Number')),
                          DataColumn(label: Text('Grand Total')),
                          DataColumn(label: Text('Partner')),
                          DataColumn(label: Text('Created At')),
                        ],
                        rows: _buildDataRows(result.data),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }

  /// Builds DataRow list from GraphQL response data.
  List<DataRow> _buildDataRows(Map<String, dynamic>? data) {
    if (data == null) return [];

    final invoices = data['invoices'];
    if (invoices == null || invoices is! List) return [];

    return invoices
        .cast<Map<String, dynamic>>()
        .map(
          (invoice) => DataRow(
            cells: [
              DataCell(Text(invoice['id']?.toString() ?? '')),
              DataCell(Text(invoice['num']?.toString() ?? '')),
              DataCell(Text(invoice['grandTotal']?.toString() ?? '')),
              DataCell(
                Text(
                  invoice['partner']?['company_name_i18n']?.toString() ?? '',
                ),
              ),
              DataCell(Text(DateTime.parse(invoice['createdAt']).toString())),
            ],
          ),
        )
        .toList();
  }

  /// Builds LineChart widget from GraphQL response data.
  ///
  /// Groups invoices by date and sums grandTotal for each date.
  Widget _buildLineChart(BuildContext context, Map<String, dynamic>? data) {
    if (data == null) {
      return const Center(child: Text('No data available'));
    }

    final invoices = data['invoices'];
    if (invoices == null || invoices is! List || invoices.isEmpty) {
      return const Center(child: Text('No invoices found'));
    }

    // Process invoices: group by date and sum grandTotal
    final Map<String, double> dateTotals = {};

    for (final invoice in invoices.cast<Map<String, dynamic>>()) {
      try {
        final createdAt = invoice['createdAt']?.toString();
        final grandTotal = invoice['grandTotal'];

        if (createdAt != null && grandTotal != null) {
          // Parse date and get just the date part (YYYY-MM-DD)
          final date = DateTime.parse(createdAt);
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

          // Sum grandTotal for this date
          final total = (grandTotal is num)
              ? grandTotal.toDouble()
              : double.tryParse(grandTotal.toString()) ?? 0.0;
          dateTotals[dateKey] = (dateTotals[dateKey] ?? 0.0) + total;
        }
      } catch (e) {
        // Skip invalid entries
        continue;
      }
    }

    if (dateTotals.isEmpty) {
      return const Center(child: Text('No valid invoice data'));
    }

    // Sort by date
    final sortedDates = dateTotals.keys.toList()..sort();

    // Create spots for the line chart
    final spots = sortedDates.asMap().entries.map((entry) {
      final index = entry.key.toDouble();
      final total = dateTotals[entry.value]!;
      return FlSpot(index, total);
    }).toList();

    if (spots.isEmpty) {
      return const Center(child: Text('No data points available'));
    }

    // Find min/max for proper scaling
    final maxY = spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    final minY = spots.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    final yInterval = ((maxY - minY) / 5).ceil().toDouble();
    final maxYValue = (maxY + yInterval).ceilToDouble();
    final minYValue = ((minY - yInterval).floorToDouble()).clamp(
      0.0,
      double.infinity,
    );

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval > 0 ? yInterval : null,
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < sortedDates.length) {
                  final dateStr = sortedDates[value.toInt()];
                  // Format date for display (e.g., "2024-01-15" -> "01/15")
                  final parts = dateStr.split('-');
                  if (parts.length == 3) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '${parts[1]}/${parts[2]}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                        ),
                      ),
                    );
                  }
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10, color: Colors.green),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: minYValue,
        maxY: maxYValue,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            // color: Theme.of(context).colorScheme.primary,
            color: Colors.green,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: false,
              // color: Theme.of(
              //   context,
              // ).colorScheme.secondary.withValues(alpha: 0.1),
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}
