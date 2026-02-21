import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/models.dart';
import '../../providers/auth_providers.dart';
import '../../providers/providers.dart';
import '../../utils/currency_utils.dart';
import '../../utils/export_service.dart';

/// Report type enum for GenUI
enum GenUiReportType { inventory, financial, health, breeding, growth }

/// Export format enum for GenUI
enum GenUiExportFormat { pdf, csv, excel, json }

/// A GenUI component for generating reports via the AI assistant
class GenUiReportForm extends ConsumerStatefulWidget {
  final Map<String, dynamic> initialData;

  const GenUiReportForm({super.key, required this.initialData});

  @override
  ConsumerState<GenUiReportForm> createState() => _GenUiReportFormState();
}

class _GenUiReportFormState extends ConsumerState<GenUiReportForm> {
  late GenUiReportType _selectedReportType;
  late GenUiExportFormat _selectedFormat;
  late DateTimeRange _dateRange;
  bool _isGenerating = false;
  bool _isGenerated = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    // Parse report type from AI
    final reportTypeStr = widget.initialData['reportType'] as String?;
    _selectedReportType = _parseReportType(reportTypeStr);

    // Parse format
    final formatStr = widget.initialData['format'] as String?;
    _selectedFormat = _parseFormat(formatStr);

    // Parse date range
    final startDateStr = widget.initialData['startDate'] as String?;
    final endDateStr = widget.initialData['endDate'] as String?;
    final daysBack = widget.initialData['daysBack'] as int?;

    debugPrint(
      'Report form received: startDate=$startDateStr, endDate=$endDateStr, daysBack=$daysBack',
    );

    DateTime startDate;
    DateTime endDate = DateTime.now();
    final now = DateTime.now();

    if (startDateStr != null) {
      var parsed = DateTime.tryParse(startDateStr);
      // If AI sends a date from a past year (e.g., 2024 when we're in 2026),
      // assume they meant the current year
      if (parsed != null && parsed.year < now.year - 1) {
        debugPrint('Correcting old year ${parsed.year} to ${now.year}');
        parsed = DateTime(now.year, parsed.month, parsed.day);
      }
      startDate = parsed ?? now.subtract(const Duration(days: 30));
    } else if (daysBack != null) {
      startDate = now.subtract(Duration(days: daysBack));
    } else {
      startDate = now.subtract(const Duration(days: 30));
    }

    if (endDateStr != null) {
      var parsed = DateTime.tryParse(endDateStr);
      // Same year correction for end date
      if (parsed != null && parsed.year < now.year - 1) {
        debugPrint('Correcting old year ${parsed.year} to ${now.year}');
        parsed = DateTime(now.year, parsed.month, parsed.day);
      }
      endDate = parsed ?? now;
    }

    // Ensure end date is not in the future
    if (endDate.isAfter(now)) {
      endDate = now;
    }

    // Ensure start is before end
    if (startDate.isAfter(endDate)) {
      startDate = endDate.subtract(const Duration(days: 30));
    }

