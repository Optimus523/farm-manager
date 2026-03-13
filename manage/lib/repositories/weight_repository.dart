import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/weight_record.dart';
import '../config/supabase_config.dart';

class WeightRepository {
  final SupabaseClient _client;
  static const String _table = 'weight_records';

  WeightRepository({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  /// Watch all weight records for a farm
  Stream<List<WeightRecord>> watchWeightRecords(String farmId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('farm_id', farmId)
        .order('date', ascending: false)
        .map(
          (data) =>
              data.map((json) => WeightRecord.fromSupabase(json)).toList(),
        );
  }

  /// Get weight records with pagination
  Future<List<WeightRecord>> getWeightRecordsPaginated(
    String farmId, {
    required int limit,
    required int offset,
  }) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('farm_id', farmId)
        .order('date', ascending: false)
        .range(offset, offset + limit - 1);
    return (response as List)
        .map((json) => WeightRecord.fromSupabase(json))
        .toList();
  }

  /// Watch weight records for a specific animal
  Stream<List<WeightRecord>> watchWeightRecordsForAnimal(String animalId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('animal_id', animalId)
        .order('date', ascending: false)
        .map(
          (data) =>
              data.map((json) => WeightRecord.fromSupabase(json)).toList(),
        );
  }

  /// Get weight records for a specific animal with pagination
  Future<List<WeightRecord>> getWeightRecordsForAnimalPaginated(
    String animalId, {
    required int limit,
    required int offset,
  }) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('animal_id', animalId)
        .order('date', ascending: false)
        .range(offset, offset + limit - 1);
    return (response as List)
        .map((json) => WeightRecord.fromSupabase(json))
        .toList();
  }

  /// Get latest weight for an animal
  Future<WeightRecord?> getLatestWeightForAnimal(String animalId) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('animal_id', animalId)
        .order('date', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return WeightRecord.fromSupabase(response);
  }

  /// Add a new weight record
  Future<String> addWeightRecord(WeightRecord record) async {
    final response = await _client
        .from(_table)
        .insert(record.toSupabase())
        .select('id')
        .single();
    return response['id'] as String;
  }

  /// Update a weight record
  Future<void> updateWeightRecord(WeightRecord record) async {
    await _client.from(_table).update(record.toSupabase()).eq('id', record.id);
  }

  /// Delete a weight record
  Future<void> deleteWeightRecord(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  /// Get all weight records for a farm (direct query, not stream)
  Future<List<WeightRecord>> getWeightRecords(String farmId) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('farm_id', farmId)
        .order('date', ascending: false);
    return (response as List)
        .map((json) => WeightRecord.fromSupabase(json))
        .toList();
  }

  /// Get weight history for an animal
  Future<List<WeightRecord>> getWeightHistoryForAnimal(String animalId) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('animal_id', animalId)
        .order('date');
    return (response as List)
        .map((json) => WeightRecord.fromSupabase(json))
        .toList();
  }

  /// Get weight gain over a period
  Future<double?> getWeightGain(String animalId, int days) async {
    final now = DateTime.now();
    final pastDate = now.subtract(Duration(days: days));

    final response = await _client
        .from(_table)
        .select()
        .eq('animal_id', animalId)
        .gte('date', pastDate.toIso8601String())
        .order('date');

    final records = response as List;
    if (records.length < 2) return null;

    final firstWeight = (records.first['weight'] as num).toDouble();
    final lastWeight = (records.last['weight'] as num).toDouble();

    return lastWeight - firstWeight;
  }
}
