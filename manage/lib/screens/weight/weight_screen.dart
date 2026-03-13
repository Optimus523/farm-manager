import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../providers/paginated_weight_provider.dart';
import '../../providers/providers.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/seo_helper.dart';
import '../../widgets/search_bar_widget.dart';
import 'add_weight_dialog.dart';

class WeightScreen extends ConsumerStatefulWidget {
  const WeightScreen({super.key});

  @override
  ConsumerState<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends ConsumerState<WeightScreen> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    SeoHelper.configureWeightPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(paginatedWeightProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weightState = ref.watch(paginatedWeightProvider);
    final animalsAsync = ref.watch(animalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Weight Records')),
      body: _buildBody(context, weightState, animalsAsync),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddWeightDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Record'),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    PaginatedWeightState state,
    AsyncValue<List<Animal>> animalsAsync,
  ) {
    if (state.error != null && state.records.isEmpty) {
      return Center(child: Text('Error: ${state.error}'));
    }

    if (state.isLoading && state.records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.records.isEmpty) {
      return _buildEmptyState(context);
    }

    return animalsAsync.when(
      data: (animals) {
        final animalMap = {for (var a in animals) a.id: a};

        // Filter records based on search query
        final filteredRecords = _searchQuery.isEmpty
            ? state.records
            : state.records.where((record) {
                final query = _searchQuery.toLowerCase();
                final animal = animalMap[record.animalId];
                return (animal?.tagId.toLowerCase().contains(query) ?? false) ||
                    (animal?.name?.toLowerCase().contains(query) ?? false) ||
                    record.weight.toString().contains(query) ||
                    (record.notes?.toLowerCase().contains(query) ?? false);
              }).toList();

        final filteredState = state.copyWith(records: filteredRecords);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SearchBarWidget(
                hintText: 'Search by animal tag, name, weight, or notes...',
                onChanged: (query) {
                  setState(() {
                    _searchQuery = query;
                  });
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(paginatedWeightProvider.notifier).refresh(),
                child: _buildRecordsList(context, filteredState, animalMap),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_weight, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No weight records yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Start tracking your animals\' weight',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList(
    BuildContext context,
    PaginatedWeightState state,
    Map<String, Animal> animalMap,
  ) {
    final records = state.records;

    // Group by animal for weight change calculation
    final groupedRecords = <String, List<WeightRecord>>{};
    for (final record in records) {
      final animal = animalMap[record.animalId];
      final key = animal?.tagId ?? 'Unknown';
      groupedRecords.putIfAbsent(key, () => []).add(record);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > Breakpoints.tablet;
        final screenWidth = constraints.maxWidth;
        const maxContentWidth = 1200.0;
        final horizontalPadding = screenWidth > maxContentWidth
            ? (screenWidth - maxContentWidth) / 2 + 8
            : 8.0;

        Widget buildWeightCard(int index) {
          final record = records[index];
          final animal = animalMap[record.animalId];

          // Calculate weight change from previous record
          final animalRecords = groupedRecords[animal?.tagId ?? 'Unknown']!;
          final recordIndex = animalRecords.indexOf(record);
          double? weightChange;
          if (recordIndex < animalRecords.length - 1) {
            weightChange =
                record.weight - animalRecords[recordIndex + 1].weight;
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.indigo.withValues(alpha: 0.2),
                child: const Icon(Icons.monitor_weight, color: Colors.indigo),
              ),
              title: Text(
                animal?.tagId ?? 'Unknown Animal',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat.yMMMd().format(record.date)),
                  if (record.notes != null && record.notes!.isNotEmpty)
                    Text(
                      record.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${record.weight.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (weightChange != null)
                    Text(
                      '${weightChange >= 0 ? '+' : ''}${weightChange.toStringAsFixed(1)} kg',
                      style: TextStyle(
                        fontSize: 12,
                        color: weightChange >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                ],
              ),
              isThreeLine: true,
            ),
          );
        }

        if (isWide) {
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 8,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth > Breakpoints.desktop
                        ? 3
                        : 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.5,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => buildWeightCard(index),
                    childCount: records.length,
                  ),
                ),
              ),
              if (state.isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (!state.hasMore && records.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'All ${records.length} records loaded',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          itemCount:
              records.length + (state.isLoading || !state.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == records.length) {
              if (state.isLoading) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'All ${records.length} records loaded',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              );
            }
            return buildWeightCard(index);
          },
        );
      },
    );
  }

  void _showAddWeightDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => const AddWeightDialog(),
      ),
    );
  }
}
