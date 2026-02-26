import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;

/// OpenAI-compatible content generator for Featherless AI
/// Supports DeepSeek-V3 and other models available on Featherless
class FeatherlessContentGenerator implements ContentGenerator {
  final String apiKey;
  final String modelName;
  final String baseUrl;
  final List<Map<String, dynamic>> _tools;
  final List<Map<String, dynamic>> _messageHistory = [];
  final String _systemPrompt;

  final _a2uiController = StreamController<A2uiMessage>.broadcast();
  final _textResponseController = StreamController<String>.broadcast();
  final _errorController = StreamController<ContentGeneratorError>.broadcast();
  final _isProcessing = ValueNotifier<bool>(false);

  FeatherlessContentGenerator({
    required this.apiKey,
    required this.modelName,
    required List<Catalog> catalogs,
    String? additionalSystemPrompt,
    bool disableTools = false,
    this.baseUrl = 'https://api.featherless.ai/v1',
  }) : _tools = disableTools ? [] : _buildTools(catalogs),
       _systemPrompt = _buildSystemPrompt(catalogs, additionalSystemPrompt);

  static String _buildSystemPrompt(
    List<Catalog> catalogs,
    String? additionalSystemPrompt,
  ) {
    if (catalogs.isEmpty) {
      return additionalSystemPrompt ?? 'You are a helpful farm assistant.';
    }

    final basePrompt = genUiTechPrompt(
      catalogs.map((c) => 'render_${c.catalogId}').toList(),
    );

    return additionalSystemPrompt != null
        ? '$basePrompt\n\n$additionalSystemPrompt'
        : basePrompt;
  }

