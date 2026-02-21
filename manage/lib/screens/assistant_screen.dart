import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genui/genui.dart';
import 'package:intl/intl.dart';
import 'package:manage/config/genui_catalog.dart';
import 'package:manage/config/theme.dart';
import 'package:manage/models/animal.dart';
import 'package:manage/models/health_record.dart';
import 'package:manage/providers/auth_providers.dart';
import 'package:manage/providers/providers.dart';
import 'package:manage/services/assistant_data_service.dart';
import 'package:manage/services/gemini_content_generator.dart';
import 'package:manage/services/memory_service.dart';
import 'package:manage/utils/env_helper.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final String _apiKey = EnvHelper.getOrDefault('GEMINI_API_KEY', '');
  GenUiConversation? _conversation;
  A2uiMessageProcessor? _processor;
  String? _initError;
  bool _isInitialized = false;

  final _textController = TextEditingController();

  // Memory integration
  MemoryService? _memoryService;
  String? _userContainerTag;
  String? _lastUserMessage;
  StreamSubscription<String>? _responseSubscription;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initializeConversation(List<Animal> animals) async {
    if (_isInitialized) return; // Prevent re-initialization
    _isInitialized = true;

    try {
      if (_apiKey.isEmpty) {
        setState(() {
          _initError = "GEMINI_API_KEY is missing from .env file";
        });
        debugPrint("WARNING: GEMINI_API_KEY is missing from .env");
        return;
      }

      // --- Memory system initialization ---
      String memoryContext = '';
      try {
        _memoryService = ref.read(memoryServiceProvider);
        final user = ref.read(currentUserProvider).value;
        if (user != null) {
          _userContainerTag = _memoryService!.getContainerTag(user.id);
          debugPrint('Memory container tag: $_userContainerTag');

          // Fetch the user's memory profile to inject into the system prompt
          // Search for general preferences and tool usage patterns
          final searchResponse = await _memoryService!
              .searchMemories(
                containerTag: _userContainerTag!,
                query:
                    'farm management preferences context tools health animals reminders',
                limit: 15,
                threshold: 0.4, // Lowered for better recall
              )
              .timeout(
                const Duration(seconds: 15),
              ); // Increased from 5s - embeddings can be slow

          if (searchResponse.hasResults) {
            final memories = searchResponse.results
                .map((m) => '- ${m.content}')
                .join('\n');
            memoryContext =
                '''

=== USER MEMORY CONTEXT ===
You remember these things about the user from previous conversations:
$memories
=== END MEMORY CONTEXT ===
''';
            debugPrint(
              'Loaded ${searchResponse.results.length} memories for assistant context',
            );
          } else {
            debugPrint(
              'No memories found for user (container: $_userContainerTag)',
            );
          }
        } else {
          debugPrint('No user logged in, skipping memory initialization');
        }
      } catch (e) {
        // Memory API unavailable — continue without memory
        debugPrint('Memory service unavailable, continuing without memory: $e');
        _memoryService = null;
        _userContainerTag = null;
      }

      // Use the standard GenUI catalog ID so parseToolCall generates compatible messages
      final catalog = Catalog(farmTools, catalogId: 'farm');
      final standardCatalog = Catalog(
        farmTools,
        catalogId: 'a2ui.org:standard_catalog_0_8_0',
      );
      final catalogs = [catalog, standardCatalog];

      _processor = A2uiMessageProcessor(catalogs: catalogs);

      // Build context about available animals using the passed-in data
      // Include ALL animals.
      String animalContext = "";
      if (animals.isNotEmpty) {
        final animalList = animals
            .map((a) {
              final statusStr = a.status.toString().split('.').last;
              return "- Tag: ${a.tagId}, Name: ${a.name ?? 'unnamed'}, Species: ${a.species.displayName}, Status: $statusStr";
            })
            .join('\n');
        animalContext =
            '''

=== USER'S FARM ANIMALS (${animals.length} total) ===
$animalList
=== END OF ANIMAL LIST ===

CRITICAL: When the user asks about an animal by name or tag ID, you MUST search the list above carefully.
- Search is case-insensitive
- For names, match partial names (e.g., "maria" matches "Maria" or "Maria's Calf")
- For tag IDs, match the exact tag or partial tag
- If found, use the showAnimal tool with the EXACT data from the list
- If not found after careful search, tell the user the animal was not found
''';
      } else {
        animalContext =
            '\nThe user has no animals registered in their farm yet.';
      }

      // Build context about health records
      String healthContext = "";
      try {
        final dataService = ref.read(assistantDataServiceProvider);
        // Wait for health records to load before building context
        final healthRecords = await dataService.waitForHealthRecords(
          timeout: const Duration(seconds: 8), // Increased timeout
        );
        debugPrint(
          'Loaded ${healthRecords.length} health records for assistant context',
        );

        final healthStats = dataService.getHealthStats();
        final upcomingVaccinations = dataService.getUpcomingVaccinations();
        final overdueVaccinations = dataService.getOverdueVaccinations();
        final animalsInWithdrawal = dataService.getAnimalsInWithdrawal();
        final pendingFollowUps = dataService.getPendingFollowUps();

        if (healthRecords.isNotEmpty || healthStats['totalRecords'] > 0) {
          final recentRecordsList = healthRecords
              .take(10)
              .map((r) {
                final dateStr = r.date.toIso8601String().split('T')[0];
                return "- [${r.type.displayName}] ${r.title} (Animal: ${r.animalTagId ?? 'N/A'}, Date: $dateStr, Status: ${r.status.name})";
              })
              .join('\n');

          final upcomingVaxList = upcomingVaccinations
              .take(5)
              .map((r) {
                final dueDate =
                    r.nextDueDate?.toIso8601String().split('T')[0] ?? 'N/A';
                return "- ${r.vaccineName ?? r.title} for ${r.animalTagId ?? 'N/A'}, due: $dueDate";
              })
              .join('\n');

          final overdueVaxList = overdueVaccinations
              .take(5)
              .map((r) {
                final dueDate =
                    r.nextDueDate?.toIso8601String().split('T')[0] ?? 'N/A';
                return "- ${r.vaccineName ?? r.title} for ${r.animalTagId ?? 'N/A'}, was due: $dueDate";
              })
              .join('\n');

          final withdrawalList = animalsInWithdrawal
              .take(5)
              .map((r) {
                final endDate =
                    r.withdrawalEndDate?.toIso8601String().split('T')[0] ??
                    'N/A';
                return "- ${r.animalTagId ?? 'N/A'}: ${r.medicationName ?? r.title}, withdrawal ends: $endDate";
              })
              .join('\n');

          final followUpList = pendingFollowUps
              .take(5)
              .map((r) {
                final followDate =
                    r.followUpDate?.toIso8601String().split('T')[0] ?? 'N/A';
                return "- ${r.title} for ${r.animalTagId ?? 'N/A'}, was due: $followDate";
              })
              .join('\n');

          healthContext =
              '''

=== ANIMAL HEALTH RECORDS ===
Total health records: ${healthStats['totalRecords']}
Records by type: ${healthStats['byType']}
Upcoming vaccinations: ${upcomingVaccinations.length}
Overdue vaccinations: ${overdueVaccinations.length}
Animals in withdrawal period: ${animalsInWithdrawal.length}
Pending follow-ups: ${pendingFollowUps.length}

RECENT HEALTH RECORDS (last 10):
$recentRecordsList

${upcomingVaccinations.isNotEmpty ? 'UPCOMING VACCINATIONS:\n$upcomingVaxList\n' : ''}
${overdueVaccinations.isNotEmpty ? 'OVERDUE VACCINATIONS (URGENT!):\n$overdueVaxList\n' : ''}
${animalsInWithdrawal.isNotEmpty ? 'ANIMALS IN WITHDRAWAL PERIOD (cannot sell meat/milk):\n$withdrawalList\n' : ''}
${pendingFollowUps.isNotEmpty ? 'PENDING FOLLOW-UPS:\n$followUpList\n' : ''}
=== END HEALTH RECORDS ===

When users ask about health records, vaccinations, medications, or animal health:
- Use the health data above to provide accurate information
- Use the showHealthRecord tool to display health record cards
- Alert users about overdue vaccinations or pending follow-ups
- Warn about animals in withdrawal period before they can be sold
''';
        } else {
          healthContext =
              '\nNo health records have been logged yet for this farm.';
        }
      } catch (e) {
        debugPrint('Failed to load health records for assistant: $e');
        healthContext = '\nHealth records are temporarily unavailable.';
      }

      // Generate tools context from catalog definitions
      final toolsContext = generateToolsContext();

      // Current date for context
      final currentDate = DateFormat('MMMM d, yyyy').format(DateTime.now());

      final contentGenerator = GeminiContentGenerator(
        apiKey: _apiKey,
        modelName: 'gemini-2.5-flash',
        catalogs: catalogs,
        disableTools: false,
        additionalSystemPrompt:
            '''
You are a helpful farm management assistant. You help farmers manage their livestock, track feeding schedules, monitor health records, manage reminders/notifications, and analyze farm data.

IMPORTANT: Today's date is $currentDate. Use this year (${DateTime.now().year}) for all date-related requests.

$animalContext
$healthContext
$memoryContext
$toolsContext

RESPONSE GUIDELINES:
1. When asked about an animal, search the ANIMAL LIST above carefully.
2. For simple questions, respond with markdown text.
3. For actions (create reminder, log feeding, log health, show animal), use the render_farm tool with the appropriate component.
4. DO NOT ask for confirmation before showing the form - just show the form directly.
5. If user doesn't provide all required fields, still show the form - they can complete it there.
6. For date ranges like "January" or "last month", use the CURRENT YEAR (${DateTime.now().year}) unless user specifies otherwise.

DO NOT say you cannot remember or don't have memory - you have all the animal and health data listed above!
''',
      );

      _responseSubscription = contentGenerator.textResponseStream.listen((
        responseText,
      ) {
        _storeConversationMemory(responseText);
      });

      _conversation = GenUiConversation(
        contentGenerator: contentGenerator,
        a2uiMessageProcessor: _processor!,
        onError: (error) {
          if (mounted) {
            final errorStr = error.error.toString();
            final isQuotaError =
                errorStr.contains('quota') ||
                errorStr.contains('rate') ||
                errorStr.contains('limit');

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      isQuotaError
                          ? Icons.hourglass_empty_rounded
                          : Icons.error_rounded,
                      color: isQuotaError
                          ? Colors.orange.shade100
                          : Colors.red.shade100,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isQuotaError
                            ? 'API quota exceeded. Please try again later or update your API key.'
                            : 'AI Error: ${error.error}',
                      ),
                    ),
                  ],
                ),
                backgroundColor: isQuotaError
                    ? Colors.orange.shade700
                    : Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        },
      );

      setState(() {});
    } catch (e, stack) {
      debugPrint("Failed to initialize GenUI: $e");
      debugPrint("Stack: $stack");
      setState(() {
        _initError = "Failed to initialize AI: $e";
      });
    }
  }

  /// Store a conversation exchange in the memory system (fire-and-forget)
  void _storeConversationMemory(String assistantResponse) {
    if (_memoryService == null ||
        _userContainerTag == null ||
        _lastUserMessage == null) {
      return;
    }

    final userMsg = _lastUserMessage!;
    _lastUserMessage = null;

    // Build health context for better memory extraction
    String healthContext = '';
    try {
      final dataService = ref.read(assistantDataServiceProvider);
      final healthStats = dataService.getHealthStats();
      final recentRecords = dataService.getRecentHealthRecords(limit: 5);

      if (recentRecords.isNotEmpty) {
        final recordSummary = recentRecords
            .map(
              (r) =>
                  '${r.type.displayName}: ${r.title} for animal ${r.animalTagId ?? "unknown"}',
            )
            .join('; ');

        healthContext =
            '''
Farm health context:
- Total health records: ${healthStats['totalRecords']}
- Records by type: ${healthStats['byType']}
- Upcoming vaccinations: ${healthStats['upcomingVaccinationsCount']}
- Overdue vaccinations: ${healthStats['overdueVaccinationsCount']}
- Animals in withdrawal: ${healthStats['animalsInWithdrawalCount']}
- Recent records: $recordSummary

Categories for health memories: animal_health, vaccination, medication, treatment, checkup, surgery, observation, withdrawal_period, follow_up
''';
      }
    } catch (e) {
      debugPrint('Failed to build health context: $e');
    }

    _memoryService!
        .storeConversation(
          containerTag: _userContainerTag!,
          userMessage: userMsg,
          assistantResponse: assistantResponse,
          additionalContext: healthContext,
        )
        .then((_) {
          debugPrint('Conversation stored in memory');
        })
        .catchError((e) {
          debugPrint('Failed to store conversation in memory: $e');
        });
  }

  void _resetAndReinitialize() {
    _responseSubscription?.cancel();
    _responseSubscription = null;
    setState(() {
      _isInitialized = false;
      _initError = null;
      _conversation?.dispose();
      _conversation = null;
    });
  }

  @override
  void dispose() {
    _responseSubscription?.cancel();
    // Don't dispose memory service - it's a singleton provider and will be reused
    _conversation?.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animalsAsync = ref.watch(allAnimalsForAIProvider);

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Farm Assistant")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  'Failed to Initialize AI Assistant',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _initError!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _resetAndReinitialize,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Wait for animals data to load before initializing
    return animalsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text("Farm Assistant")),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading farm data...'),
            ],
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text("Farm Assistant")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text('Failed to load farm data: $error'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(allAnimalsForAIProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (animals) {
        // Initialize conversation once we have animal data
        if (!_isInitialized && _conversation == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initializeConversation(animals);
          });
        }

        if (_conversation == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Farm Assistant")),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Initializing AI with ${animals.length} animals...'),
                ],
              ),
            ),
          );
        }

        return _buildMainScreen(context, animals);
      },
    );
  }

  Widget _buildMainScreen(BuildContext context, List<Animal> animals) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Farm Assistant"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh farm data',
            onPressed: () {
              _resetAndReinitialize();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.sync, color: Colors.white, size: 20),
                      SizedBox(width: 12),
                      Text('Refreshing AI assistant...'),
                    ],
                  ),
                  backgroundColor: AppTheme.farmGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(animals)),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<Animal> animals) {
    // Get total animals count for display
    final totalAnimals = animals.length;

    return ValueListenableBuilder(
      valueListenable: _conversation!.conversation,
      builder: (context, messages, _) {
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, size: 64, color: AppTheme.farmGreen),
                  const SizedBox(height: 16),
                  Text(
                    'Farm AI Assistant',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalAnimals > 0
                        ? 'I have access to $totalAnimals animals in your farm.'
                        : 'No animals found in your farm yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Container(
                  //   padding: const EdgeInsets.all(16),
                  //   decoration: BoxDecoration(
                  //     color: Theme.of(context)
                  //         .colorScheme
                  //         .surfaceContainerHighest
                  //         .withValues(alpha: 0.5),
                  //     borderRadius: BorderRadius.circular(12),
                  //   ),
                  //   child: Column(
                  //     crossAxisAlignment: CrossAxisAlignment.start,
                  //     children: [
                  //       Text(
                  //         'Try asking:',
                  //         style: Theme.of(context).textTheme.labelLarge
                  //             ?.copyWith(fontWeight: FontWeight.bold),
                  //       ),
                  //       const SizedBox(height: 8),
                  //       Text(
                  //         '• "Show me animal [tag ID]"\n'
                  //         '• "Get info on [animal name]"\n'
                  //         '• "Log feeding for [animal]"\n'
                  //         '• "How many animals do I have?"',
                  //         style: Theme.of(context).textTheme.bodySmall
                  //             ?.copyWith(
                  //               color: Colors.grey.shade600,
                  //               height: 1.5,
                  //             ),
                  //       ),
                  //     ],
                  //   ),
                  // ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: messages.length,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            final msg = messages[index];
            if (msg is UserMessage) {
              return Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12, left: 48),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              );
            } else if (msg is AiTextMessage) {
              return _buildAiMessage(context, msg.text);
            } else if (msg is AiUiMessage) {
              // Render the dynamic UI
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                constraints: const BoxConstraints(maxHeight: 350),
                child: GenUiSurface(
                  host: _conversation!.host,
                  surfaceId: msg.surfaceId,
                ),
              );
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: "Ask about animals or log feeding...",
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _conversation!.contentGenerator.isProcessing,
              builder: (context, isProcessing, _) {
                return IconButton.filled(
                  onPressed: isProcessing ? null : _sendMessage,
                  icon: isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Track the user's message for memory storage
    _lastUserMessage = text;

    _conversation!.sendRequest(UserMessage.text(text));
    _textController.clear();
  }

  Widget _buildAiMessage(BuildContext context, String text) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Avatar
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.farmGreen, AppTheme.accentLime],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          // Message Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium,
                  h1: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  h2: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  h3: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  listBullet: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                  strong: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  em: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                  blockquote: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: colorScheme.primary, width: 4),
                    ),
                  ),
                  code: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: colorScheme.surfaceContainerLow,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  tableBorder: TableBorder.all(
                    color: colorScheme.outlineVariant,
                    width: 1,
                  ),
                  tableHead: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  horizontalRuleDecoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
