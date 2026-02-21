import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../repositories/repositories.dart';
import '../utils/currency_utils.dart';
import '../utils/reminder_service.dart';
import 'auth_providers.dart';

// Repository providers
final animalRepositoryProvider = Provider<AnimalRepository>((ref) {
  return AnimalRepository();
});

final feedingRepositoryProvider = Provider<FeedingRepository>((ref) {
  return FeedingRepository();
});

final weightRepositoryProvider = Provider<WeightRepository>((ref) {
  return WeightRepository();
});

final breedingRepositoryProvider = Provider<BreedingRepository>((ref) {
  return BreedingRepository();
});

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository();
});

final financialRepositoryProvider = Provider<FinancialRepository>((ref) {
  return FinancialRepository();
});

/// Provider for the active farm ID - reactive to user changes
final activeFarmIdProvider = Provider<String?>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) {
      if (user == null) return null;
      // Return the active farm ID, or the first farm's ID if no active farm is set
      if (user.activeFarmId != null) return user.activeFarmId;
      return user.farms.isNotEmpty ? user.farms.first.farmId : null;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

// Animal providers - filtered by active farm
final animalsProvider = StreamProvider<List<Animal>>((ref) {
  final repository = ref.watch(animalRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchAnimals(farmId);
});

// Provider for fetching ALL animals (for AI assistant - no pagination/stream limits)
final allAnimalsForAIProvider = FutureProvider<List<Animal>>((ref) async {
  final repository = ref.watch(animalRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) {
    return [];
  }

  final animals = await repository.getAnimals(farmId);
  return animals;
});

final femaleAnimalsProvider = StreamProvider<List<Animal>>((ref) {
  final repository = ref.watch(animalRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchFemaleAnimals(farmId);
});

final maleAnimalsProvider = StreamProvider<List<Animal>>((ref) {
  final repository = ref.watch(animalRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchMaleAnimals(farmId);
});

final animalByIdProvider = FutureProvider.family<Animal?, String>((
  ref,
  id,
) async {
  final repository = ref.watch(animalRepositoryProvider);
  return repository.getAnimal(id);
});

/// Stream provider for watching a single animal by ID with real-time updates
final watchAnimalByIdProvider = StreamProvider.family<Animal?, String>((
  ref,
  id,
) {
  final repository = ref.watch(animalRepositoryProvider);
  return repository.watchAnimalById(id);
});

/// Provider for offspring of an animal (where this animal is mother or father)
final offspringProvider = StreamProvider.family<List<Animal>, String>((
  ref,
  animalId,
) {
  final repository = ref.watch(animalRepositoryProvider);
  return repository.watchOffspring(animalId);
});

final pregnantAnimalsCountProvider = Provider<AsyncValue<int>>((ref) {
  final animals = ref.watch(animalsProvider);
  return animals.whenData(
    (list) => list.where((a) => a.status == AnimalStatus.pregnant).length,
  );
});

// Feeding providers - filtered by active farm
final feedingRecordsProvider = StreamProvider<List<FeedingRecord>>((ref) {
  final repository = ref.watch(feedingRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchFeedingRecords(farmId);
});

final feedingRecordsForAnimalProvider =
    StreamProvider.family<List<FeedingRecord>, String>((ref, animalId) {
      final repository = ref.watch(feedingRepositoryProvider);
      return repository.watchFeedingRecordsForAnimal(animalId);
    });

// Weight providers - filtered by active farm
final weightRecordsProvider = StreamProvider<List<WeightRecord>>((ref) {
  final repository = ref.watch(weightRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchWeightRecords(farmId);
});

final weightRecordsForAnimalProvider =
    StreamProvider.family<List<WeightRecord>, String>((ref, animalId) {
      final repository = ref.watch(weightRepositoryProvider);
      return repository.watchWeightRecordsForAnimal(animalId);
    });

// Breeding providers - filtered by active farm
final breedingRecordsProvider = StreamProvider<List<BreedingRecord>>((ref) {
  final repository = ref.watch(breedingRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchBreedingRecords(farmId);
});

final breedingRecordsForAnimalProvider =
    StreamProvider.family<List<BreedingRecord>, String>((ref, animalId) {
      final repository = ref.watch(breedingRepositoryProvider);
      return repository.watchBreedingRecordsForAnimal(animalId);
    });

final pregnantBreedingRecordsProvider = StreamProvider<List<BreedingRecord>>((
  ref,
) {
  final repository = ref.watch(breedingRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchPregnantAnimals(farmId);
});

final animalsInHeatProvider = StreamProvider<List<BreedingRecord>>((ref) {
  final repository = ref.watch(breedingRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchAnimalsInHeat(farmId);
});

/// Combined provider that returns all pregnant animals
/// This combines animals with pregnant status AND breeding records with pregnant status
/// to ensure consistency across the app
final allPregnantAnimalsProvider = Provider<AsyncValue<List<Animal>>>((ref) {
  final animals = ref.watch(animalsProvider);
  final breedingRecords = ref.watch(pregnantBreedingRecordsProvider);

  return animals.when(
    data: (animalList) {
      final pregnantByStatus = animalList
          .where((a) => a.status == AnimalStatus.pregnant)
          .toList();

      final pregnantByBreeding =
          breedingRecords.whenOrNull(
            data: (records) => records.map((r) => r.animalId).toSet(),
          ) ??
          <String>{};

      // Combine both - add any animals from breeding records not already in the list
      final combinedMap = {for (var a in pregnantByStatus) a.id: a};

      // Add animals from breeding records that aren't already pregnant by status
      for (final animalId in pregnantByBreeding) {
        if (!combinedMap.containsKey(animalId)) {
          final animal = animalList.where((a) => a.id == animalId).firstOrNull;
          if (animal != null) {
            combinedMap[animalId] = animal;
          }
        }
      }

      return AsyncValue.data(combinedMap.values.toList());
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

// Health providers - filtered by active farm
final healthRecordsProvider = StreamProvider<List<HealthRecord>>((ref) {
  final repository = ref.watch(healthRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchHealthRecords(farmId);
});

final healthRecordsForAnimalProvider =
    StreamProvider.family<List<HealthRecord>, String>((ref, animalId) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.watchAnimalHealthRecords(animalId);
    });

final healthRecordsByTypeProvider =
    StreamProvider.family<List<HealthRecord>, HealthRecordType>((ref, type) {
      final repository = ref.watch(healthRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);

      if (farmId == null) return Stream.value([]);
      return repository.watchHealthRecordsByType(farmId, type);
    });

final upcomingVaccinationsProvider = StreamProvider<List<HealthRecord>>((ref) {
  final repository = ref.watch(healthRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchUpcomingVaccinations(farmId);
});

final pendingFollowUpsProvider = StreamProvider<List<HealthRecord>>((ref) {
  final repository = ref.watch(healthRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchPendingFollowUps(farmId);
});

final animalsInWithdrawalProvider = StreamProvider<List<HealthRecord>>((ref) {
  final repository = ref.watch(healthRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchAnimalsInWithdrawal(farmId);
});

final animalHealthSummaryProvider =
    FutureProvider.family<HealthSummary, String>((ref, animalId) async {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.getAnimalHealthSummary(animalId);
    });

final farmHealthStatsProvider = FutureProvider<FarmHealthStats?>((ref) async {
  final repository = ref.watch(healthRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return null;
  return repository.getFarmHealthStats(farmId);
});

// Dashboard stats provider
final dashboardStatsProvider = Provider<AsyncValue<DashboardStats>>((ref) {
  final animals = ref.watch(animalsProvider);
  final inHeatRecords = ref.watch(animalsInHeatProvider);

  return animals.when(
    data: (animalList) {
      final inHeatCount = inHeatRecords.whenOrNull(data: (r) => r.length);

      // Count pregnant animals directly from animal status
      // This ensures pregnant animals show up immediately in the dashboard
      final pregnantCount = animalList
          .where((a) => a.status == AnimalStatus.pregnant)
          .length;

      return AsyncValue.data(
        DashboardStats(
          totalAnimals: animalList.length,
          healthyAnimals: animalList
              .where((a) => a.status == AnimalStatus.healthy)
              .length,
          sickAnimals: animalList
              .where((a) => a.status == AnimalStatus.sick)
              .length,
          pregnantAnimals: pregnantCount,
          animalsInHeat: inHeatCount ?? 0,
          maleCount: animalList.where((a) => a.gender == Gender.male).length,
          femaleCount: animalList
              .where((a) => a.gender == Gender.female)
              .length,
        ),
      );
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

class DashboardStats {
  final int totalAnimals;
  final int healthyAnimals;
  final int sickAnimals;
  final int pregnantAnimals;
  final int animalsInHeat;
  final int maleCount;
  final int femaleCount;

  DashboardStats({
    required this.totalAnimals,
    required this.healthyAnimals,
    required this.sickAnimals,
    required this.pregnantAnimals,
    required this.animalsInHeat,
    required this.maleCount,
    required this.femaleCount,
  });
}

// Financial providers
final transactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchTransactions(farmId);
});

final incomeTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchTransactionsByType(farmId, TransactionType.income);
});

final expenseTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchTransactionsByType(farmId, TransactionType.expense);
});

final animalTransactionsProvider =
    StreamProvider.family<List<Transaction>, String>((ref, animalId) {
      final repository = ref.watch(financialRepositoryProvider);
      return repository.watchAnimalTransactions(animalId);
    });

final financialSummaryProvider = StreamProvider<FinancialSummary?>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value(null);
  return repository.watchFinancialSummary(farmId);
});

/// Real-time monthly financial summary
final monthlyFinancialSummaryProvider =
    StreamProvider.family<FinancialSummary?, DateTime>((ref, month) {
      final repository = ref.watch(financialRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);

      if (farmId == null) return Stream.value(null);
      return repository.watchMonthlyFinancialSummary(
        farmId,
        month.year,
        month.month,
      );
    });

final currentMonthBudgetProvider = StreamProvider<Budget?>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);
  final now = DateTime.now();

  if (farmId == null) return Stream.value(null);
  return repository.watchBudget(farmId, now.year, now.month);
});

final budgetComparisonProvider = StreamProvider<BudgetComparison?>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);
  final now = DateTime.now();

  if (farmId == null) return Stream.value(null);
  return repository.watchBudgetComparison(farmId, now.year, now.month);
});

/// Budget for a specific month (year, month)
final monthBudgetProvider = StreamProvider.family<Budget?, (int, int)>((
  ref,
  params,
) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);
  final (year, month) = params;

  if (farmId == null) return Stream.value(null);
  return repository.watchBudget(farmId, year, month);
});

final monthBudgetWithComparisonProvider =
    StreamProvider.family<BudgetComparison?, (int, int)>((ref, params) {
      final repository = ref.watch(financialRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);
      final (year, month) = params;

      if (farmId == null) return Stream.value(null);
      return repository.watchBudgetComparison(farmId, year, month);
    });

final animalFinancialsProvider =
    FutureProvider.family<AnimalFinancials, String>((ref, animalId) async {
      final repository = ref.watch(financialRepositoryProvider);
      return repository.getAnimalFinancials(animalId);
    });

final reportDateRangeProvider =
    NotifierProvider<ReportDateRangeNotifier, DateTimeRange>(
      ReportDateRangeNotifier.new,
    );

class ReportDateRangeNotifier extends Notifier<DateTimeRange> {
  @override
  DateTimeRange build() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  void setDateRange(DateTimeRange range) {
    state = range;
  }

  void reset() {
    final now = DateTime.now();
    state = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }
}

DateTimeRange _getPreviousPeriod(DateTimeRange current) {
  final duration = current.end.difference(current.start);
  return DateTimeRange(
    start: current.start.subtract(duration).subtract(const Duration(days: 1)),
    end: current.start.subtract(const Duration(days: 1)),
  );
}

final dateRangeFinancialSummaryProvider = StreamProvider<FinancialSummary?>((
  ref,
) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);
  final dateRange = ref.watch(reportDateRangeProvider);

  if (farmId == null) {
    return Stream.value(null);
  }

  return repository.watchFinancialSummary(
    farmId,
    startDate: dateRange.start,
    endDate: dateRange.end,
  );
});

final previousPeriodFinancialSummaryProvider =
    StreamProvider<FinancialSummary?>((ref) {
      final repository = ref.watch(financialRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);
      final dateRange = ref.watch(reportDateRangeProvider);
      final previousRange = _getPreviousPeriod(dateRange);

      if (farmId == null) return Stream.value(null);

      return repository.watchFinancialSummary(
        farmId,
        startDate: previousRange.start,
        endDate: previousRange.end,
      );
    });

final dateRangeTopExpensesProvider = StreamProvider<Map<String, double>>((ref) {
  final repository = ref.watch(financialRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);
  final dateRange = ref.watch(reportDateRangeProvider);

  if (farmId == null) {
    return Stream.value({});
  }

  // Watch transactions and derive top expenses
  return repository
      .watchFinancialSummary(
        farmId,
        startDate: dateRange.start,
        endDate: dateRange.end,
      )
      .map((summary) {
        final sorted = summary.expensesByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return Map.fromEntries(sorted.take(5));
      });
});

final yearlyMonthlySummariesProvider =
    FutureProvider.family<List<FinancialSummary>, int>((ref, year) async {
      final repository = ref.watch(financialRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);

      if (farmId == null) {
        throw Exception('No farm selected. Please select a farm first.');
      }

      try {
        return await repository.getMonthlySummaries(farmId, year);
      } catch (e) {
        throw Exception('Failed to load monthly summaries: $e');
      }
    });

final monthBudgetComparisonProvider =
    StreamProvider.family<BudgetComparison?, (int, int)>((ref, params) {
      final repository = ref.watch(financialRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);
      final (year, month) = params;

      if (farmId == null) {
        return Stream.value(null);
      }

      return repository.watchBudgetComparison(farmId, year, month);
    });

final farmSettingsProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value(null);
  return authRepository.watchFarmSettings(farmId);
});

final farmCurrencyProvider = Provider<CurrencyConfig>((ref) {
  final farmSettings = ref.watch(farmSettingsProvider);

  return farmSettings.when(
    data: (settings) {
      if (settings == null) return CurrencyConfig.fromCurrency(Currency.ugx);
      final currencyCode = settings['currency'] as String?;
      if (currencyCode == null) {
        return CurrencyConfig.fromCurrency(Currency.ugx);
      }
      return CurrencyConfig.fromCode(currencyCode);
    },
    loading: () => CurrencyConfig.fromCurrency(Currency.ugx),
    error: (_, _) => CurrencyConfig.fromCurrency(Currency.ugx),
  );
});

final currencyFormatterProvider = Provider<CurrencyFormatter>((ref) {
  final config = ref.watch(farmCurrencyProvider);
  return CurrencyFormatter(config);
});

final updateFarmCurrencyProvider = FutureProvider.family<void, String>((
  ref,
  currencyCode,
) async {
  final authRepository = ref.read(authRepositoryProvider);
  final farmId = ref.read(activeFarmIdProvider);

  if (farmId == null) throw Exception('No farm selected');
  await authRepository.updateFarmCurrency(farmId, currencyCode);
});

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository();
});

