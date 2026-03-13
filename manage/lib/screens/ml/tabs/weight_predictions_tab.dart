import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/theme.dart';
import '../../../models/ml_models.dart';
import '../../../providers/ml_analytics_provider.dart';
import '../widgets/widgets.dart';

class WeightPredictionsTab extends ConsumerStatefulWidget {
  const WeightPredictionsTab({super.key});

  @override
  ConsumerState<WeightPredictionsTab> createState() =>
      _WeightPredictionsTabState();
}

class _WeightPredictionsTabState extends ConsumerState<WeightPredictionsTab> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mlState = ref.watch(mlAnalyticsProvider);
    final predictions = mlState.predictions;
    final selectedHorizon = mlState.selectedHorizon;

    if (mlState.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.farmGreen),
            const SizedBox(height: 16),
            Text(
              'Loading predictions from ML API...',
              style: GoogleFonts.inter(
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      );
    }

    if (mlState.error != null && predictions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Unable to Load Predictions',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.titleMedium?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                mlState.error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(mlAnalyticsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.farmGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build chart data from predictions
    final chartData = _buildChartData(predictions, selectedHorizon.days);

    return RefreshIndicator(
      onRefresh: () async => ref.read(mlAnalyticsProvider.notifier).refresh(),
      color: AppTheme.farmGreen,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHorizonSelector(theme, isDark, selectedHorizon),
          const SizedBox(height: 16),
          if (mlState.isConnected) _buildConnectionBadge(theme, isDark),
          const SizedBox(height: 8),
          if (chartData.isNotEmpty) ...[
            _buildChartSection(theme, isDark, chartData),
            const SizedBox(height: 24),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Individual Predictions',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.textTheme.titleLarge?.color,
                ),
              ),
              Text(
                '${predictions.length} animals',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (predictions.isEmpty)
            _buildEmptyState(theme)
          else
            ...predictions.map((p) => _buildPredictionCard(p, theme, isDark)),
        ],
      ),
    );
  }

  Widget _buildConnectionBadge(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.farmGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.farmGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Live predictions from ML API',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.farmGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.analytics_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No predictions yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.titleMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add animals with weight records to see weight predictions.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: theme.textTheme.bodyMedium?.color),
          ),
        ],
      ),
    );
  }

  List<GrowthDataPoint> _buildChartData(
    List<WeightPrediction> predictions,
    int horizonDays,
  ) {
    if (predictions.isEmpty) return [];

    // Use the first animal's data for the chart as a representative
    final representative = predictions.first;
    final now = DateTime.now();
    final points = <GrowthDataPoint>[];

    // Show current weight as a reference point
    points.add(
      GrowthDataPoint(
        date: now,
        weight: representative.currentWeight,
        isPredicted: false,
      ),
    );

    // Show predicted weight at horizon
    points.add(
      GrowthDataPoint(
        date: now.add(Duration(days: horizonDays)),
        weight: representative.predictedWeight,
        isPredicted: true,
      ),
    );

    // Add bounds as interpolated points
    final midDate = now.add(Duration(days: horizonDays ~/ 2));
    final midWeight =
        representative.currentWeight +
        (representative.predictedWeight - representative.currentWeight) / 2;
    points.insert(
      1,
      GrowthDataPoint(date: midDate, weight: midWeight, isPredicted: true),
    );

    return points;
  }

  Widget _buildHorizonSelector(
    ThemeData theme,
    bool isDark,
    ForecastHorizon selectedHorizon,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: ForecastHorizon.values.map((horizon) {
          final isSelected = selectedHorizon == horizon;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref
                    .read(mlAnalyticsProvider.notifier)
                    .setForecastHorizon(horizon);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? theme.colorScheme.surface : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  '${horizon.days} Days',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.farmGreen
                        : theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChartSection(
    ThemeData theme,
    bool isDark,
    List<GrowthDataPoint> chartData,
  ) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Growth Trajectory',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: theme.textTheme.titleMedium?.color,
                ),
              ),
              Row(
                children: [
                  _legendItem('Actual', Colors.blue, theme),
                  const SizedBox(width: 12),
                  _legendItem('Predicted', AppTheme.farmGreen, theme),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: GrowthChart(dataPoints: chartData)),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionCard(
    WeightPrediction p,
    ThemeData theme,
    bool isDark,
  ) {
    final name = p.animalName ?? 'Unknown';
    final initial = name.isNotEmpty ? name[0] : '?';
    final gainIsPositive = p.predictedGain >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? theme.dividerColor : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.farmGreen.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: AppTheme.farmGreen,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: theme.textTheme.titleMedium?.color,
                  ),
                ),
                Text(
                  'Tag: ${p.animalTagId}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildConfidenceBadge(p.confidenceScore),
                    if (p.willReachTarget) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Market Ready',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[700],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${p.predictedWeight.toStringAsFixed(1)} kg',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.textTheme.titleMedium?.color,
                ),
              ),
              Text(
                '${gainIsPositive ? "+" : ""}${p.predictedGain.toStringAsFixed(1)} kg',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: gainIsPositive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'from ${p.currentWeight.toStringAsFixed(1)} kg',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(double confidence) {
    final percentage = (confidence * 100).round();
    Color color;
    if (confidence >= 0.85) {
      color = Colors.green;
    } else if (confidence >= 0.7) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$percentage% conf.',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
