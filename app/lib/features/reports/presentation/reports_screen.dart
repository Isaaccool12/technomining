import 'package:engineer/features/library/presentation/common_views.dart';
import 'package:engineer/features/reports/application/report_print.dart';
import 'package:engineer/features/reports/application/report_providers.dart';
import 'package:engineer/features/reports/domain/report_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route of a report.
String reportLocation(String id) => '/report/${Uri.encodeComponent(id)}';

/// List of reports.
class ReportsScreen extends ConsumerWidget {
  /// Creates the screen.
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Отчёты')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/reports/new'),
        icon: const Icon(Icons.add),
        label: const Text('Новый отчёт'),
      ),
      body: ref
          .watch(reportsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) =>
                ErrorRetryView(onRetry: () => ref.invalidate(reportsProvider)),
            data: (reports) => reports.isEmpty
                ? const MessageView(
                    icon: Icons.assignment,
                    title: 'Отчётов пока нет',
                    hint:
                        'Нажмите «Новый отчёт». Допуски подставляются из '
                        'импортированных инструкций.',
                  )
                : ListView.separated(
                    padding: const EdgeInsetsDirectional.only(bottom: 96),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _ReportTile(summary: reports[index]),
                  ),
          ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final h = summary.header;
    final details = [
      h.status.label,
      formatDate(h.updatedAtUtcMs),
      if (h.machine.isNotEmpty) h.machine,
      if (h.customer.isNotEmpty) h.customer,
      if (summary.measured > 0) 'замеров: ${summary.measured}',
      if (summary.outside > 0) '✕ вне допуска: ${summary.outside}',
    ];
    return ListTile(
      minTileHeight: 76,
      leading: Icon(_icon(h.status), size: 34),
      title: Text(h.title),
      subtitle: Text(details.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(reportLocation(h.id)),
    );
  }

  IconData _icon(ReportStatus status) => switch (status) {
    ReportStatus.draft => Icons.edit_note,
    ReportStatus.review => Icons.hourglass_top,
    ReportStatus.approved => Icons.verified,
  };
}