final remindersProvider = StreamProvider<List<Reminder>>((ref) {
  final repository = ref.watch(reminderRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchPendingReminders(farmId);
});

final activeRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  final repository = ref.watch(reminderRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchActiveReminders(farmId);
});

final overdueRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  final repository = ref.watch(reminderRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) return Stream.value([]);
  return repository.watchOverdueReminders(farmId);
});

final animalRemindersProvider = StreamProvider.family<List<Reminder>, String>((
  ref,
  animalId,
) {
  final repository = ref.watch(reminderRepositoryProvider);
  return repository.watchAnimalReminders(animalId);
});

final remindersByTypeProvider =
    StreamProvider.family<List<Reminder>, ReminderType>((ref, type) {
      final repository = ref.watch(reminderRepositoryProvider);
      final farmId = ref.watch(activeFarmIdProvider);

      if (farmId == null) return Stream.value([]);
      return repository.watchRemindersByType(farmId, type);
    });

final activeReminderCountProvider = Provider<AsyncValue<int>>((ref) {
  final reminders = ref.watch(activeRemindersProvider);
  return reminders.whenData((list) => list.length);
});

final reminderSettingsProvider = StreamProvider<ReminderSettings>((ref) {
  final repository = ref.watch(reminderRepositoryProvider);
  final farmId = ref.watch(activeFarmIdProvider);

  if (farmId == null) {
    return Stream.value(ReminderSettings(farmId: ''));
  }
  return repository.watchSettings(farmId);
});

final reminderServiceProvider = Provider<ReminderService>((ref) {
  return ReminderService();
});