    debugPrint('Report date range: $startDate to $endDate');
    _dateRange = DateTimeRange(start: startDate, end: endDate);
  }

  GenUiReportType _parseReportType(String? typeStr) {
    if (typeStr == null) return GenUiReportType.inventory;
    switch (typeStr.toLowerCase()) {
      case 'inventory':
      case 'animal':
      case 'animals':
        return GenUiReportType.inventory;
      case 'financial':
      case 'finance':
      case 'money':
      case 'transactions':
        return GenUiReportType.financial;
      case 'health':
      case 'medical':
      case 'vaccination':
      case 'vaccinations':
        return GenUiReportType.health;
      case 'breeding':
      case 'reproduction':
        return GenUiReportType.breeding;
      case 'growth':
      case 'weight':
      case 'weights':
        return GenUiReportType.growth;
      default:
        return GenUiReportType.inventory;
    }
  }

  GenUiExportFormat _parseFormat(String? formatStr) {
    if (formatStr == null) return GenUiExportFormat.pdf;
    switch (formatStr.toLowerCase()) {
      case 'pdf':
        return GenUiExportFormat.pdf;
      case 'csv':
        return GenUiExportFormat.csv;
      case 'excel':
      case 'xlsx':
        return GenUiExportFormat.excel;
      case 'json':
        return GenUiExportFormat.json;
      default:
        return GenUiExportFormat.pdf;
    }
  }

  String _getReportTypeDisplayName(GenUiReportType type) {
    switch (type) {
      case GenUiReportType.inventory:
        return 'Animal Inventory';
      case GenUiReportType.financial:
        return 'Financial';
      case GenUiReportType.health:
        return 'Health Records';
      case GenUiReportType.breeding:
        return 'Breeding';
      case GenUiReportType.growth:
        return 'Growth/Weight';
    }
  }

  String _getFormatDisplayName(GenUiExportFormat format) {
    switch (format) {
      case GenUiExportFormat.pdf:
        return 'PDF';
      case GenUiExportFormat.csv:
        return 'CSV';
      case GenUiExportFormat.excel:
        return 'Excel';
      case GenUiExportFormat.json:
        return 'JSON';
    }
  }

  IconData _getReportIcon(GenUiReportType type) {
    switch (type) {
      case GenUiReportType.inventory:
        return Icons.pets;
      case GenUiReportType.financial:
        return Icons.attach_money;
      case GenUiReportType.health:
        return Icons.local_hospital;
      case GenUiReportType.breeding:
        return Icons.favorite;
      case GenUiReportType.growth:
        return Icons.trending_up;
    }
  }

  IconData _getFormatIcon(GenUiExportFormat format) {
    switch (format) {
      case GenUiExportFormat.pdf:
        return Icons.picture_as_pdf;
      case GenUiExportFormat.csv:
        return Icons.table_chart;
      case GenUiExportFormat.excel:
        return Icons.grid_on;
      case GenUiExportFormat.json:
        return Icons.code;
    }
  }

  Future<void> _generateReport() async {
    final farmId = ref.read(activeFarmIdProvider);
    if (farmId == null) {
      setState(() {
        _errorText = 'No farm selected';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorText = null;
    });

    try {
      // Wait for farm settings to load to get correct currency
      final farmSettings = ref.read(farmSettingsProvider);
      await farmSettings.when(
        data: (_) async {},
        loading: () async {
          // Wait a bit for settings to load
          await Future.delayed(const Duration(milliseconds: 500));
        },
        error: (_, _) async {},
      );

      final currencyFormatter = ref.read(currencyFormatterProvider);
      debugPrint('Report using currency: ${currencyFormatter.config.code}');

      final userAsync = ref.read(currentUserProvider);
      final farmName = userAsync.value?.activeFarm?.farmName ?? 'Farm';

      final exportService = ExportService(
        currencyFormatter: currencyFormatter,
        farmName: farmName,
      );

      switch (_selectedReportType) {
        case GenUiReportType.inventory:
          await _generateInventoryReport(exportService);
          break;
        case GenUiReportType.financial:
          await _generateFinancialReport(exportService);
          break;
        case GenUiReportType.health:
          await _generateHealthReport(exportService);
          break;
        case GenUiReportType.breeding:
          await _generateBreedingReport(exportService);
          break;
        case GenUiReportType.growth:
          await _generateGrowthReport(exportService);
          break;
      }

      setState(() {
        _isGenerated = true;
      });
    } catch (e) {
      setState(() {
        _errorText = 'Failed to generate report: $e';
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _generateInventoryReport(ExportService exportService) async {
    final animalsAsync = ref.read(animalsProvider);
    final animals = animalsAsync.value ?? [];

    if (animals.isEmpty) {
      throw Exception('No animals found');
    }

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());

    switch (_selectedFormat) {
      case GenUiExportFormat.pdf:
        final pdfBytes = await exportService.generateInventoryPdf(animals);
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'inventory_report_$dateStr.pdf',
        );
        break;
      case GenUiExportFormat.csv:
        final csv = exportService.generateInventoryCsv(animals);
        await exportService.shareCsv(csv, 'inventory_report_$dateStr.csv');
        break;
      case GenUiExportFormat.excel:
        final excelBytes = exportService.generateInventoryExcel(animals);
        await exportService.shareExcel(
          excelBytes,
          'inventory_report_$dateStr.xlsx',
        );
        break;
      case GenUiExportFormat.json:
        final json = exportService.generateInventoryJson(animals);
        await exportService.shareJson(json, 'inventory_report_$dateStr.json');
        break;
    }
  }

  Future<void> _generateFinancialReport(ExportService exportService) async {
    final farmId = ref.read(activeFarmIdProvider)!;
    final repository = ref.read(financialRepositoryProvider);
    final formatter = ref.read(currencyFormatterProvider);
    final userAsync = ref.read(currentUserProvider);
    final farmName = userAsync.value?.activeFarm?.farmName ?? 'Farm';

    final summary = await repository.getFinancialSummary(
      farmId,
      startDate: _dateRange.start,
      endDate: _dateRange.end,
    );

    final transactions = await repository.getTransactions(farmId);
    final filteredTransactions = transactions.where((t) {
      return t.date.isAfter(
            _dateRange.start.subtract(const Duration(days: 1)),
          ) &&
          t.date.isBefore(_dateRange.end.add(const Duration(days: 1)));
    }).toList();

    // Get top expenses for chart
    final topExpenses = await repository.getTopExpenseCategories(
      farmId,
      startDate: _dateRange.start,
      endDate: _dateRange.end,
      limit: 8,
    );

    // Get monthly summaries for trend chart
    final monthlySummaries = await repository.getMonthlySummaries(
      farmId,
      DateTime.now().year,
    );

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());

    switch (_selectedFormat) {
      case GenUiExportFormat.pdf:
        // Generate detailed PDF with charts
        final pdfBytes = await _generateDetailedFinancialPdf(
          summary: summary,
          topExpenses: topExpenses,
          monthlySummaries: monthlySummaries,
          formatter: formatter,
          farmName: farmName,
        );
        await Printing.sharePdf(
          bytes: Uint8List.fromList(pdfBytes),
          filename: 'financial_report_$dateStr.pdf',
        );
        break;
      case GenUiExportFormat.csv:
        final csv = exportService.generateFinancialCsv(filteredTransactions);
        await exportService.shareCsv(csv, 'financial_report_$dateStr.csv');
        break;
      case GenUiExportFormat.excel:
        final excelBytes = exportService.generateFinancialExcel(
          filteredTransactions,
        );
        await exportService.shareExcel(
          excelBytes,
          'financial_report_$dateStr.xlsx',
        );
        break;
      case GenUiExportFormat.json:
        final json = exportService.generateFinancialJson(
          summary: summary,
          transactions: filteredTransactions,
          startDate: _dateRange.start,
          endDate: _dateRange.end,
        );
        await exportService.shareJson(json, 'financial_report_$dateStr.json');
        break;
    }
  }

  // ==================== DETAILED FINANCIAL PDF ====================

  Future<List<int>> _generateDetailedFinancialPdf({
    required FinancialSummary summary,
    required Map<String, double> topExpenses,
    required List<FinancialSummary> monthlySummaries,
    required CurrencyFormatter formatter,
    required String farmName,
  }) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('MMM d, yyyy');

    // Colors for charts
    final chartColors = [
      PdfColors.blue,
      PdfColors.green,
      PdfColors.orange,
      PdfColors.purple,
      PdfColors.red,
      PdfColors.teal,
      PdfColors.amber,
      PdfColors.indigo,
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildPdfHeader(farmName, 'Financial Report'),
        footer: (context) => _buildPdfFooter(context),
        build: (context) => [
          // Period
          pw.Text(
            'Period: ${dateFormat.format(_dateRange.start)} - ${dateFormat.format(_dateRange.end)}',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 20),

          // Executive Summary Box
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.blue200),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Executive Summary',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryBox(
                      'Total Income',
                      formatter.format(summary.totalIncome),
                      PdfColors.green,
                    ),
                    _buildSummaryBox(
                      'Total Expenses',
                      formatter.format(summary.totalExpenses),
                      PdfColors.red,
                    ),
                    _buildSummaryBox(
                      'Net Profit',
                      formatter.format(summary.netProfit),
                      summary.netProfit >= 0 ? PdfColors.green : PdfColors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Profit Margin Indicator
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: summary.netProfit >= 0
                  ? PdfColors.green50
                  : PdfColors.red50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Profit Margin',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  summary.totalIncome > 0
                      ? '${(summary.netProfit / summary.totalIncome * 100).toStringAsFixed(1)}%'
                      : '0%',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: summary.netProfit >= 0
                        ? PdfColors.green700
                        : PdfColors.red700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Expense Categories Chart
          if (topExpenses.isNotEmpty) ...[
            pw.Text(
              'Expense Breakdown',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            _buildExpenseChart(topExpenses, formatter, chartColors),
            pw.SizedBox(height: 24),
          ],

          // Monthly Trend Chart
          if (monthlySummaries.isNotEmpty) ...[
            pw.Text(
              'Monthly Trend',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            _buildMonthlyChart(monthlySummaries, formatter),
            pw.SizedBox(height: 24),
          ],

          // Monthly Summary Table
          if (monthlySummaries.isNotEmpty) ...[
            pw.Text(
              'Monthly Breakdown',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            _buildMonthlyTable(monthlySummaries, formatter),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfHeader(String farmName, String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            farmName,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
          ),
          pw.Divider(color: PdfColors.grey300),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter(pw.Context context) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated: ${dateFormat.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 2),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildExpenseChart(
    Map<String, double> categories,
    CurrencyFormatter formatter,
    List<PdfColor> colors,
  ) {
    final total = categories.values.fold(0.0, (sum, v) => sum + v);
    final sortedEntries = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: sortedEntries.asMap().entries.map((entry) {
          final index = entry.key;
          final category = entry.value.key;
          final amount = entry.value.value;
          final percentage = total > 0 ? (amount / total * 100) : 0.0;
          final color = colors[index % colors.length];

          return pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 12,
                  height: 12,
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    _formatCategoryName(category),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Stack(
                    children: [
                      pw.Container(
                        height: 10,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                      ),
                      pw.Container(
                        height: 10,
                        width: percentage * 1.5,
                        decoration: pw.BoxDecoration(
                          color: color,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.SizedBox(
                  width: 80,
                  child: pw.Text(
                    formatter.formatCompact(amount),
                    style: const pw.TextStyle(fontSize: 9),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.SizedBox(
                  width: 35,
                  child: pw.Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  pw.Widget _buildMonthlyChart(
    List<FinancialSummary> summaries,
    CurrencyFormatter formatter,
  ) {
    final monthNames = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];

    final maxValue = summaries.fold(0.0, (max, s) {
      final m = [
        s.totalIncome,
        s.totalExpenses,
      ].reduce((a, b) => a > b ? a : b);
      return m > max ? m : max;
    });

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          // Legend
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Container(width: 12, height: 12, color: PdfColors.green),
              pw.SizedBox(width: 4),
              pw.Text('Income', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(width: 16),
              pw.Container(width: 12, height: 12, color: PdfColors.red),
              pw.SizedBox(width: 4),
              pw.Text('Expenses', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.SizedBox(height: 12),
          // Bar chart
          pw.SizedBox(
            height: 100,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: summaries.asMap().entries.map((entry) {
                final index = entry.key;
                final summary = entry.value;
                final incomeHeight = maxValue > 0
                    ? (summary.totalIncome / maxValue * 80)
                    : 0.0;
                final expenseHeight = maxValue > 0
                    ? (summary.totalExpenses / maxValue * 80)
                    : 0.0;

                return pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Container(
                              width: 6,
                              height: incomeHeight,
                              color: PdfColors.green,
                            ),
                            pw.SizedBox(width: 1),
                            pw.Container(
                              width: 6,
                              height: expenseHeight,
                              color: PdfColors.red,
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          monthNames[index],
                          style: const pw.TextStyle(
                            fontSize: 7,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMonthlyTable(
    List<FinancialSummary> summaries,
    CurrencyFormatter formatter,
  ) {
    final monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final monthsWithData = summaries
        .where((s) => s.transactionCount > 0)
        .toList();

    if (monthsWithData.isEmpty) {
      return pw.Container();
    }

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellPadding: const pw.EdgeInsets.all(6),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
      },
      headers: ['Month', 'Income', 'Expenses', 'Profit'],
      data: monthsWithData.map((s) {
        final index = summaries.indexOf(s);
        return [
          monthNames[index],
          formatter.formatCompact(s.totalIncome),
          formatter.formatCompact(s.totalExpenses),
          formatter.formatCompact(s.netProfit),
        ];
      }).toList(),
    );
  }

  String _formatCategoryName(String category) {
    // Convert snake_case to Title Case
    return category
        .split('_')
        .map(
          (word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '',
        )
        .join(' ');
  }

  Future<void> _generateHealthReport(ExportService exportService) async {
    final healthRecordsAsync = ref.read(healthRecordsProvider);
    final healthRecords = healthRecordsAsync.value ?? [];

    final filteredRecords = healthRecords.where((r) {
      return r.date.isAfter(
            _dateRange.start.subtract(const Duration(days: 1)),
          ) &&
          r.date.isBefore(_dateRange.end.add(const Duration(days: 1)));
    }).toList();

    if (filteredRecords.isEmpty) {
      throw Exception('No health records found for the selected date range');
    }

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());

    switch (_selectedFormat) {
      case GenUiExportFormat.pdf:
        final pdfBytes = await exportService.generateHealthPdf(filteredRecords);
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'health_report_$dateStr.pdf',
        );
        break;
      case GenUiExportFormat.csv:
        final csv = exportService.generateHealthCsv(filteredRecords);
        await exportService.shareCsv(csv, 'health_report_$dateStr.csv');
        break;
      case GenUiExportFormat.excel:
        final excelBytes = exportService.generateHealthExcel(filteredRecords);
        await exportService.shareExcel(
          excelBytes,
          'health_report_$dateStr.xlsx',
        );
        break;
      case GenUiExportFormat.json:
        final json = exportService.generateHealthJson(filteredRecords);
        await exportService.shareJson(json, 'health_report_$dateStr.json');
        break;
    }
  }

  Future<void> _generateBreedingReport(ExportService exportService) async {
    final breedingRecordsAsync = ref.read(breedingRecordsProvider);
    final breedingRecords = breedingRecordsAsync.value ?? [];

    final filteredRecords = breedingRecords.where((r) {
      return r.heatDate.isAfter(
            _dateRange.start.subtract(const Duration(days: 1)),
          ) &&
          r.heatDate.isBefore(_dateRange.end.add(const Duration(days: 1)));
    }).toList();

    if (filteredRecords.isEmpty) {
      throw Exception('No breeding records found for the selected date range');
    }

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());

    switch (_selectedFormat) {
      case GenUiExportFormat.pdf:
        final pdfBytes = await exportService.generateBreedingPdf(
          filteredRecords,
        );
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'breeding_report_$dateStr.pdf',
        );
        break;
      case GenUiExportFormat.csv:
        final csv = exportService.generateBreedingCsv(filteredRecords);
        await exportService.shareCsv(csv, 'breeding_report_$dateStr.csv');
        break;
      case GenUiExportFormat.excel:
        final excelBytes = exportService.generateBreedingExcel(filteredRecords);
        await exportService.shareExcel(
          excelBytes,
          'breeding_report_$dateStr.xlsx',
        );
        break;
      case GenUiExportFormat.json:
        final json = exportService.generateBreedingJson(filteredRecords);
        await exportService.shareJson(json, 'breeding_report_$dateStr.json');
        break;
    }
  }

  Future<void> _generateGrowthReport(ExportService exportService) async {
    final animalsAsync = ref.read(animalsProvider);
    final animals = animalsAsync.value ?? [];
    final weightRepo = ref.read(weightRepositoryProvider);

    // Fetch weight records for all animals
    final Map<String, List<WeightRecord>> weightsByAnimal = {};
    for (final animal in animals) {
      final weights = await weightRepo.getWeightHistoryForAnimal(animal.id);
      final filteredWeights = weights.where((w) {
        return w.date.isAfter(
              _dateRange.start.subtract(const Duration(days: 1)),
            ) &&
            w.date.isBefore(_dateRange.end.add(const Duration(days: 1)));
      }).toList();
      if (filteredWeights.isNotEmpty) {
        weightsByAnimal[animal.id] = filteredWeights;
      }
    }

    if (weightsByAnimal.isEmpty) {
      throw Exception('No weight records found for the selected date range');
    }

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());

    switch (_selectedFormat) {
      case GenUiExportFormat.pdf:
        final pdfBytes = await exportService.generateGrowthPdf(
          animals,
          weightsByAnimal,
        );
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'growth_report_$dateStr.pdf',
        );
        break;
      case GenUiExportFormat.csv:
        final csv = exportService.generateGrowthCsv(animals, weightsByAnimal);
        await exportService.shareCsv(csv, 'growth_report_$dateStr.csv');
        break;
      case GenUiExportFormat.excel:
        final excelBytes = exportService.generateGrowthExcel(
          animals,
          weightsByAnimal,
        );
        await exportService.shareExcel(
          excelBytes,
          'growth_report_$dateStr.xlsx',
        );
        break;
      case GenUiExportFormat.json:
        final json = exportService.generateGrowthJson(animals, weightsByAnimal);
        await exportService.shareJson(json, 'growth_report_$dateStr.json');
        break;
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGenerated) {
      return _buildSuccessState();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.assessment,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Generate Report',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Export farm data as ${_getFormatDisplayName(_selectedFormat)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),

              // Report Type Selector
              Text(
                'Report Type',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GenUiReportType.values.map((type) {
                  final isSelected = _selectedReportType == type;
                  return ChoiceChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getReportIcon(type),
                          size: 16,
                          color: isSelected ? Colors.white : null,
                        ),
                        const SizedBox(width: 4),
                        Text(_getReportTypeDisplayName(type)),
                      ],
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedReportType = type);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Format Selector
              Text(
                'Export Format',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GenUiExportFormat.values.map((format) {
                  final isSelected = _selectedFormat == format;
                  return ChoiceChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getFormatIcon(format),
                          size: 16,
                          color: isSelected ? Colors.white : null,
                        ),
                        const SizedBox(width: 4),
                        Text(_getFormatDisplayName(format)),
                      ],
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedFormat = format);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Date Range (for non-inventory reports)
              if (_selectedReportType != GenUiReportType.inventory) ...[
                Text(
                  'Date Range',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _selectDateRange,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          '${DateFormat('MMM d, y').format(_dateRange.start)} - ${DateFormat('MMM d, y').format(_dateRange.end)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Error message
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Generate button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isGenerating ? null : _generateReport,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isGenerating ? 'Generating...' : 'Generate & Download',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: Colors.green.shade100,
              radius: 32,
              child: Icon(
                Icons.check_circle,
                color: Colors.green.shade700,
                size: 40,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Report Generated!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_getReportTypeDisplayName(_selectedReportType)} report exported as ${_getFormatDisplayName(_selectedFormat)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.green.shade700),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _isGenerated = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Generate Another'),
            ),
          ],
        ),
      ),
    );
  }
}
