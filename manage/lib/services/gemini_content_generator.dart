import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as google_ai;
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;

class GeminiContentGenerator implements ContentGenerator {
  late final google_ai.GenerativeModel _chatModel;
  late final google_ai.ChatSession _chatSession;

  final _a2uiController = StreamController<A2uiMessage>.broadcast();
  final _textResponseController = StreamController<String>.broadcast();
  final _errorController = StreamController<ContentGeneratorError>.broadcast();
  final _isProcessing = ValueNotifier<bool>(false);

  GeminiContentGenerator({
    required String apiKey,
    required String modelName,
    required List<Catalog> catalogs,
    String? additionalSystemPrompt,
    bool disableTools = false,
  }) {
    List<google_ai.Tool>? modelTools;
    String fullPrompt;

    if (!disableTools && catalogs.isNotEmpty) {
      final tools = catalogs.map((c) {
        final toolName = 'render_${c.catalogId}';
        final decl = catalogToFunctionDeclaration(
          c,
          toolName,
          'Generates UI for ${c.catalogId}',
        );

        final jsbSchema = decl.parameters as jsb.Schema;
        debugPrint("JSB Schema for $toolName: $jsbSchema");

        final geminiSchema = decl.parameters == null
            ? null
            : _convertSchema(jsbSchema);

        return google_ai.FunctionDeclaration(
          decl.name,
          decl.description,
          geminiSchema,
        );
      }).toList();

      modelTools = [google_ai.Tool(functionDeclarations: tools)];

      // Combine the technical prompt with any additional context
      final basePrompt = genUiTechPrompt(
        catalogs.map((c) => 'render_${c.catalogId}').toList(),
      );
      fullPrompt = additionalSystemPrompt != null
          ? '$basePrompt\n\n$additionalSystemPrompt'
          : basePrompt;
    } else {
      // No tools, just use the additional prompt directly
      fullPrompt =
          additionalSystemPrompt ?? 'You are a helpful farm assistant.';
    }

    _chatModel = google_ai.GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      tools: modelTools,
      systemInstruction: google_ai.Content.system(fullPrompt),
    );
    _chatSession = _chatModel.startChat();
  }

  static google_ai.Schema _convertSchema(jsb.Schema input) {
    try {
      return _convertSchemaImpl(input);
    } catch (e, stack) {
      debugPrint("Schema Conversion Failed for input: $input");
      debugPrint("Error: $e");
      debugPrint("Stack: $stack");
      // Fallback to avoid crash
      return google_ai.Schema.object(properties: {}, nullable: true);
    }
  }

  static google_ai.Schema _convertSchemaImpl(jsb.Schema input) {
    final typeRaw = input.type;

    // Helper: check if type is or contains specific JsonType or its string representation
    bool hasType(jsb.JsonType target) {
      try {
        if (typeRaw == target) return true;

        final targetName = target.toString().split('.').last;
        if (typeRaw is String && typeRaw == targetName) return true;

        // Defensive check: typeRaw could be a List, but we must ensure it's not a Map masquerading as dynamic
        if (typeRaw is List) {
          return typeRaw.contains(target) || typeRaw.contains(targetName);
        }
      } catch (e) {
        // ignore
      }
      return false;
    }

    if (hasType(jsb.JsonType.string)) {
      return google_ai.Schema.string(
        description: input.description,
        nullable: true,
      );
    }
    if (hasType(jsb.JsonType.num)) {
      return google_ai.Schema.number(
        description: input.description,
        nullable: true,
      );
    }
    if (hasType(jsb.JsonType.int)) {
      return google_ai.Schema.integer(
        description: input.description,
        nullable: true,
      );
    }
    if (hasType(jsb.JsonType.boolean)) {
      return google_ai.Schema.boolean(
        description: input.description,
        nullable: true,
      );
    }
    if (hasType(jsb.JsonType.list)) {
      final itemsRaw = input.schemaOrBool('items');
      return google_ai.Schema.array(
        items: itemsRaw != null
            ? _convertSchema(itemsRaw)
            : google_ai.Schema.object(properties: {}, nullable: true),
        description: input.description,
        nullable: true,
      );
    }

    // Default to object if it looks like one OR if type is null (handles complex types/anyOf/oneOf/generic)
    if (hasType(jsb.JsonType.object) ||
        input['properties'] != null ||
        typeRaw == null) {
      final props = <String, google_ai.Schema>{};
      final propertiesMap = input.mapToSchemaOrBool('properties');
      propertiesMap?.forEach((key, value) {
        props[key] = _convertSchema(value);
      });

      List<String>? requiredList;
      final requiredRaw = input['required'];
      if (requiredRaw is List) {
        // Only include strings, filter out anything else safely
        requiredList = requiredRaw.whereType<String>().toList();
      }

      return google_ai.Schema.object(
        properties: props,
        requiredProperties: requiredList,
        description: input.description,
        nullable: true,
      );
    }

    // Ultimate fallback
    return google_ai.Schema.object(
      properties: {},
      description: input.description,
      nullable: true,
    );
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

      google_ai.GenerateContentResponse response;
      try {
        response = await _chatSession.sendMessage(google_ai.Content.text(text));
      } catch (e) {
        final errorStr = e.toString();
        // Handle SDK parsing errors (like MALFORMED_FUNCTION_CALL from thinking models)
        if (errorStr.contains('MALFORMED_FUNCTION_CALL') ||
            errorStr.contains('Unhandled format')) {
          debugPrint(
            'SDK parsing error, asking model to retry with correct format: $e',
          );
          // Retry asking the model to regenerate the response with proper function call format
          response = await _chatSession.sendMessage(
            google_ai.Content.text(
              '''There was a malformed function call error. Please retry with the EXACT correct format.

CRITICAL: Use render_farm with this exact JSON structure:
{
  "surfaceId": "unique_id",
  "components": [{
    "id": "comp_1",
    "component": {
      "TOOL_NAME": { ...parameters... }
    }
  }]
}

For example, for generateReport:
{
  "surfaceId": "report_123",
  "components": [{
    "id": "comp_1",
    "component": {
      "generateReport": {
        "reportType": "inventory",
        "format": "pdf"
      }
    }
  }]
}

Now please answer the original question: $text''',
            ),
          );
        } else {
          rethrow;
        }
      }

      if (response.text != null && response.text!.isNotEmpty) {
        _textResponseController.add(response.text!);
      }

      final calls = response.functionCalls;
      for (final call in calls) {
        debugPrint("Tool Call: ${call.name}, Args: ${call.args}");

        var safeArgs = Map<String, dynamic>.from(call.args);
        var toolName = call.name;

        // Fix 0: Handle direct component calls (e.g., 'create_reminder' instead of 'render_farm')
        // The AI sometimes calls component names directly instead of using render_<catalog>
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
        final normalizedCallName = call.name.replaceAll('_', '').toLowerCase();
        final matchedComponent = knownComponents.firstWhere(
          (c) => c.replaceAll('_', '').toLowerCase() == normalizedCallName,
          orElse: () => '',
        );

        if (matchedComponent.isNotEmpty) {
          debugPrint(
            "Fixing: Converting direct component call '$toolName' to render_farm",
          );
          // Convert component name to camelCase for the schema
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
          safeArgs = {
            'surfaceId': 'surface_${DateTime.now().microsecondsSinceEpoch}',
            'components': [
              {
                'id': 'comp_${DateTime.now().microsecondsSinceEpoch}',
                'component': {
                  componentName: Map<String, dynamic>.from(call.args),
                },
              },
            ],
          };
          toolName = 'render_farm';
        }

        // Fix 1: Handle Map instead of List for components (AI often returns Map<ID, ComponentDef>)
        if (safeArgs.containsKey('components') &&
            safeArgs['components'] is Map) {
          debugPrint("Fixing: Converting components Map to List");
          final map = safeArgs['components'] as Map;
          final newList = [];
          map.forEach((key, value) {
            if (value is Map) {
              final item = Map<String, dynamic>.from(value);
              // Use key as ID if not present
              if (!item.containsKey('id')) item['id'] = key.toString();
              newList.add(item);
            }
          });
          safeArgs['components'] = newList;
        } else if (safeArgs.containsKey('components') &&
            safeArgs['components'] is! List) {
          debugPrint("Fixing: Wrapping single component in list");
          safeArgs['components'] = [safeArgs['components']];
        }

        // Fix 2: Ensure items in 'components' have 'component' wrapper if missing
        // This handles the case where AI outputs {type: 'Text'} instead of {component: {Text: ...}}
        // Also handles when AI uses generic UI components (Card, Button) instead of catalog items
        if (safeArgs['components'] is List) {
          final list = safeArgs['components'] as List;
          final fixedList = [];

          // Map of catalog component names (case-insensitive matching)
          final catalogComponents = {
            'showanimal': 'showAnimal',
            'logfeeding': 'logFeeding',
            'createreminder': 'createReminder',
          };

          for (var item in list) {
            if (item is Map) {
              final itemMap = Map<String, dynamic>.from(item);

              // Ensure 'id' exists
              if (!itemMap.containsKey('id')) {
                itemMap['id'] = 'gen_${DateTime.now().microsecondsSinceEpoch}';
              }

              // Fix 2a: Handle componentType format (AI generating generic UI)
              // e.g., {componentType: "Card", children: [...]}
              // We need to look for our catalog items in the children or just ignore generic UI
              if (!itemMap.containsKey('component') &&
                  itemMap.containsKey('componentType')) {
                final compType =
                    (itemMap['componentType'] as String?)?.toLowerCase() ?? '';

                // Check if this is actually one of our catalog components
                if (catalogComponents.containsKey(compType)) {
                  final catalogName = catalogComponents[compType]!;
                  final props = Map<String, dynamic>.from(itemMap);
                  props.remove('componentType');
                  props.remove('id');
                  props.remove('children');

                  final newItem = {
                    'id': itemMap['id'],
                    'component': {catalogName: props},
                  };
                  fixedList.add(newItem);
                  debugPrint(
                    "Fixing: Converted componentType $compType to catalog component $catalogName",
                  );
                } else {
                  // This is a generic UI component (Card, Button, etc.)
                  // Look for catalog components in children
                  debugPrint(
                    "Warning: AI generated generic UI component: $compType - searching children for catalog items",
                  );

                  if (itemMap.containsKey('children') &&
                      itemMap['children'] is List) {
                    // Try to extract any useful data from children for a createReminder
                    // This is a best-effort fallback
                    final children = itemMap['children'] as List;
                    Map<String, dynamic>? reminderData;

                    for (var child in children) {
                      if (child is Map) {
                        // Look for onPress with toolCode that contains reminder data
                        if (child.containsKey('onPress') &&
                            child['onPress'] is Map) {
                          final onPress = child['onPress'] as Map;
                          if (onPress.containsKey('toolCode')) {
                            final toolCode = onPress['toolCode'] as String?;
                            if (toolCode != null &&
                                toolCode.contains('create_reminder')) {
                              // Extract parameters from the toolCode string
                              reminderData = _extractReminderDataFromToolCode(
                                toolCode,
                              );
                            }
                          }
                        }
                      }
                    }

                    // If we found reminder data, create a proper component
                    if (reminderData != null) {
                      final newItem = {
                        'id': itemMap['id'],
                        'component': {'createReminder': reminderData},
                      };
                      fixedList.add(newItem);
                      debugPrint(
                        "Fixing: Extracted createReminder from generic UI: $reminderData",
                      );
                    }
                  }
                  // If we couldn't extract anything useful, skip this component
                }
                continue;
              }

              // Fix 2b: Check if it's the "flat" style: {type: 'MyTool', ...props}
              // valid style: {id: ..., component: { MyTool: {...props} }}
              if (!itemMap.containsKey('component') &&
                  itemMap.containsKey('type')) {
                final type = itemMap['type'] as String;
                final props = Map<String, dynamic>.from(itemMap);
                props.remove('type');
                props.remove('id'); // id stays at root

                // Construct valid item
                final newItem = {
                  'id': itemMap['id'],
                  'component': {type: props},
                };
                fixedList.add(newItem);
                debugPrint(
                  "Fixing: Converted flat component $type to wrapper style",
                );
              } else {
                fixedList.add(itemMap);
              }
            } else {
              fixedList.add(item);
            }
          }
          safeArgs['components'] = fixedList;
        }

        debugPrint("Final tool call - name: $toolName, args: $safeArgs");
        final toolCall = ToolCall(args: safeArgs, name: toolName);
        try {
          final parsed = parseToolCall(toolCall, toolName);
          debugPrint(
            "Successfully parsed tool call, messages: ${parsed.messages.length}",
          );
          for (var msg in parsed.messages) {
            _a2uiController.add(msg);
          }
          await _chatSession.sendMessage(
            google_ai.Content.functionResponse(call.name, {'status': 'ok'}),
          );
        } catch (e, stackTrace) {
          debugPrint("Error parsing tool call: $e");
          debugPrint("Stack trace: $stackTrace");
          debugPrint("Tool name was: $toolName");
          debugPrint("Args were: $safeArgs");
          await _chatSession.sendMessage(
            google_ai.Content.functionResponse(call.name, {
              'status': 'error',
              'message': e.toString(),
            }),
          );
        }
      }
    } catch (e, stack) {
      final errorStr = e.toString();
      // Handle malformed function call by sending a text response
      if (errorStr.contains('MALFORMED_FUNCTION_CALL')) {
        debugPrint('Malformed function call detected, asking model to retry');
        _textResponseController.add(
          'I encountered an issue generating the UI. Let me try responding with text instead.',
        );
      } else {
        _errorController.add(ContentGeneratorError(e, stack));
      }
    } finally {
      _isProcessing.value = false;
    }
  }

  /// Helper to extract reminder data from a toolCode string like:
  /// print(default_api.create_reminder(title='...', daysFromNow=1, ...))
  static Map<String, dynamic>? _extractReminderDataFromToolCode(
    String toolCode,
  ) {
    try {
      final result = <String, dynamic>{};

      // Extract key=value pairs using regex
      // Match: key='value' or key="value" or key=number
      final paramRegex = RegExp(
        r'''(\w+)\s*=\s*(?:'([^']*)'|"([^"]*)"|(\d+))''',
      );
      final matches = paramRegex.allMatches(toolCode);

      for (final match in matches) {
        final key = match.group(1);
        final stringValue1 = match.group(2); // single quoted
        final stringValue2 = match.group(3); // double quoted
        final numValue = match.group(4); // number

        if (key != null) {
          // Convert snake_case to camelCase for our schema
          final camelKey = key.replaceAllMapped(
            RegExp(r'_([a-z])'),
            (m) => m.group(1)!.toUpperCase(),
          );

          if (numValue != null) {
            result[camelKey] = int.tryParse(numValue) ?? numValue;
          } else {
            result[camelKey] = stringValue1 ?? stringValue2 ?? '';
          }
        }
      }

      // Ensure we have at least a title
      if (result.containsKey('title') && result['title'] != null) {
        return result;
      }
      return null;
    } catch (e) {
      debugPrint("Error extracting reminder data from toolCode: $e");
      return null;
    }
  }

  @override
  void dispose() {
    _a2uiController.close();
    _textResponseController.close();
    _errorController.close();
  }
}
