import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/financial_repository.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/seo_helper.dart';
import 'add_transaction_dialog.dart';
import 'budget_screen.dart';
import 'currency_settings_dialog.dart';
import 'financial_reports_screen.dart';

class FinancialScreen extends ConsumerStatefulWidget {
  const FinancialScreen({super.key});

  @override
  ConsumerState<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends ConsumerState<FinancialScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    SeoHelper.configureFinancialPage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(financialSummaryProvider);
    final now = DateTime.now();
    final budgetComparisonAsync = ref.watch(
      monthBudgetWithComparisonProvider((now.year, now.month)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            tooltip: 'Budget Planning',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const BudgetScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.currency_exchange),
            tooltip: 'Currency Settings',
            onPressed: () => _showCurrencySettings(context),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Reports',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FinancialReportsScreen(),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Income'),
            Tab(text: 'Expenses'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Summary Card
          summaryAsync.when(
            data: (summary) => summary != null
                ? _buildSummaryCard(summary, budgetComparisonAsync)
                : const SizedBox(),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const SizedBox(),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildIncomeTab(),
                _buildExpensesTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTransactionDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
      ),
    );
  }

  void _showCurrencySettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CurrencySettingsDialog(),
    );
  }

  Widget _buildSummaryCard(
    FinancialSummary summary,
    AsyncValue<BudgetComparison?> budgetComparisonAsync,
  ) {
    final formatter = ref.watch(currencyFormatterProvider);
    final now = DateTime.now();

    return ResponsiveLayout(
      maxWidth: 1200,
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: 'Income',
                    value: formatter.format(summary.totalIncome),
                    color: Colors.green,
                    icon: Icons.arrow_upward,
                  ),
                  _SummaryItem(
                    label: 'Expenses',
                    value: formatter.format(summary.totalExpenses),
                    color: Colors.red,
                    icon: Icons.arrow_downward,
                  ),
                  _SummaryItem(
                    label: 'Net Profit',
                    value: formatter.format(summary.netProfit),
                    color: summary.isProfitable ? Colors.green : Colors.red,
                    icon: summary.isProfitable
                        ? Icons.trending_up
                        : Icons.trending_down,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: summary.totalIncome > 0
                    ? (summary.totalExpenses / summary.totalIncome).clamp(
                        0.0,
                        1.0,
                      )
                    : 0,
                backgroundColor: Colors.green.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  summary.isProfitable ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Profit Margin: ${summary.profitMargin.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: summary.isProfitable ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Budget status for current month
              budgetComparisonAsync.when(
                data: (comparison) {
                  if (comparison == null || comparison.budget == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BudgetScreen(),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'No budget set for ${DateFormat('MMMM').format(now)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '• Set Budget',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const BudgetScreen(),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            comparison.isOverBudget
                                ? Icons.warning
                                : Icons.check_circle,
                            size: 16,
                            color: comparison.isOverBudget
                                ? Colors.red
                                : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${DateFormat('MMMM').format(now)} Budget: ${comparison.usagePercentage.toStringAsFixed(0)}% used',
                            style: TextStyle(
                              color: comparison.isOverBudget
                                  ? Colors.red
                                  : Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${formatter.format(comparison.remaining)} ${comparison.isOverBudget ? "over" : "left"})',
                            style: TextStyle(
                              color: comparison.isOverBudget
                                  ? Colors.red[400]
                                  : Colors.green[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox(),
                error: (_, _) => const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final transactionsAsync = ref.watch(transactionsProvider);

    return transactionsAsync.when(
      data: (transactions) => transactions.isEmpty
          ? _buildEmptyState(
              'No transactions yet',
              'Start tracking your finances',
            )
          : _buildTransactionList(transactions),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildTransactionList(List<Transaction> transactions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > Breakpoints.tablet;

        if (isWide) {
          return ResponsiveBody(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth > Breakpoints.desktop
                    ? 3
                    : 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.8,
              ),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                return _TransactionCard(
                  transaction: transaction,
                  onTap: () => _showTransactionDetail(context, transaction),
                );
              },
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            return _TransactionCard(
              transaction: transaction,
              onTap: () => _showTransactionDetail(context, transaction),
            );
          },
        );
      },
    );
  }

  Widget _buildIncomeTab() {
    final incomeAsync = ref.watch(incomeTransactionsProvider);

    return incomeAsync.when(
      data: (transactions) => transactions.isEmpty
          ? _buildEmptyState('No income recorded', 'Record sales and services')
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                return _TransactionCard(
                  transaction: transaction,
                  onTap: () => _showTransactionDetail(context, transaction),
                );
              },
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildExpensesTab() {
    final expensesAsync = ref.watch(expenseTransactionsProvider);

    return expensesAsync.when(
      data: (transactions) => transactions.isEmpty
          ? _buildEmptyState('No expenses recorded', 'Track your farm expenses')
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final transaction = transactions[index];
                return _TransactionCard(
                  transaction: transaction,
                  onTap: () => _showTransactionDetail(context, transaction),
                );
              },
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddTransactionDialog(),
    );
  }

  void _showTransactionDetail(BuildContext context, Transaction transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) =>
            _TransactionDetailSheet(transaction: transaction),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }
}

class _TransactionCard extends ConsumerWidget {
  final Transaction transaction;
  final VoidCallback? onTap;

  const _TransactionCard({required this.transaction, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final formatter = ref.watch(currencyFormatterProvider);
    final isIncome = transaction.isIncome;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isIncome ? Colors.green : Colors.red).withValues(
            alpha: 0.2,
          ),
          child: Icon(
            isIncome ? Icons.arrow_upward : Icons.arrow_downward,
            color: isIncome ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(transaction.categoryDisplayName),
            Text(
              dateFormat.format(transaction.date),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Text(
          formatter.format(transaction.amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isIncome ? Colors.green : Colors.red,
          ),
        ),
        onTap: onTap,
        isThreeLine: true,
      ),
    );
  }
}

class _TransactionDetailSheet extends ConsumerStatefulWidget {
  final Transaction transaction;

  const _TransactionDetailSheet({required this.transaction});

  @override
  ConsumerState<_TransactionDetailSheet> createState() =>
      _TransactionDetailSheetState();
}

class _TransactionDetailSheetState
    extends ConsumerState<_TransactionDetailSheet> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final dateFormat = DateFormat('MMM d, yyyy');
    final formatter = ref.watch(currencyFormatterProvider);
    final isIncome = transaction.isIncome;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: (isIncome ? Colors.green : Colors.red)
                      .withValues(alpha: 0.2),
                  child: Icon(
                    isIncome ? Icons.arrow_upward : Icons.arrow_downward,
                    color: isIncome ? Colors.green : Colors.red,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.description,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        transaction.categoryDisplayName,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Amount
            Center(
              child: Text(
                formatter.format(transaction.amount),
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: isIncome ? Colors.green : Colors.red,
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (isIncome ? Colors.green : Colors.red).withValues(
                    alpha: 0.2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  isIncome ? 'INCOME' : 'EXPENSE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isIncome ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Details
            _buildDetailRow('Date', dateFormat.format(transaction.date)),
            _buildDetailRow('Category', transaction.categoryDisplayName),
            if (transaction.paymentMethod != null)
              _buildDetailRow(
                'Payment Method',
                _formatPaymentMethod(transaction.paymentMethod!),
              ),
            if (transaction.referenceNumber != null)
              _buildDetailRow('Reference #', transaction.referenceNumber!),
            if (transaction.animalId != null)
              _buildDetailRow('Animal ID', transaction.animalId!),
            if (transaction.notes != null)
              _buildDetailRow('Notes', transaction.notes!),

            const SizedBox(height: 24),

            // Delete Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDeleting ? null : () => _deleteTransaction(),
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete),
                label: const Text('Delete Transaction'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPaymentMethod(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.mobileMoney:
        return 'Mobile Money';
      case PaymentMethod.cheque:
        return 'Cheque';
      case PaymentMethod.credit:
        return 'Credit';
      case PaymentMethod.other:
        return 'Other';
    }
  }

  Future<void> _deleteTransaction() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text(
          'Are you sure you want to delete this transaction?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isDeleting = true);

    try {
      final repository = ref.read(financialRepositoryProvider);
      await repository.deleteTransaction(widget.transaction.id);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Transaction deleted'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        setState(() => _isDeleting = false);
      }
    }
  }
}
