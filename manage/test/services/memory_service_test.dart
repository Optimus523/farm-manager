import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manage/services/memory_service.dart';

void main() {
  group('AddMemoryResponse', () {
    test('parses success JSON correctly', () {
      final json = {'id': '123', 'status': 'created'};
      final response = AddMemoryResponse.fromJson(json);

      expect(response.id, '123');
      expect(response.status, 'created');
      expect(response.error, isNull);
      expect(response.isSuccess, isTrue);
    });

    test('parses ok status as success', () {
      final json = {'id': '456', 'status': 'ok'};
      final response = AddMemoryResponse.fromJson(json);

      expect(response.isSuccess, isTrue);
    });

    test('parses error JSON correctly', () {
      final json = {'status': 'error', 'error': 'Something went wrong'};
      final response = AddMemoryResponse.fromJson(json);

      expect(response.id, isNull);
      expect(response.status, 'error');
      expect(response.error, 'Something went wrong');
      expect(response.isSuccess, isFalse);
    });

    test('handles missing status with unknown default', () {
      final json = <String, dynamic>{};
      final response = AddMemoryResponse.fromJson(json);

      expect(response.status, 'unknown');
      expect(response.isSuccess, isFalse);
    });

    test('handles numeric id', () {
      final json = {'id': 42, 'status': 'created'};
      final response = AddMemoryResponse.fromJson(json);

      expect(response.id, '42');
    });
  });

  group('MemorySearchResult', () {
    test('parses full JSON correctly', () {
      final json = {
        'id': 'mem-001',
        'content': 'User has 20 pigs',
        'summary': 'Pig count',
        'memory_type': 'fact',
        'category': 'livestock',
        'importance': 0.8,
        'similarity': 0.95,
        'created_at': '2025-06-15T10:30:00Z',
        'metadata': {'source': 'conversation'},
      };
      final result = MemorySearchResult.fromJson(json);

      expect(result.id, 'mem-001');
      expect(result.content, 'User has 20 pigs');
      expect(result.summary, 'Pig count');
      expect(result.memoryType, 'fact');
      expect(result.category, 'livestock');
      expect(result.importance, 0.8);
      expect(result.similarity, 0.95);
      expect(result.createdAt, isA<DateTime>());
      expect(result.metadata, isNotNull);
      expect(result.metadata!['source'], 'conversation');
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 'mem-002',
        'content': 'Some memory',
        'memory_type': 'fact',
        'similarity': 0.7,
      };
      final result = MemorySearchResult.fromJson(json);

      expect(result.summary, isNull);
      expect(result.category, isNull);
      expect(result.importance, isNull);
      expect(result.createdAt, isNull);
      expect(result.metadata, isNull);
    });

    test('defaults to empty string for missing id', () {
      final json = <String, dynamic>{'content': 'Test', 'similarity': 0.5};
      final result = MemorySearchResult.fromJson(json);

      expect(result.id, '');
    });

    test('defaults to empty string for missing content', () {
      final json = <String, dynamic>{'id': '1', 'similarity': 0.5};
      final result = MemorySearchResult.fromJson(json);

      expect(result.content, '');
    });

    test('defaults to fact for missing memory_type', () {
      final json = <String, dynamic>{
        'id': '1',
        'content': 'Test',
        'similarity': 0.5,
      };
      final result = MemorySearchResult.fromJson(json);

      expect(result.memoryType, 'fact');
    });

    test('defaults to 0.0 for missing similarity', () {
      final json = <String, dynamic>{'id': '1', 'content': 'Test'};
      final result = MemorySearchResult.fromJson(json);

      expect(result.similarity, 0.0);
    });

    test('handles invalid created_at gracefully', () {
      final json = {
        'id': '1',
        'content': 'Test',
        'similarity': 0.5,
        'created_at': 'not-a-date',
      };
      final result = MemorySearchResult.fromJson(json);

      expect(result.createdAt, isNull);
    });
  });

  group('SearchMemoriesResponse', () {
    test('parses response with results', () {
      final json = {
        'results': [
          {
            'id': '1',
            'content': 'Memory 1',
            'memory_type': 'fact',
            'similarity': 0.9,
          },
          {
            'id': '2',
            'content': 'Memory 2',
            'memory_type': 'episode',
            'similarity': 0.8,
          },
        ],
      };
      final response = SearchMemoriesResponse.fromJson(json);

      expect(response.results, hasLength(2));
      expect(response.results[0].content, 'Memory 1');
      expect(response.results[1].content, 'Memory 2');
      expect(response.hasResults, isTrue);
      expect(response.error, isNull);
    });

    test('parses empty results', () {
      final json = {'results': <dynamic>[]};
      final response = SearchMemoriesResponse.fromJson(json);

      expect(response.results, isEmpty);
      expect(response.hasResults, isFalse);
    });

    test('handles missing results key', () {
      final json = <String, dynamic>{};
      final response = SearchMemoriesResponse.fromJson(json);

      expect(response.results, isEmpty);
      expect(response.hasResults, isFalse);
    });

    test('parses error field', () {
      final json = {'results': <dynamic>[], 'error': 'Search failed'};
      final response = SearchMemoriesResponse.fromJson(json);

      expect(response.error, 'Search failed');
    });
  });

  group('MemoryProfile', () {
    test('parses profile with static and dynamic data', () {
      final json = {
        'profile': {
          'static': ['User name is John', 'Has 50 pigs'],
          'dynamic': ['Asked about feeding schedule yesterday'],
        },
      };
      final profile = MemoryProfile.fromJson(json);

      expect(profile.staticFacts, hasLength(2));
      expect(profile.staticFacts[0], 'User name is John');
      expect(profile.dynamicContext, hasLength(1));
      expect(profile.isEmpty, isFalse);
    });

    test('handles empty profile', () {
      final json = {
        'profile': {'static': <dynamic>[], 'dynamic': <dynamic>[]},
      };
      final profile = MemoryProfile.fromJson(json);

      expect(profile.staticFacts, isEmpty);
      expect(profile.dynamicContext, isEmpty);
      expect(profile.isEmpty, isTrue);
    });

    test('handles missing profile key', () {
      final json = <String, dynamic>{};
      final profile = MemoryProfile.fromJson(json);

      expect(profile.staticFacts, isEmpty);
      expect(profile.dynamicContext, isEmpty);
      expect(profile.isEmpty, isTrue);
    });

    test('toContextString builds correct output with static facts', () {
      final profile = MemoryProfile(
        staticFacts: ['Fact 1', 'Fact 2'],
        dynamicContext: [],
      );

      final context = profile.toContextString();

      expect(context, contains('## User Profile (Persistent Facts)'));
      expect(context, contains('- Fact 1'));
      expect(context, contains('- Fact 2'));
      expect(context, isNot(contains('## Recent Context')));
    });

    test('toContextString builds correct output with dynamic context', () {
      final profile = MemoryProfile(
        staticFacts: [],
        dynamicContext: ['Episode 1', 'Episode 2'],
      );

      final context = profile.toContextString();

      expect(context, isNot(contains('## User Profile')));
      expect(context, contains('## Recent Context'));
      expect(context, contains('- Episode 1'));
      expect(context, contains('- Episode 2'));
    });

    test('toContextString builds correct output with both', () {
      final profile = MemoryProfile(
        staticFacts: ['Fact 1'],
        dynamicContext: ['Episode 1'],
      );

      final context = profile.toContextString();

      expect(context, contains('## User Profile (Persistent Facts)'));
      expect(context, contains('- Fact 1'));
      expect(context, contains('## Recent Context'));
      expect(context, contains('- Episode 1'));
    });

    test('toContextString returns empty string when empty', () {
      final profile = MemoryProfile(staticFacts: [], dynamicContext: []);

      expect(profile.toContextString(), isEmpty);
    });

    test('toContextString limits static facts to 10', () {
      final profile = MemoryProfile(
        staticFacts: List.generate(15, (i) => 'Fact $i'),
        dynamicContext: [],
      );

      final context = profile.toContextString();

      expect(context, contains('- Fact 9'));
      expect(context, isNot(contains('- Fact 10')));
    });

    test('toContextString limits dynamic context to 5', () {
      final profile = MemoryProfile(
        staticFacts: [],
        dynamicContext: List.generate(10, (i) => 'Episode $i'),
      );

      final context = profile.toContextString();

      expect(context, contains('- Episode 4'));
      expect(context, isNot(contains('- Episode 5')));
    });
  });

  group('GetProfileResponse', () {
    test('parses full response', () {
      final json = {
        'profile': {
          'static': ['User has farm'],
          'dynamic': ['Recently checked pigs'],
        },
        'search_results': [
          {
            'id': '1',
            'content': 'Pig health tips',
            'memory_type': 'fact',
            'similarity': 0.9,
          },
        ],
      };
      final response = GetProfileResponse.fromJson(json);

      expect(response.profile.staticFacts, hasLength(1));
      expect(response.searchResults, hasLength(1));
      expect(response.error, isNull);
    });

    test('handles missing search_results', () {
      final json = {
        'profile': {'static': <dynamic>[], 'dynamic': <dynamic>[]},
      };
      final response = GetProfileResponse.fromJson(json);

      expect(response.searchResults, isEmpty);
    });

    test('toFullContextString combines profile and search results', () {
      final response = GetProfileResponse(
        profile: MemoryProfile(
          staticFacts: ['User is a pig farmer'],
          dynamicContext: [],
        ),
        searchResults: [
          MemorySearchResult(
            id: '1',
            content: 'Feed pigs twice daily',
            memoryType: 'fact',
            similarity: 0.9,
          ),
        ],
      );

      final context = response.toFullContextString();

      expect(context, contains('## User Profile (Persistent Facts)'));
      expect(context, contains('- User is a pig farmer'));
      expect(context, contains('## Relevant Memories'));
      expect(context, contains('- Feed pigs twice daily'));
    });

    test('toFullContextString limits search results to 5', () {
      final response = GetProfileResponse(
        profile: MemoryProfile(staticFacts: [], dynamicContext: []),
        searchResults: List.generate(
          10,
          (i) => MemorySearchResult(
            id: '$i',
            content: 'Memory $i',
            memoryType: 'fact',
            similarity: 0.9,
          ),
        ),
      );

      final context = response.toFullContextString();

      expect(context, contains('- Memory 4'));
      expect(context, isNot(contains('- Memory 5')));
    });
  });

  group('ExtractedMemory', () {
    test('parses full JSON correctly', () {
      final json = {
        'id': 'ext-001',
        'content': 'User prefers morning feeding',
        'type': 'preference',
        'category': 'feeding',
      };
      final memory = ExtractedMemory.fromJson(json);

      expect(memory.id, 'ext-001');
      expect(memory.content, 'User prefers morning feeding');
      expect(memory.type, 'preference');
      expect(memory.category, 'feeding');
    });

    test('handles missing optional fields', () {
      final json = {'content': 'Some extracted memory', 'type': 'fact'};
      final memory = ExtractedMemory.fromJson(json);

      expect(memory.id, isNull);
      expect(memory.category, isNull);
    });

    test('defaults type to fact when missing', () {
      final json = {'content': 'Test'};
      final memory = ExtractedMemory.fromJson(json);

      expect(memory.type, 'fact');
    });

    test('defaults content to empty string when missing', () {
      final json = <String, dynamic>{'type': 'fact'};
      final memory = ExtractedMemory.fromJson(json);

      expect(memory.content, '');
    });
  });

  group('ExtractMemoriesResponse', () {
    test('parses response with memories', () {
      final json = {
        'extracted': 2,
        'memories': [
          {'id': '1', 'content': 'Fact 1', 'type': 'fact'},
          {'id': '2', 'content': 'Fact 2', 'type': 'preference'},
        ],
      };
      final response = ExtractMemoriesResponse.fromJson(json);

      expect(response.extractedCount, 2);
      expect(response.memories, hasLength(2));
      expect(response.hasMemories, isTrue);
      expect(response.error, isNull);
    });

    test('defaults extractedCount to list length when missing', () {
      final json = {
        'memories': [
          {'content': 'Fact 1', 'type': 'fact'},
        ],
      };
      final response = ExtractMemoriesResponse.fromJson(json);

      expect(response.extractedCount, 1);
    });

    test('handles empty memories', () {
      final json = {'extracted': 0, 'memories': <dynamic>[]};
      final response = ExtractMemoriesResponse.fromJson(json);

      expect(response.extractedCount, 0);
      expect(response.memories, isEmpty);
      expect(response.hasMemories, isFalse);
    });

    test('handles missing memories key', () {
      final json = <String, dynamic>{};
      final response = ExtractMemoriesResponse.fromJson(json);

      expect(response.memories, isEmpty);
      expect(response.hasMemories, isFalse);
    });

    test('parses error field', () {
      final json = {
        'extracted': 0,
        'memories': <dynamic>[],
        'error': 'Extract failed',
      };
      final response = ExtractMemoriesResponse.fromJson(json);

      expect(response.error, 'Extract failed');
    });
  });

  // ─── MemoryService Tests ──────────────────────────────────────────────────

  group('MemoryService', () {
    test('getContainerTag returns user-prefixed tag', () {
      final service = MemoryService(
        baseUrl: 'http://localhost:8000/api/v1/memory',
      );
      expect(service.getContainerTag('user-123'), 'user-user-123');
      service.dispose();
    });

    test('getFarmContainerTag returns farm-prefixed tag', () {
      final service = MemoryService(
        baseUrl: 'http://localhost:8000/api/v1/memory',
      );
      expect(service.getFarmContainerTag('farm-abc'), 'farm-farm-abc-context');
      service.dispose();
    });

    test('uses provided baseUrl', () {
      final service = MemoryService(baseUrl: 'http://custom:9000/api');
      expect(service.baseUrl, 'http://custom:9000/api');
      service.dispose();
    });
  });

  group('MemoryService.addMemory', () {
    test('sends correct request and parses success response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://test:8000/api/v1/memory/add');
        expect(request.method, 'POST');
        expect(request.headers['Content-Type'], 'application/json');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['container_tag'], 'user-123');
        expect(body['content'], 'User has 20 pigs');
        expect(body['memory_type'], 'fact');
        expect(body['category'], 'livestock');

        return http.Response(
          jsonEncode({'id': 'mem-001', 'status': 'created'}),
          201,
        );
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.addMemory(
        containerTag: 'user-123',
        content: 'User has 20 pigs',
        memoryType: 'fact',
        category: 'livestock',
      );

      expect(response.isSuccess, isTrue);
      expect(response.id, 'mem-001');
      expect(response.status, 'created');
    });

    test('omits category when null', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('category'), isFalse);

        return http.Response(jsonEncode({'id': '1', 'status': 'ok'}), 200);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.addMemory(
        containerTag: 'user-123',
        content: 'Test content',
      );

      expect(response.isSuccess, isTrue);
    });

    test('returns error response on non-200/201 status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.addMemory(
        containerTag: 'user-123',
        content: 'Test',
      );

      expect(response.isSuccess, isFalse);
      expect(response.status, 'error');
      expect(response.error, contains('500'));
    });

    test('returns error response on network exception', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Connection refused');
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.addMemory(
        containerTag: 'user-123',
        content: 'Test',
      );

      expect(response.isSuccess, isFalse);
      expect(response.status, 'error');
      expect(response.error, contains('Connection refused'));
    });
  });

  group('MemoryService.searchMemories', () {
    test('sends correct request and parses results', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), 'http://test:8000/api/v1/memory/search');
        expect(request.method, 'POST');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['container_tag'], 'user-123');
        expect(body['query'], 'pig feeding');
        expect(body['limit'], 5);
        expect(body['threshold'], 0.8);

        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'mem-001',
                'content': 'Feed pigs twice daily',
                'memory_type': 'fact',
                'similarity': 0.92,
              },
              {
                'id': 'mem-002',
                'content': 'Morning feed at 7AM',
                'memory_type': 'preference',
                'similarity': 0.85,
              },
            ],
          }),
          200,
        );
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.searchMemories(
        containerTag: 'user-123',
        query: 'pig feeding',
        limit: 5,
        threshold: 0.8,
      );

      expect(response.hasResults, isTrue);
      expect(response.results, hasLength(2));
      expect(response.results[0].content, 'Feed pigs twice daily');
      expect(response.results[0].similarity, 0.92);
      expect(response.results[1].content, 'Morning feed at 7AM');
      expect(response.error, isNull);
    });

    test('uses default limit and threshold', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['limit'], 10);
        expect(body['threshold'], 0.7);

        return http.Response(jsonEncode({'results': <dynamic>[]}), 200);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      await service.searchMemories(
        containerTag: 'user-123',
        query: 'test query',
      );
    });

    test('returns empty results on non-200 status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.searchMemories(
        containerTag: 'user-123',
        query: 'test',
      );

      expect(response.hasResults, isFalse);
      expect(response.results, isEmpty);
      expect(response.error, contains('404'));
    });

    test('returns empty results on network exception', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Timeout');
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.searchMemories(
        containerTag: 'user-123',
        query: 'test',
      );

      expect(response.hasResults, isFalse);
      expect(response.error, contains('Timeout'));
    });
  });

  group('MemoryService.extractAndStore', () {
    test('sends correct request and parses response', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.toString(),
          'http://test:8000/api/v1/memory/extract',
        );
        expect(request.method, 'POST');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['container_tag'], 'user-123');
        expect(body['content'], 'I have 20 pigs on my farm');
        expect(body['context'], 'farm conversation');

        return http.Response(
          jsonEncode({
            'extracted': 2,
            'memories': [
              {
                'id': '1',
                'content': 'Has 20 pigs',
                'type': 'fact',
                'category': 'livestock',
              },
              {
                'id': '2',
                'content': 'Owns a farm',
                'type': 'fact',
                'category': 'general',
              },
            ],
          }),
          200,
        );
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.extractAndStore(
        containerTag: 'user-123',
        content: 'I have 20 pigs on my farm',
        context: 'farm conversation',
      );

      expect(response.hasMemories, isTrue);
      expect(response.extractedCount, 2);
      expect(response.memories, hasLength(2));
      expect(response.memories[0].content, 'Has 20 pigs');
      expect(response.memories[0].category, 'livestock');
    });

    test('uses empty context by default', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['context'], '');

        return http.Response(
          jsonEncode({'extracted': 0, 'memories': <dynamic>[]}),
          200,
        );
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      await service.extractAndStore(
        containerTag: 'user-123',
        content: 'Test content',
      );
    });

    test('returns error response on non-200 status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Bad Request', 400);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.extractAndStore(
        containerTag: 'user-123',
        content: 'Test',
      );

      expect(response.hasMemories, isFalse);
      expect(response.extractedCount, 0);
      expect(response.error, contains('400'));
    });

    test('returns error response on network exception', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Connection reset');
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.extractAndStore(
        containerTag: 'user-123',
        content: 'Test',
      );

      expect(response.hasMemories, isFalse);
      expect(response.error, contains('Connection reset'));
    });
  });

  group('MemoryService.storeConversation', () {
    test('formats conversation and calls extractAndStore', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['container_tag'], 'user-123');
        expect(body['content'], contains('User: How many pigs do I have?'));
        expect(body['content'], contains('Assistant: You have 20 pigs'));
        expect(body['context'], 'assistant chat');

        return http.Response(
          jsonEncode({
            'extracted': 1,
            'memories': [
              {'id': '1', 'content': 'Has 20 pigs', 'type': 'fact'},
            ],
          }),
          200,
        );
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final response = await service.storeConversation(
        containerTag: 'user-123',
        userMessage: 'How many pigs do I have?',
        assistantResponse: 'You have 20 pigs',
        additionalContext: 'assistant chat',
      );

      expect(response.hasMemories, isTrue);
      expect(response.memories[0].content, 'Has 20 pigs');
    });

    test('uses empty context when additionalContext is null', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['context'], '');

        return http.Response(
          jsonEncode({'extracted': 0, 'memories': <dynamic>[]}),
          200,
        );
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      await service.storeConversation(
        containerTag: 'user-123',
        userMessage: 'Hello',
        assistantResponse: 'Hi there!',
      );
    });
  });

  group('MemoryService.ensureContainerExists', () {
    test('returns true when addMemory succeeds', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['container_tag'], 'user-123');
        expect(body['content'], 'Memory container initialized');
        expect(body['memory_type'], 'fact');
        expect(body['category'], 'system');

        return http.Response(jsonEncode({'id': '1', 'status': 'created'}), 201);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final result = await service.ensureContainerExists('user-123');

      expect(result, isTrue);
    });

    test('returns false when addMemory fails', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final result = await service.ensureContainerExists('user-123');

      expect(result, isFalse);
    });

    test('returns false on network exception', () async {
      final mockClient = MockClient((request) async {
        throw Exception('No route to host');
      });

      final service = MemoryService(
        baseUrl: 'http://test:8000/api/v1/memory',
        client: mockClient,
      );

      final result = await service.ensureContainerExists('user-123');

      expect(result, isFalse);
    });
  });

  // ─── MemoryApiConfig Tests ────────────────────────────────────────────────

  group('MemoryApiConfig', () {
    test('baseUrl contains memory endpoint path', () {
      final url = MemoryApiConfig.baseUrl;
      expect(url, contains('/api/v1/memory'));
    });

    test('baseUrl starts with http', () {
      final url = MemoryApiConfig.baseUrl;
      expect(url, startsWith('http'));
    });
  });
}
