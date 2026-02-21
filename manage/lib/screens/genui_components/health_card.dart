import 'package:flutter/material.dart';

class GenUiHealthCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const GenUiHealthCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final animalTagId = data['animalTagId'] as String? ?? 'Unknown';
    final type = data['type'] as String? ?? 'Health Record';
    final title = data['title'] as String? ?? 'Health Record';
    final date = data['date'] as String?;
    final status = data['status'] as String? ?? 'completed';
    final severity = data['severity'] as String?;
    final description = data['description'] as String?;
    final diagnosis = data['diagnosis'] as String?;
    final treatment = data['treatment'] as String?;
    final vaccineName = data['vaccineName'] as String?;
    final medicationName = data['medicationName'] as String?;
    final dosage = data['dosage'] as String?;
    final nextDueDate = data['nextDueDate'] as String?;
    final followUpDate = data['followUpDate'] as String?;
    final withdrawalEndDate = data['withdrawalEndDate'] as String?;
    final veterinarianName = data['veterinarianName'] as String?;
    final cost = data['cost'];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row with type icon and status
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getTypeColor(type).withValues(alpha: 0.2),
                  child: Icon(
                    _getTypeIcon(type),
                    color: _getTypeColor(type),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Animal: $animalTagId',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Chip(
                      label: Text(type),
                      backgroundColor: _getTypeColor(
                        type,
                      ).withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: _getTypeColor(type),
                        fontSize: 12,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    if (severity != null)
                      Chip(
                        label: Text(severity),
                        backgroundColor: _getSeverityColor(
                          severity,
                        ).withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: _getSeverityColor(severity),
                          fontSize: 11,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Date and status row
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  date ?? 'No date',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Vaccination info
            if (vaccineName != null) ...[
              _buildInfoRow(context, Icons.vaccines, 'Vaccine', vaccineName),
              const SizedBox(height: 4),
            ],

            // Medication info
            if (medicationName != null) ...[
              _buildInfoRow(
                context,
                Icons.medication,
                'Medication',
                medicationName,
              ),
              if (dosage != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 2),
                  child: Text(
                    'Dosage: $dosage',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ),
              const SizedBox(height: 4),
            ],

            // Description
            if (description != null && description.isNotEmpty) ...[
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],

            // Diagnosis
            if (diagnosis != null && diagnosis.isNotEmpty) ...[
              _buildInfoRow(
                context,
                Icons.medical_information,
                'Diagnosis',
                diagnosis,
              ),
              const SizedBox(height: 4),
            ],

            // Treatment
            if (treatment != null && treatment.isNotEmpty) ...[
              _buildInfoRow(context, Icons.healing, 'Treatment', treatment),
              const SizedBox(height: 4),
            ],

            // Follow-up date
            if (followUpDate != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      'Follow-up: $followUpDate',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Next vaccination due date
            if (nextDueDate != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vaccines, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Next due: $nextDueDate',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Withdrawal period
            if (withdrawalEndDate != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(
                      'Withdrawal until: $withdrawalEndDate',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Veterinarian and cost
            if (veterinarianName != null || cost != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (veterinarianName != null)
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Vet: $veterinarianName',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  if (cost != null)
                    Text(
                      'Cost: \$${cost.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'vaccination':
        return Colors.blue;
      case 'medication':
        return Colors.purple;
      case 'checkup':
        return Colors.teal;
      case 'treatment':
        return Colors.orange;
      case 'surgery':
        return Colors.red;
      case 'observation':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'vaccination':
        return Icons.vaccines;
      case 'medication':
        return Icons.medication;
      case 'checkup':
        return Icons.medical_services;
      case 'treatment':
        return Icons.healing;
      case 'surgery':
        return Icons.local_hospital;
      case 'observation':
        return Icons.visibility;
      default:
        return Icons.health_and_safety;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'inprogress':
      case 'in_progress':
        return Colors.blue;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
