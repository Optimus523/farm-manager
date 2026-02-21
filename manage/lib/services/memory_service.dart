import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:manage/providers/auth_providers.dart';

/// Configuration for the Memory API
class MemoryApiConfig {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api/v1/memory';
    }
    // Android emulator uses 10.0.2.2 to reach host machine's localhost
    return 'http://10.0.2.2:8000/api/v1/memory';
  }
}

/// Response from adding a memory
class AddMemoryResponse {
  final String? id;
  final String status;
  final String? error;

  AddMemoryResponse({this.id, required this.status, this.error});

  factory AddMemoryResponse.fromJson(Map<String, dynamic> json) {
    return AddMemoryResponse(
      id: json['id']?.toString(),
      status: json['status'] ?? 'unknown',
      error: json['error'],
    );
  }

  bool get isSuccess => status == 'created' || status == 'ok';
}

/// A single memory search result
class MemorySearchResult {
  final String id;
  final String content;
  final String? summary;
  final String memoryType;
  final String? category;
  final double? importance;
  final double similarity;
  final DateTime? createdAt;
  final Map<String, dynamic>? metadata;

  MemorySearchResult({
    required this.id,
    required this.content,
    this.summary,
    required this.memoryType,
    this.category,
    this.importance,
    required this.similarity,
    this.createdAt,
    this.metadata,
  });

