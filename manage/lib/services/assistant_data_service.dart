import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/animal.dart';
import '../models/health_record.dart';
import '../providers/providers.dart';

/// Service to fetch real farm data for the AI Assistant
class AssistantDataService {
  final Ref _ref;

  AssistantDataService(this._ref);

  /// Get animal by tag ID from the active farm
  Future<Animal?> getAnimalByTagId(String tagId) async {
    final farmId = _ref.read(activeFarmIdProvider);
    if (farmId == null) return null;

    final repository = _ref.read(animalRepositoryProvider);
    return repository.getAnimalByTagId(farmId, tagId);
  }

  /// Get all animals from the active farm
  List<Animal> getAllAnimals() {
    final animalsAsync = _ref.read(animalsProvider);
    return animalsAsync.maybeWhen(data: (animals) => animals, orElse: () => []);
  }

  /// Search animals by name or tag (partial match)
  List<Animal> searchAnimals(String query) {
    final animals = getAllAnimals();
    final lowerQuery = query.toLowerCase();
    return animals.where((animal) {
      return animal.tagId.toLowerCase().contains(lowerQuery) ||
          (animal.name?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  /// Get animal statistics for the active farm
  Map<String, dynamic> getAnimalStats() {
    final animals = getAllAnimals();
    final bySpecies = <String, int>{};
    final byStatus = <String, int>{};

    for (final animal in animals) {
      final speciesName = animal.species.displayName;
      bySpecies[speciesName] = (bySpecies[speciesName] ?? 0) + 1;
      byStatus[animal.status.name] = (byStatus[animal.status.name] ?? 0) + 1;
    }

    return {
      'totalCount': animals.length,
      'bySpecies': bySpecies,
      'byStatus': byStatus,
    };
  }

  /// Format animal data for the AI to use in rendering
  Map<String, dynamic> animalToDisplayData(Animal animal) {
    return {
      'name': animal.name,
      'tagId': animal.tagId,
      'species': animal.species.displayName,
      'breed': animal.breed,
      'status': animal.status.name,
    };
  }

  // ==================== HEALTH RECORD METHODS ====================

  /// Get all health records from the active farm
  List<HealthRecord> getAllHealthRecords() {
    final healthAsync = _ref.read(healthRecordsProvider);
    return healthAsync.maybeWhen(data: (records) => records, orElse: () => []);
  }

  /// Wait for health records to load (for initial context building)
  /// Fetches directly from repository instead of polling StreamProvider
  Future<List<HealthRecord>> waitForHealthRecords({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    debugPrint('waitForHealthRecords: Starting direct fetch');

    final farmId = _ref.read(activeFarmIdProvider);
    if (farmId == null) {
      debugPrint('waitForHealthRecords: No active farm ID');
      return [];
    }

    try {
      final repository = _ref.read(healthRepositoryProvider);
      final records = await repository
          .getHealthRecords(farmId)
          .timeout(timeout);
      debugPrint(
        'waitForHealthRecords: Fetched ${records.length} records from repository',
      );
      return records;
    } catch (e) {
      debugPrint('waitForHealthRecords: Error fetching records: $e');
      return [];
    }
  }

  /// Get recent health records (last N records)
  List<HealthRecord> getRecentHealthRecords({int limit = 10}) {
    final records = getAllHealthRecords();
    return records.take(limit).toList();
  }

  /// Get health records for a specific animal by tag ID
  List<HealthRecord> getHealthRecordsForAnimal(String tagId) {
    final records = getAllHealthRecords();
    final lowerTagId = tagId.toLowerCase();
    return records.where((record) {
      return record.animalTagId?.toLowerCase() == lowerTagId;
    }).toList();
  }

  /// Get health records by type
  List<HealthRecord> getHealthRecordsByType(HealthRecordType type) {
    final records = getAllHealthRecords();
    return records.where((record) => record.type == type).toList();
  }

  /// Get upcoming vaccinations (with due dates in the future)
  List<HealthRecord> getUpcomingVaccinations() {
    final records = getAllHealthRecords();
    final now = DateTime.now();
    return records.where((record) {
      return record.type == HealthRecordType.vaccination &&
          record.nextDueDate != null &&
          record.nextDueDate!.isAfter(now);
    }).toList()..sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));
  }

  /// Get overdue vaccinations
  List<HealthRecord> getOverdueVaccinations() {
    final records = getAllHealthRecords();
    final now = DateTime.now();
    return records.where((record) {
      return record.type == HealthRecordType.vaccination &&
          record.nextDueDate != null &&
          record.nextDueDate!.isBefore(now);
    }).toList();
  }

  /// Get animals currently in medication withdrawal period
  List<HealthRecord> getAnimalsInWithdrawal() {
    final records = getAllHealthRecords();
    final now = DateTime.now();
    return records.where((record) {
      return record.withdrawalEndDate != null &&
          record.withdrawalEndDate!.isAfter(now);
    }).toList();
  }

  /// Get pending follow-ups
  List<HealthRecord> getPendingFollowUps() {
    final records = getAllHealthRecords();
    final now = DateTime.now();
    return records.where((record) {
      return record.followUpDate != null &&
          record.followUpDate!.isBefore(now) &&
          record.status != HealthStatus.completed;
    }).toList();
  }

  /// Get health records with a specific status
  List<HealthRecord> getHealthRecordsByStatus(HealthStatus status) {
    final records = getAllHealthRecords();
    return records.where((record) => record.status == status).toList();
  }

  /// Get health statistics for the active farm
  Map<String, dynamic> getHealthStats() {
    final records = getAllHealthRecords();
    final byType = <String, int>{};
    final byStatus = <String, int>{};

    for (final record in records) {
      byType[record.type.displayName] =
          (byType[record.type.displayName] ?? 0) + 1;
      byStatus[record.status.name] = (byStatus[record.status.name] ?? 0) + 1;
    }

    final upcomingVaccinations = getUpcomingVaccinations();
    final overdueVaccinations = getOverdueVaccinations();
    final animalsInWithdrawal = getAnimalsInWithdrawal();
    final pendingFollowUps = getPendingFollowUps();

    return {
      'totalRecords': records.length,
      'byType': byType,
      'byStatus': byStatus,
      'upcomingVaccinationsCount': upcomingVaccinations.length,
      'overdueVaccinationsCount': overdueVaccinations.length,
      'animalsInWithdrawalCount': animalsInWithdrawal.length,
      'pendingFollowUpsCount': pendingFollowUps.length,
    };
  }

  /// Format health record data for the AI to use in rendering
  Map<String, dynamic> healthRecordToDisplayData(HealthRecord record) {
    return {
      'id': record.id,
      'animalTagId': record.animalTagId,
      'type': record.type.displayName,
      'title': record.title,
      'date': record.date.toIso8601String().split('T')[0],
      'status': record.status.name,
      'severity': record.severity?.name,
      'description': record.description,
      'diagnosis': record.diagnosis,
      'treatment': record.treatment,
      'vaccineName': record.vaccineName,
      'medicationName': record.medicationName,
      'dosage': record.dosage,
      'nextDueDate': record.nextDueDate?.toIso8601String().split('T')[0],
      'followUpDate': record.followUpDate?.toIso8601String().split('T')[0],
      'withdrawalEndDate': record.withdrawalEndDate?.toIso8601String().split(
        'T',
      )[0],
      'veterinarianName': record.veterinarianName,
      'cost': record.cost,
    };
  }

  /// Search health records by keyword (searches title, description, diagnosis, treatment)
  List<HealthRecord> searchHealthRecords(String query) {
    final records = getAllHealthRecords();
    final lowerQuery = query.toLowerCase();
    return records.where((record) {
      return record.title.toLowerCase().contains(lowerQuery) ||
          (record.description?.toLowerCase().contains(lowerQuery) ?? false) ||
          (record.diagnosis?.toLowerCase().contains(lowerQuery) ?? false) ||
          (record.treatment?.toLowerCase().contains(lowerQuery) ?? false) ||
          (record.vaccineName?.toLowerCase().contains(lowerQuery) ?? false) ||
          (record.medicationName?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }
}

/// Provider for the assistant data service
final assistantDataServiceProvider = Provider<AssistantDataService>((ref) {
  return AssistantDataService(ref);
});
