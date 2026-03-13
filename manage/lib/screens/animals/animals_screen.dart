import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../providers/paginated_animals_provider.dart';
import '../../router/app_router.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/seo_helper.dart';
import '../../widgets/search_bar_widget.dart';
import 'add_animal_dialog.dart';

class AnimalsScreen extends ConsumerStatefulWidget {
  const AnimalsScreen({super.key});

  @override
  ConsumerState<AnimalsScreen> createState() => _AnimalsScreenState();
}

class _AnimalsScreenState extends ConsumerState<AnimalsScreen> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    SeoHelper.configureAnimalsPage();
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
      ref.read(paginatedAnimalsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paginatedAnimalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Animal Inventory')),
      body: _buildBody(context, state),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAnimalDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Animal'),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PaginatedAnimalsState state) {
    if (state.error != null && state.animals.isEmpty) {
      return Center(child: Text('Error: ${state.error}'));
    }

    if (state.isLoading && state.animals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.animals.isEmpty) {
      return _buildEmptyState(context);
    }

    // Filter animals based on search query
    final filteredAnimals = _searchQuery.isEmpty
        ? state.animals
        : state.animals.where((animal) {
            final query = _searchQuery.toLowerCase();
            return animal.tagId.toLowerCase().contains(query) ||
                (animal.name?.toLowerCase().contains(query) ?? false) ||
                animal.species.displayName.toLowerCase().contains(query) ||
                (animal.breed?.toLowerCase().contains(query) ?? false);
          }).toList();

    final filteredState = state.copyWith(animals: filteredAnimals);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SearchBarWidget(
            hintText: 'Search by tag, name, species, or breed...',
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
                ref.read(paginatedAnimalsProvider.notifier).refresh(),
            child: _buildAnimalList(context, filteredState),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pets, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No animals yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to add your first animal',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimalList(BuildContext context, PaginatedAnimalsState state) {
    final animals = state.animals;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > Breakpoints.tablet;
        final screenWidth = constraints.maxWidth;

        // Calculate horizontal padding for centering on wide screens
        const maxContentWidth = 1200.0;
        final horizontalPadding = screenWidth > maxContentWidth
            ? (screenWidth - maxContentWidth) / 2 + 8
            : 8.0;

        if (isWide) {
          // Grid layout for larger screens
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
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final animal = animals[index];
                    return _AnimalCard(animal: animal);
                  }, childCount: animals.length),
                ),
              ),
              if (state.isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (!state.hasMore && animals.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'All ${animals.length} animals loaded',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        // List layout for mobile
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          itemCount:
              animals.length + (state.isLoading || !state.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == animals.length) {
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
                    'All ${animals.length} animals loaded',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              );
            }
            final animal = animals[index];
            return _AnimalCard(animal: animal);
          },
        );
      },
    );
  }

  void _showAddAnimalDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => const AddAnimalDialog(),
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Animal animal;

  const _AnimalCard({required this.animal});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(
            animal.status,
          ).withValues(alpha: 0.2),
          child: Text(
            animal.species.icon,
            style: const TextStyle(fontSize: 20),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                animal.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              animal.gender == Gender.male ? Icons.male : Icons.female,
              size: 18,
              color: animal.gender == Gender.male ? Colors.blue : Colors.pink,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${animal.species.displayName}${animal.breed != null ? ' • ${animal.breed}' : ''} • ${animal.ageFormatted}',
            ),
            Row(
              children: [
                if (animal.currentWeight != null) ...[
                  Icon(Icons.monitor_weight, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('${animal.currentWeight!.toStringAsFixed(1)} kg'),
                  const SizedBox(width: 12),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      animal.status,
                    ).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    animal.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(animal.status),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => coordinator.push(AnimalDetailRoute(animal: animal)),
      ),
    );
  }

  Color _getStatusColor(AnimalStatus status) {
    switch (status) {
      case AnimalStatus.healthy:
        return Colors.green;
      case AnimalStatus.sick:
        return Colors.red;
      case AnimalStatus.pregnant:
        return Colors.pink;
      case AnimalStatus.nursing:
        return Colors.purple;
      case AnimalStatus.sold:
        return Colors.grey;
      case AnimalStatus.deceased:
        return Colors.black54;
    }
  }
}
