import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/seo_helper.dart';
import '../../providers/providers.dart';
import '../../providers/ml_analytics_provider.dart';
import '../../router/app_router.dart';

class MLScreen extends ConsumerStatefulWidget {
  const MLScreen({super.key});

  @override
  ConsumerState<MLScreen> createState() => _MLScreenState();
}

class _MLScreenState extends ConsumerState<MLScreen> {
  @override
  void initState() {
    super.initState();
    SeoHelper.configureMlAnalyticsPage();
  }

  @override
  Widget build(BuildContext context) {
    // Watch providers for data counts
    final animalsAsync = ref.watch(animalsProvider);
    final weightRecordsAsync = ref.watch(weightRecordsProvider);
    final feedingRecordsAsync = ref.watch(feedingRecordsProvider);
    final breedingRecordsAsync = ref.watch(breedingRecordsProvider);

    // Watch ML backend status
    final mlHealth = ref.watch(mlHealthProvider);
    final weightModelInfo = ref.watch(mlModelInfoProvider);
    final healthModelInfo = ref.watch(mlHealthModelInfoProvider);
    final mlState = ref.watch(mlAnalyticsProvider);

    // Determine model statuses from backend
    final weightStatus = weightModelInfo.when(
      data: (info) =>
          info.isLoaded ? MLModelStatus.ready : MLModelStatus.notTrained,
      loading: () => MLModelStatus.training,
      error: (_, _) => MLModelStatus.error,
    );

    final healthStatus = healthModelInfo.when(
      data: (info) =>
          info.isLoaded ? MLModelStatus.ready : MLModelStatus.notTrained,
      loading: () => MLModelStatus.training,
      error: (_, _) => MLModelStatus.error,
    );

    final isBackendConnected = mlHealth.when(
      data: (status) => status.isHealthy,
      loading: () => false,
      error: (_, _) => false,
    );

    final modelsReady =
        (weightStatus == MLModelStatus.ready ? 1 : 0) +
        (healthStatus == MLModelStatus.ready ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(mlHealthProvider);
              ref.invalidate(mlModelInfoProvider);
              ref.invalidate(mlHealthModelInfoProvider);
              ref.read(mlAnalyticsProvider.notifier).refresh();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Refreshing ML data...'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status Banner
            _buildConnectionBanner(context, isBackendConnected),
            const SizedBox(height: 16),

            // Header Section
            _buildHeaderCard(
              context,
              animalsAsync,
              weightRecordsAsync,
              feedingRecordsAsync,
              breedingRecordsAsync,
              modelsReady,
              mlState.predictions.length,
            ),
            const SizedBox(height: 24),

            // Weight Prediction Section
            Text(
              'Weight Predictions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildMLCard(
              context,
              title: 'Growth Forecast',
              description: weightStatus == MLModelStatus.ready
                  ? 'Model loaded - Tap to view predictions'
                  : 'Predict future weight based on historical data',
              icon: Icons.trending_up,
              color: Colors.blue,
              status: weightStatus,
              subtitle: weightModelInfo.whenOrNull(
                data: (info) => info.isLoaded
                    ? 'R\u00B2: ${((info.accuracy ?? 0) * 100).toStringAsFixed(1)}% | MAE: ${info.mae?.toStringAsFixed(1) ?? "N/A"} kg'
                    : null,
              ),
              onTap: () => coordinator.push(MLRoute()),
            ),
            const SizedBox(height: 24),

            // Health Prediction Section
            Text(
              'Health Analytics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildMLCard(
              context,
              title: 'Health Risk Assessment',
              description: healthStatus == MLModelStatus.ready
                  ? 'Model loaded - Tap to view health analytics'
                  : 'Identify animals at risk based on patterns',
              icon: Icons.health_and_safety,
              color: Colors.red,
              status: healthStatus,
              subtitle: healthModelInfo.whenOrNull(
                data: (info) => info.isLoaded
                    ? 'Risk + Treatment + Decline models | ${info.samples ?? 0} samples'
                    : null,
              ),
              onTap: () => coordinator.push(MLRoute()),
            ),
            const SizedBox(height: 24),

            // Breeding Prediction Section
            Text(
              'Breeding Analytics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildMLCard(
              context,
              title: 'Fertility Prediction',
              description: 'Predict optimal breeding times and success rates',
              icon: Icons.child_friendly,
              color: Colors.pink,
              status: MLModelStatus.notTrained,
            ),
            _buildMLCard(
              context,
              title: 'Farrowing Date Prediction',
              description: 'Accurate farrowing date estimation',
              icon: Icons.calendar_month,
              color: Colors.purple,
              status: MLModelStatus.notTrained,
            ),
            const SizedBox(height: 24),

            // Feed Optimization Section
            Text(
              'Feed Optimization',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildMLCard(
              context,
              title: 'Feed Efficiency Analysis',
              description: 'Optimize feed-to-weight conversion ratios',
              icon: Icons.restaurant,
              color: Colors.orange,
              status: MLModelStatus.notTrained,
            ),
            const SizedBox(height: 24),

            // Data Summary Section
            Text('Data Summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildDataSummaryCard(
              context,
              animalsAsync,
              weightRecordsAsync,
              feedingRecordsAsync,
              breedingRecordsAsync,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(BuildContext context, bool isConnected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isConnected
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'ML Backend Connected' : 'ML Backend Offline',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isConnected ? Colors.green[700] : Colors.orange[700],
                  ),
                ),
                Text(
                  isConnected
                      ? 'Connected to cloud backend'
                      : 'Backend unavailable',
                  style: TextStyle(
                    fontSize: 12,
                    color: isConnected ? Colors.green[600] : Colors.orange[600],
                  ),
                ),
              ],
            ),
          ),
          if (isConnected)
            TextButton(
              onPressed: () => coordinator.push(MLRoute()),
              child: const Text('View Analytics'),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    AsyncValue animalsAsync,
    AsyncValue weightRecordsAsync,
    AsyncValue feedingRecordsAsync,
    AsyncValue breedingRecordsAsync,
    int modelsReady,
    int predictionsCount,
  ) {
    final totalData =
        animalsAsync.maybeWhen(
          data: (animals) => animals.length,
          orElse: () => 0,
        ) +
        weightRecordsAsync.maybeWhen(
          data: (records) => records.length,
          orElse: () => 0,
        ) +
        feedingRecordsAsync.maybeWhen(
          data: (records) => records.length,
          orElse: () => 0,
        ) +
        breedingRecordsAsync.maybeWhen(
          data: (records) => records.length,
          orElse: () => 0,
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.psychology,
                    size: 32,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Machine Learning Hub',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'AI-powered insights for your farm',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context,
                  'Models',
                  '$modelsReady',
                  Icons.model_training,
                ),
                _buildStatItem(
                  context,
                  'Predictions',
                  '$predictionsCount',
                  Icons.analytics,
                ),
                _buildStatItem(
                  context,
                  'Records',
                  '$totalData',
                  Icons.data_usage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: Colors.teal, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildMLCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required MLModelStatus status,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.teal[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        trailing: _buildStatusChip(status),
        onTap:
            onTap ??
            () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title - Coming soon!'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
      ),
    );
  }

