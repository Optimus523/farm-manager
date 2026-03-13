import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ml_models.dart';
import '../models/animal.dart';
import '../models/weight_record.dart';
import '../services/ml_service.dart';
import 'providers.dart';

// =============================================================================
// ML Service Provider
// =============================================================================

/// Provider for the ML Service instance.
/// Uses the `BASE_URL` environment variable for backend connection.
final mlServiceProvider = Provider<MLService>((ref) {
  final service = MLService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider to pre-warm the backend on free-tier hosts (e.g., Render).
/// Call this early in the app lifecycle to minimize cold start delays.
/// Returns true if backend is responsive, false otherwise.
final mlWarmUpProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(mlServiceProvider);
  return service.wakeUp();
});

/// Provider to check API health status
final mlHealthProvider = FutureProvider<MLHealthStatus>((ref) async {
  final service = ref.watch(mlServiceProvider);
  return service.checkHealth();
});

/// Provider for model info
final mlModelInfoProvider = FutureProvider<MLModelInfo>((ref) async {
  final service = ref.watch(mlServiceProvider);
  return service.getModelInfo();
});

/// Provider for health model info
final mlHealthModelInfoProvider = FutureProvider<MLHealthModelInfo>((
  ref,
) async {
  final service = ref.watch(mlServiceProvider);
  return service.getHealthModelInfo();
});

// =============================================================================
// ML Analytics State
// =============================================================================

/// State for ML Analytics data
class MLAnalyticsState {
  final bool isLoading;
  final String? error;
  final bool isConnected;
  final HerdWeightSummary? weightSummary;
  final HerdHealthSummary? healthSummary;
  final List<WeightPrediction> predictions;
  final List<AnimalHealthScore> healthScores;
  final List<AIInsight> insights;
  final ModelMetrics? modelMetrics;
  final ForecastHorizon selectedHorizon;
  final String selectedPeriod;
  final MLModelInfo? modelInfo;

  const MLAnalyticsState({
    this.isLoading = false,
    this.error,
    this.isConnected = false,
    this.weightSummary,
    this.healthSummary,
    this.predictions = const [],
    this.healthScores = const [],
    this.insights = const [],
    this.modelMetrics,
    this.selectedHorizon = ForecastHorizon.days14,
    this.selectedPeriod = '7d',
    this.modelInfo,
  });

  MLAnalyticsState copyWith({
    bool? isLoading,
    String? error,
    bool? isConnected,
    HerdWeightSummary? weightSummary,
    HerdHealthSummary? healthSummary,
    List<WeightPrediction>? predictions,
    List<AnimalHealthScore>? healthScores,
    List<AIInsight>? insights,
    ModelMetrics? modelMetrics,
    ForecastHorizon? selectedHorizon,
    String? selectedPeriod,
    MLModelInfo? modelInfo,
  }) {
    return MLAnalyticsState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isConnected: isConnected ?? this.isConnected,
      weightSummary: weightSummary ?? this.weightSummary,
      healthSummary: healthSummary ?? this.healthSummary,
      predictions: predictions ?? this.predictions,
      healthScores: healthScores ?? this.healthScores,
      insights: insights ?? this.insights,
      modelMetrics: modelMetrics ?? this.modelMetrics,
      selectedHorizon: selectedHorizon ?? this.selectedHorizon,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      modelInfo: modelInfo ?? this.modelInfo,
    );
  }

  /// Check if data has been loaded
  bool get hasData =>
      weightSummary != null ||
      healthSummary != null ||
      predictions.isNotEmpty ||
      healthScores.isNotEmpty;

  /// Get predictions for a specific animal
  List<WeightPrediction> predictionsForAnimal(String animalId) =>
      predictions.where((p) => p.animalId == animalId).toList();

  /// Get health score for a specific animal
  AnimalHealthScore? healthScoreForAnimal(String animalId) {
    final matches = healthScores.where((h) => h.animalId == animalId);
    return matches.isEmpty ? null : matches.first;
  }

  /// Get at-risk animals
  List<AnimalHealthScore> get atRiskAnimals =>
      healthScores
          .where(
            (h) =>
                h.riskLevel == RiskLevel.moderate ||
                h.riskLevel == RiskLevel.high ||
                h.riskLevel == RiskLevel.critical,
          )
          .toList()
        ..sort((a, b) => a.healthScore.compareTo(b.healthScore));

  /// Get market-ready animals (predicted weight above threshold)
  List<WeightPrediction> get marketReadyPredictions => predictions
      .where((p) => p.willReachTarget && p.predictedWeight >= 100)
      .toList();
}

// =============================================================================
// ML Analytics Notifier
// =============================================================================

/// Main ML Analytics provider
final mlAnalyticsProvider =
    NotifierProvider<MLAnalyticsNotifier, MLAnalyticsState>(
      MLAnalyticsNotifier.new,
    );

class MLAnalyticsNotifier extends Notifier<MLAnalyticsState> {
  /// Cache of features per animal for SHAP explanations
  final Map<String, Map<String, dynamic>> _animalFeatures = {};

  MLService get _mlService => ref.read(mlServiceProvider);

