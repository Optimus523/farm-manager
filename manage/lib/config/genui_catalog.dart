import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:manage/screens/genui_components/animal_card.dart';
import 'package:manage/screens/genui_components/feeding_form.dart';
import 'package:manage/screens/genui_components/health_card.dart';
import 'package:manage/screens/genui_components/invite_code_form.dart';
import 'package:manage/screens/genui_components/reminder_form.dart';
import 'package:manage/screens/genui_components/report_form.dart';

/// Tool definitions that can be stored in memory for the assistant to recall
class ToolDefinition {
  final String name;
  final String description;
  final List<String> requiredParams;
  final Map<String, String> optionalParams;
  final List<String>? examples;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.requiredParams,
    required this.optionalParams,
    this.examples,
  });

  String toContextString() {
    final buffer = StringBuffer();
    buffer.writeln('**$name** - $description');
    buffer.writeln('   Required: ${requiredParams.join(", ")}');
    if (optionalParams.isNotEmpty) {
      buffer.writeln('   Optional: ${optionalParams.keys.join(", ")}');
    }
    if (examples != null && examples!.isNotEmpty) {
      buffer.writeln('   Examples:');
      for (final example in examples!) {
        buffer.writeln('   - $example');
      }
    }
    return buffer.toString();
  }
}

/// All available tools with their definitions for memory storage
const List<ToolDefinition> toolDefinitions = [
  ToolDefinition(
    name: 'showAnimal',
    description: 'Display an animal card with details',
    requiredParams: ['tagId', 'species'],
    optionalParams: {
      'name': 'Name of the animal',
      'breed': 'Breed of the animal',
      'status': 'Current status: healthy, sick, pregnant, etc.',
    },
  ),
  ToolDefinition(
    name: 'showHealthRecord',
    description: 'Display a health record card',
    requiredParams: ['animalTagId', 'type', 'title'],
    optionalParams: {
      'date': 'Date in YYYY-MM-DD format',
      'status': 'Status: pending, inProgress, completed, cancelled',
      'severity': 'Severity level: low, medium, high, critical',
      'description': 'Notes about the health event',
      'diagnosis': 'Medical diagnosis',
      'treatment': 'Treatment administered',
      'vaccineName': 'Name of vaccine',
      'medicationName': 'Name of medication',
      'dosage': 'Dosage of medication',
      'nextDueDate': 'Next vaccination due date',
      'followUpDate': 'Follow-up appointment date',
      'withdrawalEndDate': 'End of withdrawal period',
      'veterinarianName': 'Name of the vet',
      'cost': 'Cost of the procedure',
    },
    examples: [
      'Types: Vaccination, Medication, Checkup, Treatment, Surgery, Observation',
    ],
  ),
  ToolDefinition(
    name: 'logFeeding',
    description: 'Show a feeding log form to record animal feeding',
    requiredParams: ['animalId', 'feedType', 'quantity'],
    optionalParams: {'date': 'Date of feeding in YYYY-MM-DD format'},
  ),
  ToolDefinition(
    name: 'createReminder',
    description: 'Show a reminder creation form',
    requiredParams: ['title'],
    optionalParams: {
      'description': 'Detailed description of what needs to be done',
      'dueDate': 'Due date (YYYY-MM-DD)',
      'daysFromNow': 'Days from today (1=tomorrow, 7=next week)',
      'type': 'Type: breeding, health, weightCheck, custom',
      'priority': 'Priority: low, medium, high, urgent',
      'animalTagId': 'Tag ID of related animal',
    },
    examples: [
      '"Remind me to vaccinate pig 123 tomorrow" → title="Vaccinate pig 123", daysFromNow=1, type="health"',
      '"Set reminder for next week to check goats" → title="Check the goats", daysFromNow=7',
    ],
  ),
  ToolDefinition(
    name: 'createInviteCode',
    description: 'Generate an invite code to add team members to the farm',
    requiredParams: ['email'],
    optionalParams: {
      'role': 'Role: owner, manager, worker, vet (default: worker)',
      'maxUses': 'Maximum uses (default: 1)',
      'validityDays': 'Days valid (default: 7)',
    },
    examples: [
      '"Create invite for john@example.com as worker" → email="john@example.com", role="worker"',
      '"Generate manager invite for sarah@farm.co" → email="sarah@farm.co", role="manager"',
    ],
  ),
  ToolDefinition(
    name: 'generateReport',
    description:
        'Generate and export farm reports in various formats (PDF, CSV, Excel, JSON)',
    requiredParams: ['reportType'],
    optionalParams: {
      'format': 'Export format: pdf, csv, excel, json (default: pdf)',
      'startDate': 'Start date for date-range reports (YYYY-MM-DD)',
      'endDate': 'End date for date-range reports (YYYY-MM-DD)',
      'daysBack': 'Days back from today (alternative to startDate/endDate)',
    },
    examples: [
      '"Generate inventory report" → reportType="inventory"',
      '"Export health records as PDF" → reportType="health", format="pdf"',
      '"Create financial report for last 30 days" → reportType="financial", daysBack=30',
      '"Export breeding data as CSV" → reportType="breeding", format="csv"',
      '"Generate growth/weight report" → reportType="growth"',
    ],
  ),
];

