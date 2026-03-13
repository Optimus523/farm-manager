import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../providers/auth_providers.dart';
import '../../models/models.dart';
import '../../router/app_router.dart';
import '../../utils/responsive_layout.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final bool showCreateFarmDialog;

  const DashboardScreen({super.key, this.showCreateFarmDialog = false});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.showCreateFarmDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCreateFirstFarmDialog();
      });
    }
  }

  void _showCreateFirstFarmDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Your Farm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Welcome! Let\'s set up your first farm. As the creator, you will be the Owner with full access.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Farm Name',
                hintText: 'e.g., Green Valley Farm',
                prefixIcon: Icon(Icons.agriculture),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Skip for Now'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              final authNotifier = ref.read(authNotifierProvider.notifier);
              await authNotifier.createFarm(nameController.text);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animalsAsync = ref.watch(animalsProvider);
    final theme = Theme.of(context);

    // Watch notification counts
    final activeReminderCount = ref.watch(activeReminderCountProvider);
    final unreadAdminCount = ref.watch(unreadAdminNotificationCountProvider);

    // Total notification count
    final totalNotificationCount = activeReminderCount.maybeWhen(
      data: (count) => count + unreadAdminCount,
      orElse: () => unreadAdminCount,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Farm Dashboard'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => coordinator.push(NotificationsRoute()),
                tooltip: 'Notifications',
              ),
              if (totalNotificationCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      totalNotificationCount > 99
                          ? '99+'
                          : '$totalNotificationCount',
                      style: TextStyle(
                        color: theme.colorScheme.onError,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  coordinator.push(SettingsRoute());
                  break;
                case 'profile':
                  coordinator.push(ProfileRoute());
                  break;
                case 'logout':
                  _showLogoutDialog(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Logout', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => coordinator.push(AssistantRoute()),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI Assistant'),
        tooltip: 'Ask Farm AI Assistant',
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(animalsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Section
              _buildWelcomeSection(context, ref, theme),
              const SizedBox(height: 24),

              // Quick Stats
              _buildQuickStats(animalsAsync, theme),
              const SizedBox(height: 24),

              // Quick Actions Grid
              Text(
                'Quick Actions',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildQuickActionsGrid(context),
              const SizedBox(height: 24),

              // Recent Activity
              Text(
                'Recent Activity',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildRecentActivity(animalsAsync, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
  ) {
    final userAsync = ref.watch(currentUserProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                size: 30,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back!',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  userAsync.when(
                    data: (user) => Text(
                      user?.displayName ?? user?.email ?? 'Farmer',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    loading: () => const Text('Loading...'),
                    error: (_, _) => const Text('Farmer'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(
    AsyncValue<List<Animal>> animalsAsync,
    ThemeData theme,
  ) {
    return animalsAsync.when(
      data: (animals) {
        final totalAnimals = animals.length;
        final healthyCount = animals
            .where((a) => a.status == AnimalStatus.healthy)
            .length;
        final sickCount = animals
            .where((a) => a.status == AnimalStatus.sick)
            .length;

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Total',
                value: totalAnimals.toString(),
                icon: Icons.pets,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                title: 'Healthy',
                value: healthyCount.toString(),
                icon: Icons.favorite,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                title: 'Sick',
                value: sickCount.toString(),
                icon: Icons.medical_services,
                color: Colors.red,
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error loading stats: $error'),
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context) {
    // Get current user's role for the active farm
    final user = ref.watch(currentUserProvider).value;
    final userRole = user?.activeRole ?? UserRole.worker;

    // Define all actions with their required minimum role
    final allActions = <({_QuickAction action, UserRole minRole})>[
      (
        action: _QuickAction(
          title: 'Animals',
          subtitle: 'View all',
          icon: Icons.pets,
          color: Colors.teal,
          onTap: () => coordinator.push(AnimalsRoute()),
        ),
        minRole: UserRole.worker, // All roles can view animals
      ),
      (
        action: _QuickAction(
          title: 'Health',
          subtitle: 'Records',
          icon: Icons.medical_services,
          color: Colors.red,
          onTap: () => coordinator.push(HealthRoute()),
        ),
        minRole: UserRole.vet, // Vet, manager, owner
      ),
      (
        action: _QuickAction(
          title: 'Weight',
          subtitle: 'Tracking',
          icon: Icons.monitor_weight,
          color: Colors.blue,
          onTap: () => coordinator.push(WeightRoute()),
        ),
        minRole: UserRole.worker, // All roles
      ),
      (
        action: _QuickAction(
          title: 'Feeding',
          subtitle: 'Schedules',
          icon: Icons.restaurant,
          color: Colors.orange,
          onTap: () => coordinator.push(FeedingRoute()),
        ),
        minRole: UserRole.worker, // All roles
      ),
      (
        action: _QuickAction(
          title: 'Breeding',
          subtitle: 'Records',
          icon: Icons.favorite_border,
          color: Colors.pink,
          onTap: () => coordinator.push(BreedingRoute()),
        ),
        minRole: UserRole.vet, // Vet, manager, owner
      ),
      (
        action: _QuickAction(
          title: 'Financial',
          subtitle: 'Expenses',
          icon: Icons.account_balance_wallet,
          color: Colors.green,
          onTap: () => coordinator.push(FinancialRoute()),
        ),
        minRole: UserRole.manager, // Manager, owner only
      ),
      (
        action: _QuickAction(
          title: 'Reports',
          subtitle: 'Analytics',
          icon: Icons.bar_chart,
          color: Colors.purple,
          onTap: () => coordinator.push(ReportsRoute()),
        ),
        minRole: UserRole.manager, // Manager, owner only
      ),
      (
        action: _QuickAction(
          title: 'ML Analytics',
          subtitle: 'AI Insights',
          icon: Icons.psychology,
          color: const Color(0xFF6366F1),
          onTap: () => coordinator.push(MLRoute()),
        ),
        minRole: UserRole.manager, // Manager, owner only
      ),
      (
        action: _QuickAction(
          title: 'Budget',
          subtitle: 'Planning',
          icon: Icons.savings,
          color: Colors.amber,
          onTap: () => coordinator.push(BudgetRoute()),
        ),
        minRole: UserRole.owner, // Owner only
      ),
    ];

    // Filter actions based on user role
    final actions = allActions
        .where((item) => _hasAccessToAction(userRole, item.minRole))
        .map((item) => item.action)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive columns and aspect ratio based on available width
        int crossAxisCount = 2;
        double aspectRatio = 1.4; // Adjusted for better content fit

        if (constraints.maxWidth >= Breakpoints.desktop) {
          crossAxisCount = 4;
          aspectRatio = 1.6;
        } else if (constraints.maxWidth >= Breakpoints.tablet) {
          crossAxisCount = 3;
          aspectRatio = 1.5;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) => actions[index],
        );
      },
    );
  }

  Widget _buildRecentActivity(
    AsyncValue<List<Animal>> animalsAsync,
    ThemeData theme,
  ) {
    return animalsAsync.when(
      data: (animals) {
        if (animals.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.pets, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No animals yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add your first animal to get started',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Show recent animals
        final recentAnimals = animals.take(5).toList();

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentAnimals.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final animal = recentAnimals[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(
                    animal.status,
                  ).withValues(alpha: 0.2),
                  child: Text(
                    animal.species.icon,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                title: Text(animal.name ?? animal.tagId),
                subtitle: Text(
                  '${animal.species.displayName} • ${animal.status.name}',
                ),
                trailing: Icon(
                  Icons.circle,
                  size: 12,
                  color: _getStatusColor(animal.status),
                ),
                onTap: () =>
                    coordinator.push(AnimalDetailRoute(animal: animal)),
              );
            },
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text('Error: $error')),
        ),
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
        return Colors.blue;
      case AnimalStatus.deceased:
        return Colors.grey;
    }
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gradient Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade600, Colors.red.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.waving_hand_rounded,
                        size: 48,
                        color: Colors.orange.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Are you sure you want to sign out?',
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You will need to sign in again to access your farm data.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(context);
                            ref.read(authNotifierProvider.notifier).signOut();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Sign Out'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Check if user role has access to an action based on minimum required role
  bool _hasAccessToAction(UserRole userRole, UserRole minRole) {
    // Role hierarchy: owner > manager > vet > worker
    const roleHierarchy = {
      UserRole.owner: 4,
      UserRole.manager: 3,
      UserRole.vet: 2,
      UserRole.worker: 1,
    };

    final userLevel = roleHierarchy[userRole] ?? 1;
    final requiredLevel = roleHierarchy[minRole] ?? 1;

    return userLevel >= requiredLevel;
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.2),
                      radius: 16,
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