  @override
  MLAnalyticsState build() {
    print('[ML] MLService initialized with baseUrl: ${_mlService.baseUrl}');
    // Schedule data loading after build completes to avoid circular dependency
    Future.microtask(() => loadAnalytics());
    return const MLAnalyticsState(isLoading: true);
  }

  /// Check connection to ML backend with timeout
  Future<bool> checkConnection() async {
    try {
      final health = await _mlService.checkHealth().timeout(
        const Duration(seconds: 5),
        onTimeout: () => MLHealthStatus(
          status: 'timeout',
          timestamp: DateTime.now(),
          error: 'Connection timeout',
        ),
      );
      print(
        '[ML] Health check result: status=${health.status}, healthy=${health.isHealthy}, error=${health.error}',
      );
      state = state.copyWith(isConnected: health.isHealthy);
      return health.isHealthy;
    } catch (e) {
      print('[ML] checkConnection exception: $e');
      state = state.copyWith(isConnected: false);
      return false;
    }
  }

  /// Load all ML analytics data
  Future<void> loadAnalytics() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final isConnected = await checkConnection();
      if (kDebugMode) {
        print('[ML] Connection check: $isConnected');
      }

      if (isConnected) {
        try {
          print('[ML] Calling _loadFromAPI...');
          await _loadFromAPI().timeout(const Duration(seconds: 30));
          print('[ML] _loadFromAPI completed');
        } on TimeoutException {
          print('[ML] _loadFromAPI timed out');
          state = state.copyWith(
            error: 'Connection timed out. Please check your ML API server.',
          );
        } catch (e) {
          print('[ML] _loadFromAPI error: $e');
          rethrow;
        }
      } else {
        state = state.copyWith(
          error:
              'ML API is not available. Please check your internet connection.',
        );
      }
    } catch (e, st) {
      print('[ML] loadAnalytics exception: $e');
      print('[ML] Stack trace: $st');
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load data from the live API
  Future<void> _loadFromAPI() async {
    try {
      print('[ML] _loadFromAPI starting...');
      final modelInfo = await _mlService.getModelInfo();
      print(
        '[ML] Got model info: status=${modelInfo.status}, samples=${modelInfo.samples}',
      );

      final testMetrics = modelInfo.testMetrics;
      state = state.copyWith(
        modelInfo: modelInfo,
        modelMetrics: ModelMetrics(
          modelName: 'Weight Prediction',
          mae: modelInfo.mae ?? 2.0,
          mape: (testMetrics?['mape'] as num?)?.toDouble() ?? 0.04,
          r2: modelInfo.accuracy ?? 0.9,
          trainingSamples: modelInfo.samples ?? 0,
          lastTrainedAt: modelInfo.trainedAt ?? DateTime.now(),
          version: '2.1.0',
        ),
      );

      print('[ML] Fetching animals...');
      final animals = await ref.read(animalsProvider.future);
      print('[ML] Got ${animals.length} animals');

      print('[ML] Fetching weight records...');
      List<WeightRecord> weightRecords;
      try {
        weightRecords = await ref
            .read(weightRecordsProvider.future)
            .timeout(const Duration(seconds: 15));
        print('[ML] Got ${weightRecords.length} weight records from stream');
      } on TimeoutException {
        // Fall back to direct query
        print('[ML] Stream timeout, falling back to direct query...');
        final farmId = ref.read(activeFarmIdProvider);
        if (farmId == null) {
          print('[ML] No active farm, returning empty weight records');
          weightRecords = [];
        } else {
          final weightRepo = ref.read(weightRepositoryProvider);
          weightRecords = await weightRepo.getWeightRecords(farmId);
          print(
            '[ML] Got ${weightRecords.length} weight records from direct query',
          );
        }
      }

      if (animals.isEmpty) {
        print('[ML] No animals found, returning empty state');
        // No animals yet - show empty state with API connection
        state = state.copyWith(
          predictions: [],
          healthScores: [],
          insights: _generateConnectionInsights(),
          weightSummary: null,
          healthSummary: null,
        );
        return;
      }

      // Build weight records map for quick lookup
      final weightRecordsByAnimal = <String, List<WeightRecord>>{};
      for (final record in weightRecords) {
        weightRecordsByAnimal
            .putIfAbsent(record.animalId, () => [])
            .add(record);
      }
      print(
        '[ML] Animals with weight records: ${weightRecordsByAnimal.length}',
      );

      // Compute predictions for each animal using the ML API
      final predictions = <WeightPrediction>[];
      final healthScores = <AnimalHealthScore>[];
      int skippedNoWeight = 0;

      for (final animal in animals) {
        final animalWeightRecords = weightRecordsByAnimal[animal.id] ?? [];

        // Skip animals without enough weight data
        if (animalWeightRecords.isEmpty) {
          skippedNoWeight++;
          continue;
        }

        // Sort by date descending
        animalWeightRecords.sort((a, b) => b.date.compareTo(a.date));

        final currentWeight = animalWeightRecords.first.weight;

        try {
          // Compute features and predict using live API
          final features = _buildFeatures(animal, animalWeightRecords);
          print(
            '[ML] Predicting for ${animal.tagId} with ${features.length} features',
          );

          // Cache features for later SHAP explanation use
          _animalFeatures[animal.id] = features;

          final apiResponse = await _mlService.predictWeight(
            features: features,
            horizonDays: state.selectedHorizon.days,
          );

          // Calculate bounds based on confidence (simple approximation)
          final confidence = apiResponse.confidence;
          final margin = apiResponse.predictedGain * (1 - confidence) * 0.5;
          final lowerBound = apiResponse.predictedWeight - margin;
          final upperBound = apiResponse.predictedWeight + margin;

          predictions.add(
            WeightPrediction(
              animalId: animal.id,
              animalTagId: animal.tagId,
              animalName: animal.name ?? animal.tagId,
              currentWeight: currentWeight,
              predictedWeight: apiResponse.predictedWeight,
              predictedGain: apiResponse.predictedWeight - currentWeight,
              horizonDays: state.selectedHorizon.days,
              predictionDate: DateTime.now().add(
                Duration(days: state.selectedHorizon.days),
              ),
              confidenceScore: apiResponse.confidence,
              lowerBound: lowerBound,
              upperBound: upperBound,
              targetWeight: 100,
              daysToTarget: _estimateDaysToTarget(
                currentWeight,
                apiResponse.predictedWeight,
                state.selectedHorizon.days,
                100,
              ),
            ),
          );

          // Try health model API for health score, fall back to local
          try {
            final healthResponse = await _mlService.predictHealthRisk(
              features: features,
              horizonDays: state.selectedHorizon.days,
            );

            // Map API risk level string to RiskLevel enum
            RiskLevel riskLevel;
            switch (healthResponse.riskLevel) {
              case 'critical':
                riskLevel = RiskLevel.critical;
              case 'high':
                riskLevel = RiskLevel.high;
              case 'moderate':
                riskLevel = RiskLevel.moderate;
              default:
                riskLevel = RiskLevel.low;
            }

            final riskFactors = <HealthRiskFactor>[];
            if (healthResponse.treatmentLikely) {
              riskFactors.add(
                HealthRiskFactor(
                  name: 'Treatment Likely',
                  severity: RiskLevel.moderate,
                  description:
                      'Treatment probability: ${(healthResponse.treatmentProbability * 100).toStringAsFixed(0)}%',
                  pointsImpact: -10,
                ),
              );
            }
            if (healthResponse.healthDeclining) {
              riskFactors.add(
                HealthRiskFactor(
                  name: 'Health Declining',
                  severity: RiskLevel.high,
                  description:
                      'Predicted score change: ${healthResponse.predictedScoreDelta.toStringAsFixed(1)} (${healthResponse.trend})',
                  pointsImpact: -15,
                ),
              );
            }

            // Derive a health score: start at currentHealthScore, adjust by risk
            final healthScore =
                healthResponse.currentHealthScore -
                healthResponse.predictedRiskScore.round().clamp(0, 60);

            healthScores.add(
              AnimalHealthScore(
                animalId: animal.id,
                animalTagId: animal.tagId,
                animalName: animal.name ?? animal.tagId,
                healthScore: healthScore.clamp(0, 100),
                riskLevel: riskLevel,
                riskFactors: riskFactors,
                lastUpdated: DateTime.now(),
              ),
            );
          } catch (_) {
            // Fall back to local health score computation
            healthScores.add(
              _buildHealthScore(animal, animalWeightRecords, features),
            );
          }
        } catch (e) {
          // Skip animals that fail prediction
          print('[ML] Prediction FAILED for ${animal.tagId}: $e');
          continue;
        }
      }

      print(
        '[ML] Final: ${predictions.length} predictions, ${healthScores.length} health scores, $skippedNoWeight skipped (no weight)',
      );

      // Generate summaries and insights
      final weightSummary = _computeWeightSummary(predictions);
      final healthSummary = _computeHealthSummary(healthScores);
      final insights = _generateInsightsFromData(
        predictions,
        healthScores,
        modelInfo,
      );

      state = state.copyWith(
        predictions: predictions,
        healthScores: healthScores,
        insights: insights,
        weightSummary: weightSummary,
        healthSummary: healthSummary,
      );
    } catch (e) {
      // Rethrow to be handled by loadAnalytics
      rethrow;
    }
  }

  /// Build feature map for ML API prediction
  Map<String, dynamic> _buildFeatures(
    Animal animal,
    List<WeightRecord> weightRecords,
  ) {
    final now = DateTime.now();
    final sorted = List<WeightRecord>.from(weightRecords)
      ..sort((a, b) => b.date.compareTo(a.date));

    final currentWeight = sorted.first.weight;

    // Calculate derived features
    double? weight7dAgo;
    double? weight30dAgo;
    final weights30d = <double>[];

    for (final record in sorted) {
      final daysDiff = now.difference(record.date).inDays;
      if (daysDiff <= 30) weights30d.add(record.weight);
      if (daysDiff >= 6 && daysDiff <= 8 && weight7dAgo == null) {
        weight7dAgo = record.weight;
      }
      if (daysDiff >= 28 && daysDiff <= 32 && weight30dAgo == null) {
        weight30dAgo = record.weight;
      }
    }

    // Calculate statistics
    final avgWeight30d = weights30d.isNotEmpty
        ? weights30d.reduce((a, b) => a + b) / weights30d.length
        : currentWeight;

    double stdWeight30d = 0;
    if (weights30d.length > 1) {
      final variance =
          weights30d
              .map((w) => (w - avgWeight30d) * (w - avgWeight30d))
              .reduce((a, b) => a + b) /
          weights30d.length;
      stdWeight30d = variance > 0 ? _sqrt(variance) : 0;
    }

    final weightChange7d = weight7dAgo != null
        ? currentWeight - weight7dAgo
        : 0.0;
    final adgLifetime = sorted.length > 1
        ? (currentWeight - sorted.last.weight) /
              now.difference(sorted.last.date).inDays.clamp(1, 365)
        : 0.0;
    final velocity30d = weight30dAgo != null
        ? (currentWeight - weight30dAgo) / 30
        : adgLifetime;

    return {
      'wf_current_weight': currentWeight,
      'wf_weight_7d_ago': weight7dAgo ?? currentWeight,
      'wf_weight_30d_ago': weight30dAgo ?? currentWeight,
      'wf_weight_avg_30d': avgWeight30d,
      'wf_weight_std_30d': stdWeight30d,
      'wf_weight_min_30d': weights30d.isNotEmpty
          ? weights30d.reduce((a, b) => a < b ? a : b)
          : currentWeight,
      'wf_weight_max_30d': weights30d.isNotEmpty
          ? weights30d.reduce((a, b) => a > b ? a : b)
          : currentWeight,
      'wf_weight_change_7d': weightChange7d,
      'wf_weight_velocity_30d': velocity30d,
      'wf_adg_lifetime': adgLifetime,
      'wf_growth_curve_deviation': 0.0, // Would need expected growth curve
      'hf_health_score': 85.0, // Default if no health records
      'hf_days_since_last_vaccination': 30, // Default
      'hf_days_since_last_health_record': 7, // Default
    };
  }

  double _sqrt(double value) {
    if (value <= 0) return 0;
    double guess = value / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + value / guess) / 2;
    }
    return guess;
  }

  int _estimateDaysToTarget(
    double current,
    double predicted,
    int horizonDays,
    double target,
  ) {
    if (current >= target) return 0;
    final dailyGain = (predicted - current) / horizonDays;
    if (dailyGain <= 0) return 999;
    return ((target - current) / dailyGain).ceil();
  }

  AnimalHealthScore _buildHealthScore(
    Animal animal,
    List<WeightRecord> weightRecords,
    Map<String, dynamic> features,
  ) {
    // Calculate health score based on weight stability and growth
    final stdWeight = (features['wf_weight_std_30d'] as num?)?.toDouble() ?? 0;
    final velocity =
        (features['wf_weight_velocity_30d'] as num?)?.toDouble() ?? 0;
    final weightChange7d =
        (features['wf_weight_change_7d'] as num?)?.toDouble() ?? 0;

    // Score components
    double score = 85; // Base score
    final riskFactors = <HealthRiskFactor>[];

    // Penalize high weight variability
    if (stdWeight > 5) {
      score -= 10;
      riskFactors.add(
        HealthRiskFactor(
          name: 'Weight Variability',
          severity: RiskLevel.moderate,
          description:
              'Weight fluctuations of ${stdWeight.toStringAsFixed(1)} kg',
          pointsImpact: -10,
        ),
      );
    }

    // Penalize weight loss
    if (weightChange7d < -1) {
      score -= 15;
      riskFactors.add(
        HealthRiskFactor(
          name: 'Recent Weight Loss',
          severity: weightChange7d < -3 ? RiskLevel.high : RiskLevel.moderate,
          description:
              'Lost ${(-weightChange7d).toStringAsFixed(1)} kg in 7 days',
          pointsImpact: -15,
        ),
      );
    }

    // Penalize slow growth
    if (velocity < 0.3) {
      score -= 5;
      riskFactors.add(
        HealthRiskFactor(
          name: 'Slow Growth',
          severity: RiskLevel.low,
          description: 'Growing at ${velocity.toStringAsFixed(2)} kg/day',
          pointsImpact: -5,
        ),
      );
    }

    score = score.clamp(0.0, 100.0);

    RiskLevel riskLevel;
    if (score >= 80) {
      riskLevel = RiskLevel.low;
    } else if (score >= 60) {
      riskLevel = RiskLevel.moderate;
    } else if (score >= 40) {
      riskLevel = RiskLevel.high;
    } else {
      riskLevel = RiskLevel.critical;
    }

    return AnimalHealthScore(
      animalId: animal.id,
      animalTagId: animal.tagId,
      animalName: animal.name ?? animal.tagId,
      healthScore: score.round(),
      riskLevel: riskLevel,
      riskFactors: riskFactors,
      lastUpdated: DateTime.now(),
    );
  }

  HerdWeightSummary _computeWeightSummary(List<WeightPrediction> predictions) {
    final now = DateTime.now();
    if (predictions.isEmpty) {
      return HerdWeightSummary(
        totalAnimals: 0,
        avgDailyGain: 0,
        targetDailyGain: 0.7,
        animalsGrowingWell: 0,
        animalsReadyForMarket: 0,
        daysToMarketReady: 0,
        lastUpdated: now,
      );
    }

    final avgGain =
        predictions.map((p) => p.predictedGain).reduce((a, b) => a + b) /
        predictions.length;
    final avgDailyGain = avgGain / state.selectedHorizon.days;
    final marketReady = predictions.where((p) => p.willReachTarget).length;
    final growingWell = predictions.where((p) => p.predictedGain > 0).length;

    return HerdWeightSummary(
      totalAnimals: predictions.length,
      avgDailyGain: avgDailyGain,
      targetDailyGain: 0.7, // Default target
      animalsGrowingWell: growingWell,
      animalsReadyForMarket: marketReady,
      daysToMarketReady: predictions.isNotEmpty
          ? (predictions
                        .map((p) => p.daysToTarget ?? 0)
                        .reduce((a, b) => a + b) /
                    predictions.length)
                .round()
          : 0,
      lastUpdated: now,
    );
  }

  HerdHealthSummary _computeHealthSummary(
    List<AnimalHealthScore> healthScores,
  ) {
    final now = DateTime.now();
    if (healthScores.isEmpty) {
      return HerdHealthSummary(
        overallScore: 0,
        totalAnimals: 0,
        atRiskCount: 0,
        healthyCount: 0,
        scoreChange: 0,
        scoreChangePeriod: 'this week',
        upcomingTasks: [],
        lastUpdated: now,
      );
    }

    final avgScore =
        healthScores.map((h) => h.healthScore).reduce((a, b) => a + b) /
        healthScores.length;
    final healthy = healthScores
        .where((h) => h.riskLevel == RiskLevel.low)
        .length;
    final atRisk = healthScores
        .where(
          (h) =>
              h.riskLevel == RiskLevel.moderate ||
              h.riskLevel == RiskLevel.high ||
              h.riskLevel == RiskLevel.critical,
        )
        .length;

    return HerdHealthSummary(
      overallScore: avgScore.round(),
      totalAnimals: healthScores.length,
      atRiskCount: atRisk,
      healthyCount: healthy,
      scoreChange: 0, // Would need historical data
      scoreChangePeriod: 'this week',
      upcomingTasks: [], // Would need task data
      lastUpdated: now,
    );
  }

  List<AIInsight> _generateConnectionInsights() {
    return [
      AIInsight(
        id: 'connected',
        category: 'system',
        priority: 'low',
        title: 'ML Backend Connected',
        description:
            'Successfully connected to the prediction API. Add animals with weight records to see predictions.',
        createdAt: DateTime.now(),
      ),
    ];
  }

  List<AIInsight> _generateInsightsFromData(
    List<WeightPrediction> predictions,
    List<AnimalHealthScore> healthScores,
    MLModelInfo modelInfo,
  ) {
    final insights = <AIInsight>[];
    final now = DateTime.now();

    // Connected insight
    insights.add(
      AIInsight(
        id: 'api_live',
        category: 'system',
        priority: 'low',
        title: 'Live ML Predictions Active',
        description:
            'Predictions are generated in real-time using model trained on ${modelInfo.samples ?? 0} samples with ${((modelInfo.accuracy ?? 0.9) * 100).toStringAsFixed(1)}% accuracy.',
        createdAt: now,
      ),
    );

    // Market ready animals
    final marketReady = predictions
        .where(
          (p) =>
              p.willReachTarget &&
              p.daysToTarget != null &&
              p.daysToTarget! <= 14,
        )
        .toList();
    if (marketReady.isNotEmpty) {
      insights.add(
        AIInsight(
          id: 'market_ready',
          category: 'market',
          priority: 'high',
          title: '${marketReady.length} Animals Near Market Weight',
          description:
              '${marketReady.map((p) => p.animalName).join(", ")} predicted to reach target weight within 2 weeks.',
          createdAt: now,
        ),
      );
    }

    // At risk animals
    final atRisk = healthScores
        .where(
          (h) =>
              h.riskLevel == RiskLevel.high ||
              h.riskLevel == RiskLevel.critical,
        )
        .toList();
    if (atRisk.isNotEmpty) {
      insights.add(
        AIInsight(
          id: 'at_risk',
          category: 'health',
          priority: 'critical',
          title: '${atRisk.length} Animals Need Attention',
          description:
              '${atRisk.map((h) => h.animalName).join(", ")} showing health concerns based on weight patterns.',
          createdAt: now,
        ),
      );
    }

    // High confidence predictions
    final highConf = predictions
        .where((p) => p.confidenceScore >= 0.9)
        .toList();
    if (highConf.isNotEmpty) {
      insights.add(
        AIInsight(
          id: 'high_confidence',
          category: 'growth',
          priority: 'medium',
          title: '${highConf.length} High-Confidence Predictions',
          description:
              'Model is highly confident about weight predictions for these animals based on consistent growth patterns.',
          createdAt: now,
        ),
      );
    }

    return insights;
  }

  /// Mock data loader - kept for development/testing purposes
  // ignore: unused_element
  void _loadMockData() {
    final now = DateTime.now();
    state = state.copyWith(
      isConnected: false,
      predictions: _generateMockPredictions(now),
      healthScores: _generateMockHealthScores(now),
      insights: _generateMockInsights(now),
      weightSummary: _generateMockWeightSummary(now),
      healthSummary: _generateMockHealthSummary(now),
      modelMetrics: ModelMetrics(
        modelName: 'Weight Prediction v2.1',
        mae: 2.3,
        mape: 0.04,
        r2: 0.89,
        trainingSamples: 1523,
        lastTrainedAt: now.subtract(const Duration(days: 7)),
        version: '2.1.0',
      ),
    );
  }

  /// Refresh analytics data
  Future<void> refresh() => loadAnalytics();

  /// Update selected forecast horizon
  void setForecastHorizon(ForecastHorizon horizon) {
    state = state.copyWith(selectedHorizon: horizon);
    // Reload predictions with new horizon
    loadAnalytics();
  }

  /// Update selected time period
  void setTimePeriod(String period) {
    state = state.copyWith(selectedPeriod: period);
    // Reload analytics with new period
    loadAnalytics();
  }

  /// Get prediction details for an animal
  Future<WeightPrediction?> getPrediction(String animalId) async {
    // First check if we already have it
    final existing = state.predictionsForAnimal(animalId);
    if (existing.isNotEmpty) return existing.first;

    // TODO: Fetch from API if not in cache
    return null;
  }

  /// Get prediction with SHAP explanation from API
  Future<MLExplanationResponse?> getExplanation({
    required Map<String, dynamic> features,
    int? horizonDays,
  }) async {
    try {
      return await _mlService.explainPrediction(
        features: features,
        horizonDays: horizonDays ?? state.selectedHorizon.days,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get SHAP explanation for a prediction
  Future<ShapExplanation?> getShapExplanation(String animalId) async {
    // Try API with cached features
    if (state.isConnected && _animalFeatures.containsKey(animalId)) {
      try {
        final features = _animalFeatures[animalId]!;
        final response = await _mlService.explainPrediction(
          features: features,
          horizonDays: state.selectedHorizon.days,
        );

        // Convert MLExplanationResponse to ShapExplanation
        final allFactors = [
          ...response.explanation.positiveFactors,
          ...response.explanation.negativeFactors,
        ];

        return ShapExplanation(
          animalId: animalId,
          predictionType: 'weight',
          baseValue: response.baseValue,
          predictedValue: response.predictedWeight,
          modelConfidence: response.predictedGain > 0 ? 0.85 : 0.6,
          generatedAt: DateTime.now(),
          summary: response.explanation.summary,
          recommendation:
              'Based on model analysis. ${response.explanation.positiveFactors.isNotEmpty ? "Key growth drivers: ${response.explanation.positiveFactors.take(2).map((f) => f.displayName).join(", ")}." : ""}',
          features: allFactors
              .map(
                (f) => ShapFeature(
                  featureName: f.feature,
                  displayName: f.displayName,
                  value: (f.value as num?)?.toDouble() ?? 0.0,
                  shapValue: f.contribution,
                  explanation: f.userExplanation,
                ),
              )
              .toList(),
        );
      } catch (_) {
        // Fall through to null
      }
    }

    return null;
  }

  /// Get global feature importance
  Future<List<FeatureImportance>> getFeatureImportance() async {
    // Try API first
    if (state.isConnected) {
      try {
        final response = await _mlService.getFeatureImportance();
        return response.sortedFeatures.take(6).map((e) {
          final displayName = _featureDisplayNames[e.key] ?? e.key;
          return FeatureImportance(
            featureName: e.key,
            displayName: displayName,
            importance: e.value / 100, // Normalize to 0-1
            description: _featureDescriptions[e.key],
          );
        }).toList();
      } catch (_) {
        // Fall through to mock data
      }
    }

    // Return mock data
    return [
      FeatureImportance(
        featureName: 'wf_current_weight',
        displayName: 'Current Weight',
        importance: 0.32,
        description: 'Heavier animals tend to gain more weight',
      ),
      FeatureImportance(
        featureName: 'wf_weight_velocity_30d',
        displayName: '30-Day Growth Speed',
        importance: 0.22,
        description: 'Recent growth momentum',
      ),
      FeatureImportance(
        featureName: 'horizon_days',
        displayName: 'Prediction Period',
        importance: 0.18,
        description: 'Longer periods allow more growth',
      ),
      FeatureImportance(
        featureName: 'wf_adg_lifetime',
        displayName: 'Lifetime Growth Rate',
        importance: 0.15,
        description: 'Consistent historical growth supports prediction',
      ),
      FeatureImportance(
        featureName: 'hf_health_score',
        displayName: 'Health Score',
        importance: 0.08,
        description: 'Healthy animals grow better',
      ),
      FeatureImportance(
        featureName: 'wf_weight_std_30d',
        displayName: 'Weight Variability',
        importance: 0.05,
        description: 'Inconsistent weights reduce prediction confidence',
      ),
    ];
  }

  /// Get global explanation from API
  Future<MLGlobalExplanation?> getGlobalExplanation() async {
    if (!state.isConnected) return null;
    try {
      return await _mlService.getGlobalExplanation();
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // Mock Data Generators
  // ===========================================================================

  List<WeightPrediction> _generateMockPredictions(DateTime now) {
    return [
      WeightPrediction(
        animalId: 'a1',
        animalTagId: 'Pig-001',
        animalName: 'Bella',
        currentWeight: 85.5,
        predictedWeight: 92.3,
        predictedGain: 6.8,
        horizonDays: state.selectedHorizon.days,
        predictionDate: now.add(Duration(days: state.selectedHorizon.days)),
        confidenceScore: 0.91,
        lowerBound: 89.1,
        upperBound: 95.5,
        targetWeight: 100,
        daysToTarget: 28,
      ),
      WeightPrediction(
        animalId: 'a2',
        animalTagId: 'Pig-002',
        animalName: 'Max',
        currentWeight: 78.2,
        predictedWeight: 84.5,
        predictedGain: 6.3,
        horizonDays: state.selectedHorizon.days,
        predictionDate: now.add(Duration(days: state.selectedHorizon.days)),
        confidenceScore: 0.75,
        lowerBound: 81.0,
        upperBound: 88.0,
        targetWeight: 100,
        daysToTarget: 35,
      ),
      WeightPrediction(
        animalId: 'a3',
        animalTagId: 'Pig-003',
        animalName: 'Charlie',
        currentWeight: 95.0,
        predictedWeight: 103.2,
        predictedGain: 8.2,
        horizonDays: state.selectedHorizon.days,
        predictionDate: now.add(Duration(days: state.selectedHorizon.days)),
        confidenceScore: 0.89,
        lowerBound: 100.5,
        upperBound: 106.0,
        targetWeight: 100,
        daysToTarget: 7,
      ),
      WeightPrediction(
        animalId: 'a4',
        animalTagId: 'Pig-004',
        animalName: 'Duke',
        currentWeight: 72.3,
        predictedWeight: 78.1,
        predictedGain: 5.8,
        horizonDays: state.selectedHorizon.days,
        predictionDate: now.add(Duration(days: state.selectedHorizon.days)),
        confidenceScore: 0.82,
        lowerBound: 75.5,
        upperBound: 80.7,
        targetWeight: 100,
        daysToTarget: 42,
      ),
      WeightPrediction(
        animalId: 'a5',
        animalTagId: 'Pig-005',
        animalName: 'Rex',
        currentWeight: 88.7,
        predictedWeight: 95.4,
        predictedGain: 6.7,
        horizonDays: state.selectedHorizon.days,
        predictionDate: now.add(Duration(days: state.selectedHorizon.days)),
        confidenceScore: 0.88,
        lowerBound: 92.1,
        upperBound: 98.7,
        targetWeight: 100,
        daysToTarget: 21,
      ),
    ];
  }

  List<AnimalHealthScore> _generateMockHealthScores(DateTime now) {
    return [
      AnimalHealthScore(
        animalId: 'a1',
        animalTagId: 'Pig-001',
        animalName: 'Bella',
        healthScore: 92,
        riskLevel: RiskLevel.low,
        riskFactors: [],
        lastUpdated: now,
      ),
      AnimalHealthScore(
        animalId: 'a2',
        animalTagId: 'Pig-002',
        animalName: 'Max',
        healthScore: 88,
        riskLevel: RiskLevel.low,
        riskFactors: [],
        lastUpdated: now,
      ),
      AnimalHealthScore(
        animalId: 'a3',
        animalTagId: 'Pig-003',
        animalName: 'Charlie',
        healthScore: 95,
        riskLevel: RiskLevel.low,
        riskFactors: [],
        lastUpdated: now,
      ),
      AnimalHealthScore(
        animalId: 'a4',
        animalTagId: 'Pig-004',
        animalName: 'Duke',
        healthScore: 68,
        riskLevel: RiskLevel.moderate,
        riskFactors: [
          HealthRiskFactor(
            name: 'Weight Loss',
            severity: RiskLevel.moderate,
            description: 'Lost 2.1 kg in the last week',
            pointsImpact: -15,
            possibleCauses: 'Reduced appetite, possible stress or illness',
          ),
          HealthRiskFactor(
            name: 'Irregular Feeding',
            severity: RiskLevel.low,
            description: 'Feeding pattern inconsistent',
            pointsImpact: -8,
            possibleCauses: 'Environmental changes or feed quality',
          ),
        ],
        lastUpdated: now,
      ),
      AnimalHealthScore(
        animalId: 'a5',
        animalTagId: 'Pig-005',
        animalName: 'Rex',
        healthScore: 52,
        riskLevel: RiskLevel.high,
        riskFactors: [
          HealthRiskFactor(
            name: 'Significant Weight Loss',
            severity: RiskLevel.high,
            description: 'Lost 4.5 kg in the last 10 days',
            pointsImpact: -25,
            possibleCauses: 'Possible infection, needs vet attention',
          ),
          HealthRiskFactor(
            name: 'Vaccination Overdue',
            severity: RiskLevel.moderate,
            description: 'Vaccination 5 days overdue',
            pointsImpact: -12,
          ),
        ],
        lastUpdated: now,
      ),
    ];
  }

  List<AIInsight> _generateMockInsights(DateTime now) {
    return [
      AIInsight(
        id: '1',
        category: 'growth',
        priority: 'low',
        title: 'Strong growth week',
        description:
            'Your herd gained an average of 1.8 kg this week, 15% above target.',
        createdAt: now,
      ),
      AIInsight(
        id: '2',
        category: 'health',
        priority: 'high',
        title: '2 animals need attention',
        description:
            'Health scores dropped for Pig-004 and Pig-005. Review recommended.',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      AIInsight(
        id: '3',
        category: 'market',
        priority: 'medium',
        title: 'Market opportunity',
        description:
            '3 animals projected to reach market weight within 2 weeks.',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
    ];
  }

  HerdWeightSummary _generateMockWeightSummary(DateTime now) {
    return HerdWeightSummary(
      totalAnimals: 17,
      avgDailyGain: 1.8,
      targetDailyGain: 1.5,
      animalsGrowingWell: 12,
      animalsReadyForMarket: 3,
      daysToMarketReady: 21,
      lastUpdated: now,
    );
  }

  HerdHealthSummary _generateMockHealthSummary(DateTime now) {
    return HerdHealthSummary(
      overallScore: 85,
      totalAnimals: 17,
      atRiskCount: 2,
      healthyCount: 15,
      scoreChange: 3,
      scoreChangePeriod: 'last week',
      lastUpdated: now,
      upcomingTasks: [
        UpcomingHealthTask(
          type: 'vaccination',
          title: 'Vaccination due',
          description: 'Pig-001, Pig-002, Pig-003',
          dueDate: now,
          animalIds: ['a1', 'a2', 'a3'],
          animalCount: 3,
        ),
        UpcomingHealthTask(
          type: 'checkup',
          title: 'Weekly checkup',
          description: 'All animals',
          dueDate: now.add(const Duration(days: 2)),
          animalIds: [],
          animalCount: 17,
        ),
        UpcomingHealthTask(
          type: 'medication',
          title: 'Deworming schedule',
          description: 'Pig-004, Pig-005',
          dueDate: now.add(const Duration(days: 5)),
          animalIds: ['a4', 'a5'],
          animalCount: 2,
        ),
      ],
    );
  }

  // Feature display name mappings
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

  static const _featureDescriptions = {
    'wf_current_weight': 'Heavier animals tend to gain more weight',
    'wf_adg_lifetime': 'Consistent historical growth supports prediction',
    'wf_weight_velocity_30d': 'Recent growth momentum',
    'wf_weight_std_30d': 'Inconsistent weights reduce prediction confidence',
    'wf_weight_change_7d': 'Recent weight trend (gain or loss)',
    'wf_weight_7d_ago': 'Reference point for weekly comparison',
    'horizon_days': 'Longer periods allow more growth',
    'hf_health_score': 'Healthy animals grow better',
    'hf_vaccination_count_total': 'Well-vaccinated animals are healthier',
  };
}

// =============================================================================
// Helper Providers
// =============================================================================

/// Shortcut providers for specific data
final weightPredictionsProvider = Provider<List<WeightPrediction>>((ref) {
  return ref.watch(mlAnalyticsProvider).predictions;
});

final healthScoresProvider = Provider<List<AnimalHealthScore>>((ref) {
  return ref.watch(mlAnalyticsProvider).healthScores;
});

final atRiskAnimalsProvider = Provider<List<AnimalHealthScore>>((ref) {
  return ref.watch(mlAnalyticsProvider).atRiskAnimals;
});

final marketReadyAnimalsProvider = Provider<List<WeightPrediction>>((ref) {
  return ref.watch(mlAnalyticsProvider).marketReadyPredictions;
});

final aiInsightsProvider = Provider<List<AIInsight>>((ref) {
  return ref.watch(mlAnalyticsProvider).insights;
});

final mlModelMetricsProvider = Provider<ModelMetrics?>((ref) {
  return ref.watch(mlAnalyticsProvider).modelMetrics;
});

/// Provider for individual animal prediction
final animalPredictionProvider =
    FutureProvider.family<WeightPrediction?, String>((ref, animalId) async {
      final notifier = ref.read(mlAnalyticsProvider.notifier);
      return notifier.getPrediction(animalId);
    });

/// Provider for SHAP explanation
final shapExplanationProvider = FutureProvider.family<ShapExplanation?, String>(
  (ref, animalId) async {
    final notifier = ref.read(mlAnalyticsProvider.notifier);
    return notifier.getShapExplanation(animalId);
  },
);

/// Provider for global feature importance
final featureImportanceProvider = FutureProvider<List<FeatureImportance>>((
  ref,
) async {
  final notifier = ref.read(mlAnalyticsProvider.notifier);
  return notifier.getFeatureImportance();
});

/// Selected forecast horizon provider
final selectedHorizonProvider = Provider<ForecastHorizon>((ref) {
  return ref.watch(mlAnalyticsProvider).selectedHorizon;
});

/// Selected time period provider
final selectedPeriodProvider = Provider<String>((ref) {
  return ref.watch(mlAnalyticsProvider).selectedPeriod;
});

/// Connection status provider
final mlConnectionProvider = Provider<bool>((ref) {
  return ref.watch(mlAnalyticsProvider).isConnected;
});