/// Generate the full tools context string for the assistant
String generateToolsContext() {
  final buffer = StringBuffer();
  buffer.writeln('=== AVAILABLE TOOLS ===');
  buffer.writeln(
    'Use render_farm with these tools. Each renders an interactive widget.',
  );
  buffer.writeln('');

  for (int i = 0; i < toolDefinitions.length; i++) {
    buffer.writeln('${i + 1}. ${toolDefinitions[i].toContextString()}');
  }

  buffer.writeln('');
  buffer.writeln('=== CRITICAL: TOOL CALL FORMAT ===');
  buffer.writeln('''
The component object MUST have the TOOL NAME as the key, with parameters as the value object.

CORRECT FORMAT (tool name is the key):
{
  "surfaceId": "healthRecord_maria_123",
  "components": [{
    "id": "comp_1",
    "component": {
      "showHealthRecord": {
        "animalTagId": "MARIA",
        "type": "Vaccination",
        "title": "Annual Booster",
        "date": "2026-02-22"
      }
    }
  }]
}

WRONG FORMAT (DO NOT DO THIS - tool parameters at wrong level):
{
  "component": {
    "animalTagId": "MARIA",  ← WRONG! Missing tool name wrapper
    "type": "Vaccination"
  }
}

The tool name (showHealthRecord, showAnimal, createReminder, etc.) MUST be the key inside "component".
''');
  buffer.writeln('=== END TOOLS ===');

  return buffer.toString();
}