  factory MemorySearchResult.fromJson(Map<String, dynamic> json) {
    return MemorySearchResult(
      id: json['id']?.toString() ?? '',
      content: json['content'] ?? '',
      summary: json['summary'],
      memoryType: json['memory_type'] ?? 'fact',
      category: json['category'],
      importance: (json['importance'] as num?)?.toDouble(),
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Response from searching memories
class SearchMemoriesResponse {
  final List<MemorySearchResult> results;
  final String? error;

  SearchMemoriesResponse({required this.results, this.error});

  factory SearchMemoriesResponse.fromJson(Map<String, dynamic> json) {
    final resultsList = json['results'] as List<dynamic>? ?? [];
    return SearchMemoriesResponse(
      results: resultsList
          .map((r) => MemorySearchResult.fromJson(r as Map<String, dynamic>))
          .toList(),
      error: json['error'],
    );
  }

  bool get hasResults => results.isNotEmpty;
}

/// User memory profile
class MemoryProfile {
  final List<String> staticFacts;
  final List<String> dynamicContext;

  MemoryProfile({required this.staticFacts, required this.dynamicContext});

  factory MemoryProfile.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>? ?? {};
    return MemoryProfile(
      staticFacts:
          (profile['static'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      dynamicContext:
          (profile['dynamic'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// Build a context string for the LLM prompt
  String toContextString() {
    final parts = <String>[];

    if (staticFacts.isNotEmpty) {
      parts.add('## User Profile (Persistent Facts)');
      for (final fact in staticFacts.take(10)) {
        parts.add('- $fact');
      }
    }

    if (dynamicContext.isNotEmpty) {
      parts.add('\n## Recent Context');
      for (final episode in dynamicContext.take(5)) {
        parts.add('- $episode');
      }
    }

    return parts.join('\n');
  }

  bool get isEmpty => staticFacts.isEmpty && dynamicContext.isEmpty;
}

/// Response from getting memory profile
class GetProfileResponse {
  final MemoryProfile profile;
  final List<MemorySearchResult> searchResults;
  final String? error;

  GetProfileResponse({
    required this.profile,
    required this.searchResults,
    this.error,
  });

  factory GetProfileResponse.fromJson(Map<String, dynamic> json) {
    final searchResultsList = json['search_results'] as List<dynamic>? ?? [];
    return GetProfileResponse(
      profile: MemoryProfile.fromJson(json),
      searchResults: searchResultsList
          .map((r) => MemorySearchResult.fromJson(r as Map<String, dynamic>))
          .toList(),
      error: json['error'],
    );
  }

  /// Build full context including profile and search results
  String toFullContextString() {
    final parts = <String>[];

    final profileContext = profile.toContextString();
    if (profileContext.isNotEmpty) {
      parts.add(profileContext);
    }

    if (searchResults.isNotEmpty) {
      parts.add('\n## Relevant Memories');
      for (final mem in searchResults.take(5)) {
        parts.add('- ${mem.content}');
      }
    }

    return parts.join('\n');
  }
}

/// Extracted memory from content
class ExtractedMemory {
  final String? id;
  final String content;
  final String type;
  final String? category;

  ExtractedMemory({
    this.id,
    required this.content,
    required this.type,
    this.category,
  });

  factory ExtractedMemory.fromJson(Map<String, dynamic> json) {
    return ExtractedMemory(
      id: json['id']?.toString(),
      content: json['content'] ?? '',
      type: json['type'] ?? 'fact',
      category: json['category'],
    );
  }
}

/// Response from extracting memories
class ExtractMemoriesResponse {
  final int extractedCount;
  final List<ExtractedMemory> memories;
  final String? error;

  ExtractMemoriesResponse({
    required this.extractedCount,
    required this.memories,
    this.error,
  });

  factory ExtractMemoriesResponse.fromJson(Map<String, dynamic> json) {
    final memoriesList = json['memories'] as List<dynamic>? ?? [];
    return ExtractMemoriesResponse(
      extractedCount: json['extracted'] ?? memoriesList.length,
      memories: memoriesList
          .map((m) => ExtractedMemory.fromJson(m as Map<String, dynamic>))
          .toList(),
      error: json['error'],
    );
  }

  bool get hasMemories => memories.isNotEmpty;
}

/// Service for interacting with the Memory API
class MemoryService {
  final String baseUrl;
  final http.Client _client;

  MemoryService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? MemoryApiConfig.baseUrl,
      _client = client ?? http.Client();

  String getContainerTag(String userId) => 'user-$userId';

  String getFarmContainerTag(String farmId) => 'farm-$farmId-context';

  Future<bool> ensureContainerExists(String containerTag) async {
    try {
      final response = await addMemory(
        containerTag: containerTag,
        content: 'Memory container initialized',
        memoryType: 'fact',
        category: 'system',
      );

      if (response.isSuccess) {
        debugPrint('Container ensured: $containerTag');
        return true;
      } else {
        debugPrint('Failed to ensure container: ${response.error}');
        return false;
      }
    } catch (e) {
      debugPrint('Error ensuring container: $e');
      return false;
    }
  }

  /// Add a memory to the user's container
  Future<AddMemoryResponse> addMemory({
    required String containerTag,
    required String content,
    String memoryType = 'fact',
    String? category,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'container_tag': containerTag,
          'content': content,
          'memory_type': memoryType,
          if (category != null) 'category': category,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return AddMemoryResponse.fromJson(jsonDecode(response.body));
      } else {
        debugPrint(
          'Add memory failed: ${response.statusCode} - ${response.body}',
        );
        return AddMemoryResponse(
          status: 'error',
          error: 'Failed to add memory: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Add memory error: $e');
      return AddMemoryResponse(status: 'error', error: e.toString());
    }
  }

  /// Search memories by semantic similarity
  Future<SearchMemoriesResponse> searchMemories({
    required String containerTag,
    required String query,
    int limit = 10,
    double threshold = 0.7,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'container_tag': containerTag,
          'query': query,
          'limit': limit,
          'threshold': threshold,
        }),
      );

      if (response.statusCode == 200) {
        return SearchMemoriesResponse.fromJson(jsonDecode(response.body));
      } else {
        debugPrint('Search failed: ${response.statusCode} - ${response.body}');
        return SearchMemoriesResponse(
          results: [],
          error: 'Search failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Search error: $e');
      return SearchMemoriesResponse(results: [], error: e.toString());
    }
  }

  /// Extract memories from content and store them
  Future<ExtractMemoriesResponse> extractAndStore({
    required String containerTag,
    required String content,
    String context = '',
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/extract'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'container_tag': containerTag,
          'content': content,
          'context': context,
        }),
      );

      if (response.statusCode == 200) {
        return ExtractMemoriesResponse.fromJson(jsonDecode(response.body));
      } else {
        debugPrint('Extract failed: ${response.statusCode} - ${response.body}');
        return ExtractMemoriesResponse(
          extractedCount: 0,
          memories: [],
          error: 'Extract failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Extract error: $e');
      return ExtractMemoriesResponse(
        extractedCount: 0,
        memories: [],
        error: e.toString(),
      );
    }
  }

  /// Store a conversation for future context extraction
  Future<ExtractMemoriesResponse> storeConversation({
    required String containerTag,
    required String userMessage,
    required String assistantResponse,
    String? additionalContext,
  }) async {
    final conversationText =
        '''
User: $userMessage
Assistant: $assistantResponse
''';

    return extractAndStore(
      containerTag: containerTag,
      content: conversationText,
      context: additionalContext ?? '',
    );
  }

  void dispose() {
    _client.close();
  }
}

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

final userMemoryContextProvider =
    FutureProvider.family<GetProfileResponse?, String>((ref, query) async {
      final memoryService = ref.read(memoryServiceProvider);

      final user = ref.read(currentUserProvider).value;
      if (user == null) {
        debugPrint('No user logged in, cannot fetch memory context');
        return null;
      }

      final containerTag = memoryService.getContainerTag(user.id);

      final searchResponse = await memoryService.searchMemories(
        containerTag: containerTag,
        query: query,
        limit: 5,
        threshold: 0.6,
      );

      // Build a profile response (in a real implementation, you'd call a profile endpoint)
      return GetProfileResponse(
        profile: MemoryProfile(staticFacts: [], dynamicContext: []),
        searchResults: searchResponse.results,
      );
    });