  Widget _buildStatusChip(MLModelStatus status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case MLModelStatus.notTrained:
        color = Colors.grey;
        label = 'Not Trained';
        icon = Icons.hourglass_empty;
      case MLModelStatus.training:
        color = Colors.orange;
        label = 'Loading...';
        icon = Icons.sync;
      case MLModelStatus.ready:
        color = Colors.green;
        label = 'Ready';
        icon = Icons.check_circle;
      case MLModelStatus.error:
        color = Colors.red;
        label = 'Offline';
        icon = Icons.cloud_off;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataSummaryCard(
    BuildContext context,
    AsyncValue animalsAsync,
    AsyncValue weightRecordsAsync,
    AsyncValue feedingRecordsAsync,
    AsyncValue breedingRecordsAsync,
  ) {
    final animalCount = animalsAsync.maybeWhen(
      data: (animals) => animals.length,
      orElse: () => 0,
    );
    final weightCount = weightRecordsAsync.maybeWhen(
      data: (records) => records.length,
      orElse: () => 0,
    );
    final feedingCount = feedingRecordsAsync.maybeWhen(
      data: (records) => records.length,
      orElse: () => 0,
    );
    final breedingCount = breedingRecordsAsync.maybeWhen(
      data: (records) => records.length,
      orElse: () => 0,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  'Available Training Data',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDataRow(
              context,
              'Animal Records',
              '$animalCount records',
              Icons.pets,
            ),
            _buildDataRow(
              context,
              'Weight Records',
              '$weightCount records',
              Icons.monitor_weight,
            ),
            _buildDataRow(
              context,
              'Feeding Records',
              '$feedingCount records',
              Icons.restaurant,
            ),
            _buildDataRow(
              context,
              'Breeding Records',
              '$breedingCount records',
              Icons.family_restroom,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum MLModelStatus { notTrained, training, ready, error }
