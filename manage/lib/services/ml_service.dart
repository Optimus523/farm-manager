import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ml_models.dart';
import '../utils/env_helper.dart';

/// ML API Service for weight predictions and health analytics.
///
/// Connects to the backend specified by the `BASE_URL` environment variable.
/// Set `BASE_URL` in your `.env` file or via `--dart-define=BASE_URL=...`
///
/// Note: Free tier backends (e.g., Render) may spin down after inactivity.
/// Cold starts can take 50+ seconds. Use [wakeUp] to pre-warm the backend.
class MLService {
  /// Default production backend URL (used when BASE_URL env var is not set)
  static const String _defaultBaseUrl =
      'https://farm-manager-nxvx.onrender.com';

  /// Timeout for cold start requests (backend may need to spin up)
  static const Duration coldStartTimeout = Duration(seconds: 90);

  /// Timeout for normal requests (backend is already warm)
  static const Duration normalTimeout = Duration(seconds: 30);

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Whether the backend has been confirmed as active this session
  bool _isWarm = false;

  /// Creates an ML service instance.
  ///
  /// [baseUrl] - The backend API URL. Defaults to `BASE_URL` env variable,
  ///             falls back to production URL if not set.
  /// [client] - Optional HTTP client for testing.
  /// [timeout] - Request timeout duration. Defaults to [coldStartTimeout]
  ///             to handle free-tier backend spin-up delays.
  MLService({
    String? baseUrl,
    http.Client? client,
    this.timeout = coldStartTimeout,
  }) : baseUrl = baseUrl ?? EnvHelper.get('BASE_URL') ?? _defaultBaseUrl,
       _client = client ?? http.Client();

  /// Wake up the backend if it's sleeping (free tier spin-down).
  /// Call this on app startup to minimize delay for user requests.
  /// Returns true if backend is responsive, false otherwise.
  Future<bool> wakeUp() async {
    try {
      final health = await checkHealth();
      _isWarm = health.isHealthy;
      return _isWarm;
    } catch (e) {
      _isWarm = false;
      return false;
    }
  }

  /// Get the appropriate timeout based on whether backend is warm
  Duration get _currentTimeout => _isWarm ? normalTimeout : timeout;