final List<CatalogItem> farmTools = [
  CatalogItem(
    name: 'showAnimal',
    dataSchema: Schema.object(
      properties: {
        'name': Schema.string(description: 'Name of the animal'),
        'tagId': Schema.string(description: 'Tag ID of the animal'),
        'species': Schema.string(description: 'Species e.g. Cow, Goat'),
        'breed': Schema.string(description: 'Brief info about breed'),
        'status': Schema.string(
          description: 'current status: healthy, sick...',
        ),
      },
      required: ['tagId', 'species'],
    ),
    widgetBuilder: (context) {
      return GenUiAnimalCard(data: context.data as Map<String, dynamic>);
    },
  ),
  CatalogItem(
    name: 'showHealthRecord',
    dataSchema: Schema.object(
      properties: {
        'animalTagId': Schema.string(description: 'Tag ID of the animal'),
        'type': Schema.string(
          description:
              'Type of health record: Vaccination, Medication, Checkup, Treatment, Surgery, Observation',
        ),
        'title': Schema.string(description: 'Title of the health record'),
        'date': Schema.string(description: 'Date in YYYY-MM-DD format'),
        'status': Schema.string(
          description: 'Status: pending, inProgress, completed, cancelled',
        ),
        'severity': Schema.string(
          description: 'Severity level: low, medium, high, critical',
        ),
        'description': Schema.string(
          description: 'Description or notes about the health event',
        ),
        'diagnosis': Schema.string(description: 'Medical diagnosis if any'),
        'treatment': Schema.string(
          description: 'Treatment administered or recommended',
        ),
        'vaccineName': Schema.string(
          description: 'Name of vaccine if applicable',
        ),
        'medicationName': Schema.string(
          description: 'Name of medication if applicable',
        ),
        'dosage': Schema.string(description: 'Dosage of medication'),
        'nextDueDate': Schema.string(
          description: 'Next vaccination due date (YYYY-MM-DD)',
        ),
        'followUpDate': Schema.string(
          description: 'Follow-up appointment date (YYYY-MM-DD)',
        ),
        'withdrawalEndDate': Schema.string(
          description:
              'End of withdrawal period for meat/milk safety (YYYY-MM-DD)',
        ),
        'veterinarianName': Schema.string(
          description: 'Name of the veterinarian',
        ),
        'cost': Schema.number(description: 'Cost of the treatment/procedure'),
      },
      required: ['animalTagId', 'type', 'title'],
    ),
    widgetBuilder: (context) {
      return GenUiHealthCard(data: context.data as Map<String, dynamic>);
    },
  ),
  CatalogItem(
    name: 'logFeeding',
    dataSchema: Schema.object(
      properties: {
        'animalId': Schema.string(description: 'Tag ID of the animal'),
        'feedType': Schema.string(description: 'The feed type of the animal'),
        'quantity': Schema.number(description: 'The feed amount'),
        'date': Schema.string(),
      },
      required: ['animalId', 'feedType', 'quantity'],
    ),
    widgetBuilder: (context) {
      return GenUiFeedingForm(
        initialData: context.data as Map<String, dynamic>,
      );
    },
  ),
  CatalogItem(
    name: 'createReminder',
    dataSchema: Schema.object(
      properties: {
        'title': Schema.string(
          description: 'Title of the reminder, e.g. "Vaccinate pig 123"',
        ),
        'description': Schema.string(
          description: 'Optional detailed description of what needs to be done',
        ),
        'dueDate': Schema.string(
          description: 'Due date in ISO format (YYYY-MM-DD), e.g. "2026-02-15"',
        ),
        'daysFromNow': Schema.integer(
          description:
              'Alternative to dueDate: number of days from today. Use 1 for tomorrow, 7 for next week, etc.',
        ),
        'type': Schema.string(
          description:
              'Type of reminder: "breeding", "health", "weightCheck", or "custom"',
        ),
        'priority': Schema.string(
          description: 'Priority level: "low", "medium", "high", or "urgent"',
        ),
        'animalTagId': Schema.string(
          description:
              'Optional: Tag ID of the animal this reminder is related to',
        ),
      },
      required: ['title'],
    ),
    widgetBuilder: (context) {
      return GenUiReminderForm(
        initialData: context.data as Map<String, dynamic>,
      );
    },
  ),
  CatalogItem(
    name: 'createInviteCode',
    dataSchema: Schema.object(
      properties: {
        'email': Schema.string(
          description: 'Email address of the person to invite. Required field.',
        ),
        'role': Schema.string(
          description:
              'Role to assign: "owner", "manager", "worker", or "vet". Defaults to "worker" if not specified.',
        ),
        'maxUses': Schema.integer(
          description:
              'Maximum number of times this code can be used. Default is 1 (single use). Use higher values for team onboarding.',
        ),
        'validityDays': Schema.integer(
          description:
              'Number of days the code is valid. Default is 7 days. Use 1 for urgent invites, 30 for longer validity.',
        ),
      },
      required: ['email'],
    ),
    widgetBuilder: (context) {
      return GenUiInviteCodeForm(
        initialData: context.data as Map<String, dynamic>,
      );
    },
  ),
  CatalogItem(
    name: 'generateReport',
    dataSchema: Schema.object(
      properties: {
        'reportType': Schema.string(
          description:
              'Type of report: "inventory" (animals), "financial" (transactions), "health" (medical records), "breeding" (reproduction), or "growth" (weight tracking).',
        ),
        'format': Schema.string(
          description:
              'Export format: "pdf", "csv", "excel", or "json". Defaults to "pdf" if not specified.',
        ),
        'startDate': Schema.string(
          description:
              'Start date for reports with date ranges (YYYY-MM-DD). Used with financial, health, breeding, and growth reports.',
        ),
        'endDate': Schema.string(
          description:
              'End date for reports with date ranges (YYYY-MM-DD). Defaults to today if not specified.',
        ),
        'daysBack': Schema.integer(
          description:
              'Alternative to startDate: number of days back from today. Use 7 for last week, 30 for last month, 90 for last quarter.',
        ),
      },
      required: ['reportType'],
    ),
    widgetBuilder: (context) {
      return GenUiReportForm(initialData: context.data as Map<String, dynamic>);
    },
  ),
];