  static List<Map<String, dynamic>> _buildTools(List<Catalog> catalogs) {
    return catalogs.map((c) {
      final toolName = 'render_${c.catalogId}';
      final decl = catalogToFunctionDeclaration(
        c,
        toolName,
        'Generates UI for ${c.catalogId}',
      );

      // Build a simple schema for OpenAI format
      return {
        'type': 'function',
        'function': {
          'name': decl.name,
          'description': decl.description,
          'parameters': {
            'type': 'object',
            'properties': {
              'surfaceId': {
                'type': 'string',
                'description': 'Unique identifier for this UI surface',
              },
              'components': {
                'type': 'array',
                'description': 'Array of UI components to render',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'component': {'type': 'object'},
                  },
                },
              },
            },
            'required': ['surfaceId', 'components'],
          },
        },
      };
    }).toList();
  }

  @override
  Stream<A2uiMessage> get a2uiMessageStream => _a2uiController.stream;

  @override
  Stream<String> get textResponseStream => _textResponseController.stream;

  @override
  Stream<ContentGeneratorError> get errorStream => _errorController.stream;

  @override
  ValueListenable<bool> get isProcessing => _isProcessing;

  @override
  Future<void> sendRequest(
    ChatMessage message, {
    Iterable<ChatMessage>? history,
    A2UiClientCapabilities? clientCapabilities,
  }) async {
    _isProcessing.value = true;
    try {
      String text = "";
      if (message is AiTextMessage) text = message.text;
      if (message is UserMessage) text = message.text;
      if (message is UserUiInteractionMessage) text = message.text;

      // Add user message to history
      _messageHistory.add({'role': 'user', 'content': text});

      // Build request body
      final body = <String, dynamic>{
        'model': modelName,
        'messages': [
          {'role': 'system', 'content': _systemPrompt},
          ..._messageHistory,
        ],
        'temperature': 0.7,
        'max_tokens': 4096,
      };

      // Add tools if available
      if (_tools.isNotEmpty) {
        body['tools'] = _tools;
        body['tool_choice'] = 'auto';
      }

      debugPrint('Sending request to Featherless: $modelName');

      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        final error =
            'Featherless API error: ${response.statusCode} - ${response.body}';
        debugPrint(error);
        throw Exception(error);
      }

      final data = jsonDecode(response.body);
      final choice = data['choices'][0];
      final assistantMessage = choice['message'];

      // Handle text response
      final content = assistantMessage['content'] as String?;
      if (content != null && content.isNotEmpty) {
        _textResponseController.add(content);
        _messageHistory.add({'role': 'assistant', 'content': content});
      }

      // Handle tool calls
      final toolCalls = assistantMessage['tool_calls'] as List<dynamic>?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        for (final toolCall in toolCalls) {
          final function = toolCall['function'];
          final toolName = function['name'] as String;
          final arguments = jsonDecode(function['arguments'] as String);

          debugPrint('Tool Call: $toolName, Args: $arguments');

          var safeArgs = Map<String, dynamic>.from(arguments);
          var finalToolName = toolName;

          // Handle direct component calls (same logic as Gemini version)
          safeArgs = _normalizeAndFixArgs(finalToolName, safeArgs);
          if (!finalToolName.startsWith('render_')) {
            finalToolName = 'render_farm';
          }

          debugPrint("Final tool call - name: $finalToolName, args: $safeArgs");

          // Use genui's parseToolCall to convert to A2uiMessage
          final genUiToolCall = ToolCall(args: safeArgs, name: finalToolName);
          try {
            final parsed = parseToolCall(genUiToolCall, finalToolName);
            debugPrint(
              "Successfully parsed tool call, messages: ${parsed.messages.length}",
            );
            for (var msg in parsed.messages) {
              _a2uiController.add(msg);
            }
          } catch (e, stackTrace) {
            debugPrint("Error parsing tool call: $e");
            debugPrint("Stack trace: $stackTrace");
          }
        }

        // Add tool call to history
        _messageHistory.add({'role': 'assistant', 'tool_calls': toolCalls});
      }
    } catch (e, stack) {
      debugPrint('Featherless error: $e');
      _errorController.add(ContentGeneratorError(e, stack));
    } finally {
      _isProcessing.value = false;
    }
  }

  Map<String, dynamic> _normalizeAndFixArgs(
    String toolName,
    Map<String, dynamic> args,
  ) {
    final knownComponents = [
      'showAnimal',
      'logFeeding',
      'createReminder',
      'create_reminder',
      'show_animal',
      'log_feeding',
      'generateReport',
      'generate_report',
      'showHealthRecord',
      'show_health_record',
      'generateInviteCode',
      'generate_invite_code',
    ];

    final normalizedCallName = toolName.replaceAll('_', '').toLowerCase();
    final matchedComponent = knownComponents.firstWhere(
      (c) => c.replaceAll('_', '').toLowerCase() == normalizedCallName,
      orElse: () => '',
    );

    if (matchedComponent.isNotEmpty) {
      debugPrint(
        "Fixing: Converting direct component call '$toolName' to render_farm",
      );

      String componentName;
      switch (normalizedCallName) {
        case 'createreminder':
          componentName = 'createReminder';
          break;
        case 'showanimal':
          componentName = 'showAnimal';
          break;
        case 'logfeeding':
          componentName = 'logFeeding';
          break;
        case 'generatereport':
          componentName = 'generateReport';
          break;
        case 'showhealthrecord':
          componentName = 'showHealthRecord';
          break;
        case 'generateinvitecode':
          componentName = 'generateInviteCode';
          break;
        default:
          componentName = matchedComponent;
      }

      // Wrap the direct call args in the proper GenUI structure
      return {
        'surfaceId': 'surface_${DateTime.now().microsecondsSinceEpoch}',
        'components': [
          {
            'id': 'comp_${DateTime.now().microsecondsSinceEpoch}',
            'component': {componentName: Map<String, dynamic>.from(args)},
          },
        ],
      };
    }

    // Fix: Handle Map instead of List for components
    if (args.containsKey('components') && args['components'] is Map) {
      debugPrint("Fixing: Converting components Map to List");
      final map = args['components'] as Map;
      final newList = [];
      map.forEach((key, value) {
        if (value is Map) {
          final item = Map<String, dynamic>.from(value);
          if (!item.containsKey('id')) item['id'] = key.toString();
          newList.add(item);
        }
      });
      args['components'] = newList;
    } else if (args.containsKey('components') && args['components'] is! List) {
      debugPrint("Fixing: Wrapping single component in list");
      args['components'] = [args['components']];
    }

    // Ensure items in 'components' have 'component' wrapper if missing
    if (args['components'] is List) {
      final list = args['components'] as List;
      for (int i = 0; i < list.length; i++) {
        if (list[i] is Map) {
          final item = Map<String, dynamic>.from(list[i] as Map);

          if (!item.containsKey('component')) {
            // Check if this looks like a raw component
            if (item.containsKey('type') || item.containsKey('text')) {
              final id = item['id'] ?? 'comp_$i';
              item.remove('id');
              list[i] = {'id': id, 'component': item};
            }
          }
        }
      }
    }

    return args;
  }

  @override
  void dispose() {
    _a2uiController.close();
    _textResponseController.close();
    _errorController.close();
  }
}