  /// Check if the API server is running
  Future<MLHealthStatus> checkHealth() async {
    try {
      final response = await _get('/health');
      return MLHealthStatus.fromJson(response);
    } catch (e) {
      return MLHealthStatus(
        status: 'offline',
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  /// Compute weight features for a single animal
  Future<WeightFeatures> computeWeightFeatures(String animalId) async {
    final response = await _get('/api/v1/features/weight/$animalId');
    return WeightFeatures.fromJson(response);
  }

  /// Compute health features for a single animal
  Future<HealthFeatures> computeHealthFeatures(String animalId) async {
    final response = await _get('/api/v1/features/health/$animalId');
    return HealthFeatures.fromJson(response);
  }

  /// Compute all features (weight + health) for a single animal
  Future<CombinedFeatures> computeCombinedFeatures(String animalId) async {
    final response = await _get('/api/v1/features/animal/$animalId');
    return CombinedFeatures.fromJson(response);
  }

  /// Compute features for multiple animals (batch)
  Future<BatchJobStatus> computeBatchFeatures({
    required List<String> animalIds,
    List<String> featureTypes = const ['weight', 'health'],
  }) async {
    final response = await _post('/api/v1/pipeline/compute-batch', {
      'animal_ids': animalIds,
      'feature_types': featureTypes,
    });
    return BatchJobStatus.fromJson(response);
  }

  /// Check batch job status
  Future<BatchJobStatus> getJobStatus(String jobId) async {
    final response = await _get('/api/v1/pipeline/jobs/$jobId');
    return BatchJobStatus.fromJson(response);
  }

  /// Predict future weight for a single animal
  Future<MLPredictionResponse> predictWeight({
    required Map<String, dynamic> features,
    int horizonDays = 14,
  }) async {
    final response = await _post('/api/v1/models/weight/predict', {
      'features': features,
      'horizon_days': horizonDays,
    });
    return MLPredictionResponse.fromJson(response);
  }

  /// Predict weight for multiple animals (batch)
  Future<MLBatchPredictionResponse> predictWeightBatch({
    required List<Map<String, dynamic>> featuresList,
    int horizonDays = 14,
  }) async {
    final response = await _post('/api/v1/models/weight/predict-batch', {
      'features_list': featuresList,
      'horizon_days': horizonDays,
    });
    return MLBatchPredictionResponse.fromJson(response);
  }

  /// Get SHAP explanation for a prediction
  Future<MLExplanationResponse> explainPrediction({
    required Map<String, dynamic> features,
    int horizonDays = 14,
  }) async {
    final response = await _post('/api/v1/models/weight/explain', {
      'features': features,
      'horizon_days': horizonDays,
    });
    return MLExplanationResponse.fromJson(response);
  }

  /// Get global feature importance
  Future<MLGlobalExplanation> getGlobalExplanation() async {
    final response = await _get('/api/v1/models/weight/explain/global');
    return MLGlobalExplanation.fromJson(response);
  }

  /// Get information about the current model
  Future<MLModelInfo> getModelInfo() async {
    final response = await _get('/api/v1/models/weight/info');
    return MLModelInfo.fromJson(response);
  }

  /// Get feature importance from the model
  Future<MLFeatureImportanceResponse> getFeatureImportance() async {
    final response = await _get('/api/v1/models/weight/feature-importance');
    return MLFeatureImportanceResponse.fromJson(response);
  }

  // =========================================================================
  // Health Model Endpoints
  // =========================================================================

  /// Predict health risk for a single animal
  Future<MLHealthPredictionResponse> predictHealthRisk({
    required Map<String, dynamic> features,
    int horizonDays = 14,
  }) async {
    final response = await _post('/api/v1/models/health/predict', {
      'features': features,
      'horizon_days': horizonDays,
    });
    return MLHealthPredictionResponse.fromJson(response);
  }

  /// Predict health risk for multiple animals (batch)
  Future<MLHealthBatchPredictionResponse> predictHealthRiskBatch({
    required List<Map<String, dynamic>> featuresList,
    int horizonDays = 14,
  }) async {
    final response = await _post('/api/v1/models/health/predict-batch', {
      'features_list': featuresList,
      'horizon_days': horizonDays,
    });
    return MLHealthBatchPredictionResponse.fromJson(response);
  }

  /// Get information about the health model
  Future<MLHealthModelInfo> getHealthModelInfo() async {
    final response = await _get('/api/v1/models/health/info');
    return MLHealthModelInfo.fromJson(response);
  }

  /// Get SHAP explanation for a health prediction
  Future<MLExplanationResponse> explainHealthPrediction({
    required Map<String, dynamic> features,
    int horizonDays = 14,
  }) async {
    final response = await _post('/api/v1/models/health/explain', {
      'features': features,
      'horizon_days': horizonDays,
    });
    return MLExplanationResponse.fromJson(response);
  }

  /// Get MLflow status
  Future<MLFlowStatus> getMLflowStatus() async {
    final response = await _get('/api/v1/mlflow/status');
    return MLFlowStatus.fromJson(response);
  }

  /// Get recent training runs
  Future<MLFlowRunsResponse> getTrainingRuns() async {
    final response = await _get('/api/v1/mlflow/runs');
    return MLFlowRunsResponse.fromJson(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _client.get(uri).timeout(_currentTimeout);
    _isWarm = true; // Backend responded, mark as warm
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_currentTimeout);
    _isWarm = true; // Backend responded, mark as warm
    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    // Handle error responses
    final errorBody = jsonDecode(response.body);
    final detail = errorBody['detail'] ?? 'Unknown error';
    throw MLServiceException(
      statusCode: response.statusCode,
      message: detail is String ? detail : jsonEncode(detail),
    );
  }

  void dispose() {
    _client.close();
  }
}

/// Exception thrown by MLService
class MLServiceException implements Exception {
  final int statusCode;
  final String message;

  MLServiceException({required this.statusCode, required this.message});

  @override
  String toString() => 'MLServiceException($statusCode): $message';
}

/// Health check response
class MLHealthStatus {
  final String status;
  final DateTime timestamp;
  final String? error;

  MLHealthStatus({required this.status, required this.timestamp, this.error});

  bool get isHealthy => status == 'healthy';

  factory MLHealthStatus.fromJson(Map<String, dynamic> json) {
    return MLHealthStatus(
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Database health response
class MLDatabaseStatus {
  final String status;
  final List<String> tables;
  final Map<String, int> recordCounts;

  MLDatabaseStatus({
    required this.status,
    required this.tables,
    required this.recordCounts,
  });

  bool get isConnected => status == 'connected';

  factory MLDatabaseStatus.fromJson(Map<String, dynamic> json) {
    return MLDatabaseStatus(
      status: json['status'] as String,
      tables: List<String>.from(json['tables'] as List),
      recordCounts: Map<String, int>.from(
        (json['record_counts'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      ),
    );
  }
}

/// Weight features response
class WeightFeatures {
  final String animalId;
  final DateTime computedAt;
  final Map<String, dynamic> features;

  WeightFeatures({
    required this.animalId,
    required this.computedAt,
    required this.features,
  });

  double? get currentWeight => features['wf_current_weight'] as double?;
  double? get adg7d => features['wf_adg_7d'] as double?;
  double? get adg30d => features['wf_adg_30d'] as double?;
  double? get adgLifetime => features['wf_adg_lifetime'] as double?;
  double? get weightChange7d => features['wf_weight_change_7d'] as double?;
  double? get weightChange30d => features['wf_weight_change_30d'] as double?;

  factory WeightFeatures.fromJson(Map<String, dynamic> json) {
    return WeightFeatures(
      animalId: json['animal_id'] as String,
      computedAt: DateTime.parse(json['computed_at'] as String),
      features: json['features'] as Map<String, dynamic>,
    );
  }
}

/// Health features response
class HealthFeatures {
  final String animalId;
  final DateTime computedAt;
  final Map<String, dynamic> features;

  HealthFeatures({
    required this.animalId,
    required this.computedAt,
    required this.features,
  });

  int? get healthScore => (features['hf_health_score'] as num?)?.toInt();
  int? get overdueVaccinations =>
      (features['hf_overdue_vaccinations'] as num?)?.toInt();
  bool get hasActivetreatment =>
      features['hf_active_treatment'] as bool? ?? false;
  bool get inWithdrawalPeriod =>
      features['hf_in_withdrawal_period'] as bool? ?? false;

  factory HealthFeatures.fromJson(Map<String, dynamic> json) {
    return HealthFeatures(
      animalId: json['animal_id'] as String,
      computedAt: DateTime.parse(json['computed_at'] as String),
      features: json['features'] as Map<String, dynamic>,
    );
  }
}

/// Combined features response
class CombinedFeatures {
  final String animalId;
  final DateTime computedAt;
  final Map<String, dynamic> weightFeatures;
  final Map<String, dynamic> healthFeatures;
  final AnimalMetadata metadata;

  CombinedFeatures({
    required this.animalId,
    required this.computedAt,
    required this.weightFeatures,
    required this.healthFeatures,
    required this.metadata,
  });

  /// Get all features merged for prediction
  Map<String, dynamic> get allFeatures => {
    ...weightFeatures,
    ...healthFeatures,
    'species': metadata.species,
    'breed': metadata.breed,
    'gender': metadata.gender,
  };

  factory CombinedFeatures.fromJson(Map<String, dynamic> json) {
    return CombinedFeatures(
      animalId: json['animal_id'] as String,
      computedAt: DateTime.parse(json['computed_at'] as String),
      weightFeatures: json['weight_features'] as Map<String, dynamic>,
      healthFeatures: json['health_features'] as Map<String, dynamic>,
      metadata: AnimalMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
    );
  }
}

class AnimalMetadata {
  final String species;
  final String? breed;
  final String? gender;
  final DateTime? birthDate;
  final int? ageDays;

  AnimalMetadata({
    required this.species,
    this.breed,
    this.gender,
    this.birthDate,
    this.ageDays,
  });

  factory AnimalMetadata.fromJson(Map<String, dynamic> json) {
    return AnimalMetadata(
      species: json['species'] as String,
      breed: json['breed'] as String?,
      gender: json['gender'] as String?,
      birthDate: json['birth_date'] != null
          ? DateTime.parse(json['birth_date'] as String)
          : null,
      ageDays: (json['age_days'] as num?)?.toInt(),
    );
  }
}

/// Batch job status
class BatchJobStatus {
  final String jobId;
  final String status;
  final int total;
  final int completed;
  final int? failed;
  final String? message;
  final Map<String, dynamic>? results;

  BatchJobStatus({
    required this.jobId,
    required this.status,
    required this.total,
    required this.completed,
    this.failed,
    this.message,
    this.results,
  });

  bool get isCompleted => status == 'completed';
  bool get isProcessing => status == 'processing';
  double get progress => total > 0 ? completed / total : 0;

  factory BatchJobStatus.fromJson(Map<String, dynamic> json) {
    return BatchJobStatus(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      total: (json['total'] as num).toInt(),
      completed: (json['completed'] as num).toInt(),
      failed: (json['failed'] as num?)?.toInt(),
      message: json['message'] as String?,
      results: json['results'] as Map<String, dynamic>?,
    );
  }
}

/// Single prediction response
class MLPredictionResponse {
  final double predictedWeight;
  final int horizonDays;
  final double confidence;
  final double currentWeight;
  final double predictedGain;

  MLPredictionResponse({
    required this.predictedWeight,
    required this.horizonDays,
    required this.confidence,
    required this.currentWeight,
    required this.predictedGain,
  });

  ConfidenceLevel get confidenceLevel {
    if (confidence > 0.85) return ConfidenceLevel.high;
    if (confidence > 0.7) return ConfidenceLevel.medium;
    return ConfidenceLevel.low;
  }

  factory MLPredictionResponse.fromJson(Map<String, dynamic> json) {
    return MLPredictionResponse(
      predictedWeight: (json['predicted_weight'] as num).toDouble(),
      horizonDays: (json['horizon_days'] as num).toInt(),
      confidence: (json['confidence'] as num).toDouble(),
      currentWeight: (json['current_weight'] as num).toDouble(),
      predictedGain: (json['predicted_gain'] as num).toDouble(),
    );
  }
}

/// Batch prediction response
class MLBatchPredictionResponse {
  final List<MLPredictionResponse> predictions;
  final int count;

  MLBatchPredictionResponse({required this.predictions, required this.count});

  factory MLBatchPredictionResponse.fromJson(Map<String, dynamic> json) {
    return MLBatchPredictionResponse(
      predictions: (json['predictions'] as List)
          .map((p) => MLPredictionResponse.fromJson(p as Map<String, dynamic>))
          .toList(),
      count: (json['count'] as num).toInt(),
    );
  }
}

/// SHAP explanation response
class MLExplanationResponse {
  final double predictedWeight;
  final int horizonDays;
  final double currentWeight;
  final double predictedGain;
  final double baseValue;
  final MLExplanation explanation;

  MLExplanationResponse({
    required this.predictedWeight,
    required this.horizonDays,
    required this.currentWeight,
    required this.predictedGain,
    required this.baseValue,
    required this.explanation,
  });

  factory MLExplanationResponse.fromJson(Map<String, dynamic> json) {
    return MLExplanationResponse(
      predictedWeight: (json['predicted_weight'] as num).toDouble(),
      horizonDays: (json['horizon_days'] as num).toInt(),
      currentWeight: (json['current_weight'] as num).toDouble(),
      predictedGain: (json['predicted_gain'] as num).toDouble(),
      baseValue: (json['base_value'] as num).toDouble(),
      explanation: MLExplanation.fromJson(
        json['explanation'] as Map<String, dynamic>,
      ),
    );
  }
}

class MLExplanation {
  final String summary;
  final List<MLFactor> positiveFactors;
  final List<MLFactor> negativeFactors;

  MLExplanation({
    required this.summary,
    required this.positiveFactors,
    required this.negativeFactors,
  });

  factory MLExplanation.fromJson(Map<String, dynamic> json) {
    return MLExplanation(
      summary: json['summary'] as String,
      positiveFactors: (json['positive_factors'] as List)
          .map((f) => MLFactor.fromJson(f as Map<String, dynamic>))
          .toList(),
      negativeFactors: (json['negative_factors'] as List)
          .map((f) => MLFactor.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MLFactor {
  final String feature;
  final dynamic value;
  final double contribution;
  final String direction;

  MLFactor({
    required this.feature,
    required this.value,
    required this.contribution,
    required this.direction,
  });

  /// Get human-readable feature name
  String get displayName => _featureDisplayNames[feature] ?? feature;

  /// Get explanation for users
  String get userExplanation =>
      _featureExplanations[feature] ?? 'Affects weight prediction';

  bool get isPositive => direction == 'increases';

  static const _featureDisplayNames = {
    'wf_current_weight': 'Current Weight',
    'wf_adg_lifetime': 'Lifetime Growth Rate',
    'wf_weight_velocity_30d': '30-Day Growth Speed',
    'wf_weight_std_30d': 'Weight Variability',
    'wf_weight_change_7d': 'Weekly Weight Change',
    'wf_weight_7d_ago': 'Weight 7 Days Ago',
    'horizon_days': 'Prediction Period',
    'hf_health_score': 'Health Score',
    'hf_vaccination_count_total': 'Vaccinations',
    'species_encoded': 'Species',
    'gender_encoded': 'Gender',
  };

  static const _featureExplanations = {
    'wf_current_weight': 'Heavier animals tend to gain more weight',
    'wf_adg_lifetime': 'Consistent historical growth supports prediction',
    'wf_weight_velocity_30d': 'Recent growth momentum',
    'wf_weight_std_30d': 'Inconsistent weights reduce prediction confidence',
    'wf_weight_change_7d': 'Recent weight trend (gain or loss)',
    'wf_weight_7d_ago': 'Reference point for weekly comparison',
    'horizon_days': 'Longer periods allow more growth',
    'hf_health_score': 'Healthy animals grow better',
    'hf_vaccination_count_total': 'Well-vaccinated animals are healthier',
    'species_encoded': 'Different species have different growth rates',
    'gender_encoded': 'Males and females may grow differently',
  };

  factory MLFactor.fromJson(Map<String, dynamic> json) {
    return MLFactor(
      feature: json['feature'] as String,
      value: json['value'],
      contribution: (json['contribution'] as num).toDouble(),
      direction: json['direction'] as String,
    );
  }
}

/// Global feature importance
class MLGlobalExplanation {
  final int sampleSize;
  final double baseValue;
  final List<String> topFeatures;
  final Map<String, MLFeatureStats> featureImportance;
  final String summary;

  MLGlobalExplanation({
    required this.sampleSize,
    required this.baseValue,
    required this.topFeatures,
    required this.featureImportance,
    required this.summary,
  });

  factory MLGlobalExplanation.fromJson(Map<String, dynamic> json) {
    final featureImportanceMap = <String, MLFeatureStats>{};
    final rawImportance = json['feature_importance'] as Map<String, dynamic>;
    for (final entry in rawImportance.entries) {
      featureImportanceMap[entry.key] = MLFeatureStats.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return MLGlobalExplanation(
      sampleSize: (json['sample_size'] as num).toInt(),
      baseValue: (json['base_value'] as num).toDouble(),
      topFeatures: List<String>.from(json['top_features'] as List),
      featureImportance: featureImportanceMap,
      summary: json['summary'] as String,
    );
  }
}

class MLFeatureStats {
  final double meanAbsShap;
  final double stdShap;
  final double minShap;
  final double maxShap;

  MLFeatureStats({
    required this.meanAbsShap,
    required this.stdShap,
    required this.minShap,
    required this.maxShap,
  });

  factory MLFeatureStats.fromJson(Map<String, dynamic> json) {
    return MLFeatureStats(
      meanAbsShap: (json['mean_abs_shap'] as num).toDouble(),
      stdShap: (json['std_shap'] as num).toDouble(),
      minShap: (json['min_shap'] as num).toDouble(),
      maxShap: (json['max_shap'] as num).toDouble(),
    );
  }
}

/// Model info response
class MLModelInfo {
  final String status;
  final DateTime? trainedAt;
  final int? samples;
  final int? features;
  final Map<String, dynamic>? trainMetrics;
  final Map<String, dynamic>? testMetrics;
  final Map<String, int>? topFeatures;

  MLModelInfo({
    required this.status,
    this.trainedAt,
    this.samples,
    this.features,
    this.trainMetrics,
    this.testMetrics,
    this.topFeatures,
  });

  bool get isLoaded => status == 'loaded';

  double? get accuracy {
    final r2 = testMetrics?['r2'] as num?;
    return r2?.toDouble();
  }

  double? get mae => (testMetrics?['mae'] as num?)?.toDouble();

  factory MLModelInfo.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] as Map<String, dynamic>?;
    return MLModelInfo(
      status: json['status'] as String,
      trainedAt: json['trained_at'] != null
          ? DateTime.parse(json['trained_at'] as String)
          : null,
      samples: (json['samples'] as num?)?.toInt(),
      features: (json['features'] as num?)?.toInt(),
      trainMetrics: metrics?['train'] as Map<String, dynamic>?,
      testMetrics: metrics?['test'] as Map<String, dynamic>?,
      topFeatures: json['top_features'] != null
          ? Map<String, int>.from(
              (json['top_features'] as Map).map(
                (k, v) => MapEntry(k as String, (v as num).toInt()),
              ),
            )
          : null,
    );
  }
}

/// Feature importance response
class MLFeatureImportanceResponse {
  final Map<String, int> featureImportance;
  final String modelType;

  MLFeatureImportanceResponse({
    required this.featureImportance,
    required this.modelType,
  });

  /// Get sorted features by importance
  List<MapEntry<String, int>> get sortedFeatures {
    final entries = featureImportance.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  factory MLFeatureImportanceResponse.fromJson(Map<String, dynamic> json) {
    return MLFeatureImportanceResponse(
      featureImportance: Map<String, int>.from(
        (json['feature_importance'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      ),
      modelType: json['model_type'] as String,
    );
  }
}

/// MLflow status
class MLFlowStatus {
  final String trackingUri;
  final String experimentName;
  final String experimentId;
  final String status;

  MLFlowStatus({
    required this.trackingUri,
    required this.experimentName,
    required this.experimentId,
    required this.status,
  });

  bool get isConnected => status == 'connected';

  factory MLFlowStatus.fromJson(Map<String, dynamic> json) {
    return MLFlowStatus(
      trackingUri: json['tracking_uri'] as String,
      experimentName: json['experiment_name'] as String,
      experimentId: json['experiment_id'] as String,
      status: json['status'] as String,
    );
  }
}

/// MLflow runs response
class MLFlowRunsResponse {
  final List<MLFlowRun> runs;
  final int count;
  final String experiment;

  MLFlowRunsResponse({
    required this.runs,
    required this.count,
    required this.experiment,
  });

  factory MLFlowRunsResponse.fromJson(Map<String, dynamic> json) {
    return MLFlowRunsResponse(
      runs: (json['runs'] as List)
          .map((r) => MLFlowRun.fromJson(r as Map<String, dynamic>))
          .toList(),
      count: (json['count'] as num).toInt(),
      experiment: json['experiment'] as String,
    );
  }
}

class MLFlowRun {
  final String runId;
  final String runName;
  final String status;
  final DateTime startTime;
  final Map<String, double> metrics;

  MLFlowRun({
    required this.runId,
    required this.runName,
    required this.status,
    required this.startTime,
    required this.metrics,
  });

  double? get testMae => metrics['test_mae'];
  double? get testR2 => metrics['test_r2'];

  factory MLFlowRun.fromJson(Map<String, dynamic> json) {
    return MLFlowRun(
      runId: json['run_id'] as String,
      runName: json['run_name'] as String,
      status: json['status'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      metrics: Map<String, double>.from(
        (json['metrics'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
      ),
    );
  }
}

/// Health model prediction response
class MLHealthPredictionResponse {
  final int horizonDays;
  final int currentHealthScore;
  final double predictedRiskScore;
  final String riskLevel;
  final double treatmentProbability;
  final bool treatmentLikely;
  final double predictedScoreDelta;
  final bool healthDeclining;
  final String trend;

  MLHealthPredictionResponse({
    required this.horizonDays,
    required this.currentHealthScore,
    required this.predictedRiskScore,
    required this.riskLevel,
    required this.treatmentProbability,
    required this.treatmentLikely,
    required this.predictedScoreDelta,
    required this.healthDeclining,
    required this.trend,
  });

  factory MLHealthPredictionResponse.fromJson(Map<String, dynamic> json) {
    return MLHealthPredictionResponse(
      horizonDays: (json['horizon_days'] as num).toInt(),
      currentHealthScore: (json['current_health_score'] as num).toInt(),
      predictedRiskScore: (json['predicted_risk_score'] as num).toDouble(),
      riskLevel: json['risk_level'] as String,
      treatmentProbability: (json['treatment_probability'] as num).toDouble(),
      treatmentLikely: json['treatment_likely'] as bool,
      predictedScoreDelta: (json['predicted_score_delta'] as num).toDouble(),
      healthDeclining: json['health_declining'] as bool,
      trend: json['trend'] as String,
    );
  }
}

/// Batch health prediction response
class MLHealthBatchPredictionResponse {
  final List<MLHealthPredictionResponse> predictions;
  final int count;

  MLHealthBatchPredictionResponse({
    required this.predictions,
    required this.count,
  });

  factory MLHealthBatchPredictionResponse.fromJson(Map<String, dynamic> json) {
    return MLHealthBatchPredictionResponse(
      predictions: (json['predictions'] as List)
          .map(
            (p) =>
                MLHealthPredictionResponse.fromJson(p as Map<String, dynamic>),
          )
          .toList(),
      count: (json['count'] as num).toInt(),
    );
  }
}

/// Health model info response
class MLHealthModelInfo {
  final String status;
  final bool hasRiskModel;
  final bool hasTreatmentModel;
  final bool hasDeclineModel;
  final DateTime? trainedAt;
  final int? samples;
  final int? featureCount;

  MLHealthModelInfo({
    required this.status,
    required this.hasRiskModel,
    required this.hasTreatmentModel,
    required this.hasDeclineModel,
    this.trainedAt,
    this.samples,
    this.featureCount,
  });

  bool get isLoaded => status == 'loaded';
  bool get hasAnyModel => hasRiskModel || hasTreatmentModel || hasDeclineModel;

  factory MLHealthModelInfo.fromJson(Map<String, dynamic> json) {
    return MLHealthModelInfo(
      status: json['status'] as String,
      hasRiskModel: json['risk_model'] as bool? ?? false,
      hasTreatmentModel: json['treatment_model'] as bool? ?? false,
      hasDeclineModel: json['decline_model'] as bool? ?? false,
      trainedAt: json['trained_at'] != null
          ? DateTime.parse(json['trained_at'] as String)
          : null,
      samples: (json['samples'] as num?)?.toInt(),
      featureCount: (json['feature_count'] as num?)?.toInt(),
    );
  }
}
