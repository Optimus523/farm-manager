import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../providers/paginated_health_provider.dart';
import '../../providers/providers.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/seo_helper.dart';
import '../../widgets/search_bar_widget.dart';
import 'add_health_record_dialog.dart';
import 'health_record_detail_dialog.dart';

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    SeoHelper.configureHealthPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(paginatedHealthProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthState = ref.watch(paginatedHealthProvider);
    final animalsAsync = ref.watch(animalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Management'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Vaccinations'),
            Tab(text: 'Medications'),
            Tab(text: 'Treatments'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPaginatedRecordsList(context, ref, healthState, animalsAsync),
          _buildVaccinationsList(context, ref, animalsAsync),
          _buildMedicationsList(context, ref, animalsAsync),
          _buildTreatmentsList(context, ref, animalsAsync),
          _buildAlertsList(context, ref, animalsAsync),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddHealthRecordDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Record'),
      ),
    );
  }

  Widget _buildPaginatedRecordsList(
    BuildContext context,
    WidgetRef ref,
    PaginatedHealthState healthState,
    AsyncValue<List<Animal>> animalsAsync,
  ) {
    if (healthState.error != null && healthState.records.isEmpty) {
      return Center(child: Text('Error: ${healthState.error}'));
    }

    if (healthState.isLoading && healthState.records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (healthState.records.isEmpty) {
      return _buildEmptyState(
        context,
        'No health records yet',
        'Start by adding vaccinations, medications, or treatments',
      );
    }

    return animalsAsync.when(
      data: (animals) {
        final animalMap = {for (var a in animals) a.id: a};

        // Filter records based on search query
        final filteredRecords = _searchQuery.isEmpty
            ? healthState.records
            : healthState.records.where((record) {
                final query = _searchQuery.toLowerCase();
                final animal = animalMap[record.animalId];
                return (animal?.tagId.toLowerCase().contains(query) ?? false) ||
                    (animal?.name?.toLowerCase().contains(query) ?? false) ||
                    record.type.name.toLowerCase().contains(query) ||
                    record.title.toLowerCase().contains(query) ||
                    (record.description?.toLowerCase().contains(query) ??
                        false) ||
                    (record.veterinarianName?.toLowerCase().contains(query) ??
                        false);
              }).toList();

        final filteredState = healthState.copyWith(records: filteredRecords);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: SearchBarWidget(
                hintText: 'Search by animal, type, description, vet...',
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
                    ref.read(paginatedHealthProvider.notifier).refresh(),
                child: _buildPaginatedResponsiveList(
                  records: filteredRecords,
                  animalMap: animalMap,
                  state: filteredState,
                  onTap: (record, animal) =>
                      _showRecordDetail(context, record, animal),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildPaginatedResponsiveList({
    required List<HealthRecord> records,
    required Map<String, Animal> animalMap,
    required PaginatedHealthState state,
    required void Function(HealthRecord, Animal?) onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > Breakpoints.tablet;
        final screenWidth = constraints.maxWidth;
        const maxContentWidth = 1200.0;
        final horizontalPadding = screenWidth > maxContentWidth
            ? (screenWidth - maxContentWidth) / 2 + 8
            : 8.0;

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
                    childAspectRatio: 2.2,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final record = records[index];
                    final animal = animalMap[record.animalId];
                    return _HealthRecordCard(
                      record: record,
                      animal: animal,
                      onTap: () => onTap(record, animal),
                    );
                  }, childCount: records.length),
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
            final record = records[index];
            final animal = animalMap[record.animalId];
            return _HealthRecordCard(
              record: record,
              animal: animal,
              onTap: () => onTap(record, animal),
            );
          },
        );
      },
    );
  }

  /// Responsive list for non-paginated tabs (Vaccinations, Medications, etc.)
  Widget _buildResponsiveRecordList({
    required List<HealthRecord> records,
    required Map<String, Animal> animalMap,
    required void Function(HealthRecord, Animal?) onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > Breakpoints.tablet;
        final screenWidth = constraints.maxWidth;
        const maxContentWidth = 1200.0;
        final horizontalPadding = screenWidth > maxContentWidth
            ? (screenWidth - maxContentWidth) / 2 + 8
            : 8.0;

        if (isWide) {
          return GridView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 8,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth > Breakpoints.desktop
                  ? 3
                  : 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
            ),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              final animal = animalMap[record.animalId];
              return _HealthRecordCard(
                record: record,
                animal: animal,
                onTap: () => onTap(record, animal),
              );
            },
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: records.length,
          itemBuilder: (context, index) {
            final record = records[index];
            final animal = animalMap[record.animalId];
            return _HealthRecordCard(
              record: record,
              animal: animal,
              onTap: () => onTap(record, animal),
            );
          },
        );
      },
    );
  }

  Widget _buildVaccinationsList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Animal>> animalsAsync,
  ) {
    final vaccinationsAsync = ref.watch(
      healthRecordsByTypeProvider(HealthRecordType.vaccination),
    );

    return vaccinationsAsync.when(
      data: (records) => records.isEmpty
          ? _buildEmptyState(
              context,
              'No vaccinations recorded',
              'Keep your animals healthy with regular vaccinations',
            )
          : animalsAsync.when(
              data: (animals) {
                final animalMap = {for (var a in animals) a.id: a};
                return _buildResponsiveRecordList(
                  records: records,
                  animalMap: animalMap,
                  onTap: (record, animal) =>
                      _showRecordDetail(context, record, animal),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildMedicationsList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Animal>> animalsAsync,
  ) {
    final medicationsAsync = ref.watch(
      healthRecordsByTypeProvider(HealthRecordType.medication),
    );

    return medicationsAsync.when(
      data: (records) => records.isEmpty
          ? _buildEmptyState(
              context,
              'No medications recorded',
              'Track medications and withdrawal periods',
            )
          : animalsAsync.when(
              data: (animals) {
                final animalMap = {for (var a in animals) a.id: a};
                return _buildResponsiveRecordList(
                  records: records,
                  animalMap: animalMap,
                  onTap: (record, animal) =>
                      _showRecordDetail(context, record, animal),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildTreatmentsList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Animal>> animalsAsync,
  ) {
    final treatmentsAsync = ref.watch(
      healthRecordsByTypeProvider(HealthRecordType.treatment),
    );
    final surgeriesAsync = ref.watch(
      healthRecordsByTypeProvider(HealthRecordType.surgery),
    );
    final checkupsAsync = ref.watch(
      healthRecordsByTypeProvider(HealthRecordType.checkup),
    );

    return treatmentsAsync.when(
      data: (treatments) => surgeriesAsync.when(
        data: (surgeries) => checkupsAsync.when(
          data: (checkups) {
            final allRecords = [...treatments, ...surgeries, ...checkups];
            allRecords.sort((a, b) => b.date.compareTo(a.date));

            return allRecords.isEmpty
                ? _buildEmptyState(
                    context,
                    'No treatments recorded',
                    'Record treatments, surgeries, and checkups',
                  )
                : animalsAsync.when(
                    data: (animals) {
                      final animalMap = {for (var a in animals) a.id: a};
                      return _buildResponsiveRecordList(
                        records: allRecords,
                        animalMap: animalMap,
                        onTap: (record, animal) =>
                            _showRecordDetail(context, record, animal),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, st) => Center(child: Text('Error: $e')),
                  );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildAlertsList(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Animal>> animalsAsync,
  ) {
    final upcomingVaccinations = ref.watch(upcomingVaccinationsProvider);
    final pendingFollowUps = ref.watch(pendingFollowUpsProvider);
    final animalsInWithdrawal = ref.watch(animalsInWithdrawalProvider);

    return animalsAsync.when(
      data: (animals) {
        final animalMap = {for (var a in animals) a.id: a};

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                // Upcoming Vaccinations Section
                _buildAlertSection(
                  context,
                  'Upcoming Vaccinations',
                  Icons.vaccines,
                  Colors.blue,
                  upcomingVaccinations,
                  animalMap,
                ),

                // Pending Follow-ups Section
                _buildAlertSection(
                  context,
                  'Pending Follow-ups',
                  Icons.schedule,
                  Colors.orange,
                  pendingFollowUps,
                  animalMap,
                ),

                // Animals in Withdrawal Section
                _buildAlertSection(
                  context,
                  'Animals in Withdrawal',
                  Icons.warning_amber,
                  Colors.red,
                  animalsInWithdrawal,
                  animalMap,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildAlertSection(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    AsyncValue<List<HealthRecord>> recordsAsync,
    Map<String, Animal> animalMap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        recordsAsync.when(
          data: (records) => records.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('No $title'),
                    ),
                  ),
                )
              : Column(
                  children: records
                      .map(
                        (record) => _HealthRecordCard(
                          record: record,
                          animal: animalMap[record.animalId],
                          onTap: () => _showRecordDetail(
                            context,
                            record,
                            animalMap[record.animalId],
                          ),
                          compact: true,
                        ),
                      )
                      .toList(),
                ),
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $e'),
          ),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medical_services, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddHealthRecordDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddHealthRecordDialog(),
    );
  }

  void _showRecordDetail(
    BuildContext context,
    HealthRecord record,
    Animal? animal,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) =>
            HealthRecordDetailDialog(record: record, animal: animal),
      ),
    );
  }
}

class _HealthRecordCard extends StatelessWidget {
  final HealthRecord record;
  final Animal? animal;
  final VoidCallback? onTap;
  final bool compact;

  const _HealthRecordCard({
    required this.record,
    this.animal,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(record.type).withValues(alpha: 0.2),
          child: Icon(
            _getTypeIcon(record.type),
            color: _getTypeColor(record.type),
            size: compact ? 20 : 24,
          ),
        ),
        title: Text(
          record.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (animal != null)
              Text('Animal: ${animal!.tagId}')
            else
              const Text('Animal: Unknown'),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  dateFormat.format(record.date),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      record.status,
                    ).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    record.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(record.status),
                    ),
                  ),
                ),
              ],
            ),
            if (record.isInWithdrawalPeriod) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    'In withdrawal until ${dateFormat.format(record.withdrawalEndDate!)}',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ],
              ),
            ],
            if (record.nextDueDate != null && !compact) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Next due: ${dateFormat.format(record.nextDueDate!)}',
                    style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        isThreeLine: true,
      ),
    );
  }

  Color _getTypeColor(HealthRecordType type) {
    switch (type) {
      case HealthRecordType.vaccination:
        return Colors.blue;
      case HealthRecordType.medication:
        return Colors.purple;
      case HealthRecordType.checkup:
        return Colors.teal;
      case HealthRecordType.treatment:
        return Colors.orange;
      case HealthRecordType.surgery:
        return Colors.red;
      case HealthRecordType.observation:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(HealthRecordType type) {
    switch (type) {
      case HealthRecordType.vaccination:
        return Icons.vaccines;
      case HealthRecordType.medication:
        return Icons.medication;
      case HealthRecordType.checkup:
        return Icons.health_and_safety;
      case HealthRecordType.treatment:
        return Icons.healing;
      case HealthRecordType.surgery:
        return Icons.local_hospital;
      case HealthRecordType.observation:
        return Icons.visibility;
    }
  }

  Color _getStatusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.pending:
        return Colors.orange;
      case HealthStatus.inProgress:
        return Colors.blue;
      case HealthStatus.completed:
        return Colors.green;
      case HealthStatus.cancelled:
        return Colors.grey;
    }
  }
}
