import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/seo_helper.dart';
import '../../providers/providers.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh all providers
              ref.invalidate(animalsProvider);
              ref.invalidate(weightRecordsProvider);
              ref.invalidate(feedingRecordsProvider);
              ref.invalidate(breedingRecordsProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Data refreshed'),
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
            // Header Section
            _buildHeaderCard(
              context,
              animalsAsync,
              weightRecordsAsync,
              feedingRecordsAsync,
              breedingRecordsAsync,
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
              description: 'Predict future weight based on historical data',
              icon: Icons.trending_up,
              color: Colors.blue,
              status: MLModelStatus.notTrained,
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
              description: 'Identify animals at risk based on patterns',
              icon: Icons.health_and_safety,
              color: Colors.red,
              status: MLModelStatus.notTrained,
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

            // Visualization Placeholder Section
            Text(
              'Visualizations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildVisualizationPlaceholder(context),
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

  Widget _buildHeaderCard(
    BuildContext context,
    AsyncValue animalsAsync,
    AsyncValue weightRecordsAsync,
    AsyncValue feedingRecordsAsync,
    AsyncValue breedingRecordsAsync,
  ) {
    // Calculate total predictions (placeholder for now)
    final totalData = animalsAsync.maybeWhen(
      data: (animals) => animals.length,
      orElse: () => 0,
    );
    final weightData = weightRecordsAsync.maybeWhen(
      data: (records) => records.length,
      orElse: () => 0,
    );
    final feedingData = feedingRecordsAsync.maybeWhen(
      data: (records) => records.length,
      orElse: () => 0,
    );
    final breedingData = breedingRecordsAsync.maybeWhen(
      data: (records) => records.length,
      orElse: () => 0,
    );
    
    final totalRecords = totalData + weightData + feedingData + breedingData;
    final modelsReady = 0; // Placeholder until ML models are integrated
    final predictionsCount = 0; // Placeholder

    return _buildHeaderCardInternal(
      context,
      modelsReady,
      predictionsCount,
      totalRecords,
    );
  }

  Widget _buildHeaderCardInternal(
    BuildContext context,
    int models,
    int predictions,
    int totalRecords,
  ) {
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
                  '$models',
                  Icons.model_training,
                ),
                _buildStatItem(
                  context,
                  'Predictions',
                  '$predictions',
                  Icons.analytics,
                ),
                _buildStatItem(
                  context,
                  'Records',
                  '$totalRecords',
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
        subtitle: Text(description),
        trailing: _buildStatusChip(status),
        onTap: () {
          // TODO: Navigate to model details or run prediction
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
        label = 'Training';
        icon = Icons.sync;
      case MLModelStatus.ready:
        color = Colors.green;
        label = 'Ready';
        icon = Icons.check;
      case MLModelStatus.error:
        color = Colors.red;
        label = 'Error';
        icon = Icons.error;
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

  Widget _buildVisualizationPlaceholder(BuildContext context) {
    return Card(
      child: Container(
        height: 250,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_chart_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Charts & Graphs',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Visualizations will appear here once ML models are trained',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Sample visualizations will be available once ML models are trained',
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility),
              label: const Text('Preview Sample'),
            ),
          ],
        ),
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

    return _buildDataSummaryCardInternal(
      context,
      animalCount,
      weightCount,
      feedingCount,
      breedingCount,
    );
  }

  Widget _buildDataSummaryCardInternal(
    BuildContext context,
    int animalCount,
    int weightCount,
    int feedingCount,
    int breedingCount,
  ) {
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
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Show export options
                      final format = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Export Data'),
                          content: const Text(
                            'Choose export format for ML training data',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'csv'),
                              child: const Text('CSV'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, 'json'),
                              child: const Text('JSON'),
                            ),
                          ],
                        ),
                      );
                      if (format != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Exporting data as ${format.toUpperCase()}...'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                        // TODO: Implement actual export functionality
                        // This would use ExportService to export all data
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Export Data'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: animalCount > 0 && weightCount > 0
                        ? () {
                            // Show training dialog
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Train ML Models'),
                                content: const Text(
                                  'Model training requires connection to the ML backend service. '
                                  'This feature will be available once the backend is configured.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Train Models'),
                  ),
                ),
              ],
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
