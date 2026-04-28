import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/features/admin/providers/dashboard_provider.dart';
import 'package:provider/provider.dart';

// Re-export panels from their dedicated files.
export 'package:frontend/features/admin/widgets/incident_control_panel.dart'
    show IncidentControlPanel;
export 'package:frontend/features/admin/widgets/staff_management_panel.dart'
    show StaffCoordinationPanel;

class HotelStatusView extends StatefulWidget {
  const HotelStatusView({super.key});

  @override
  State<HotelStatusView> createState() => _HotelStatusViewState();
}

class _HotelStatusViewState extends State<HotelStatusView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Hotel Status',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: provider.refreshData,
                  icon: const Icon(Icons.refresh, color: AppColors.accent),
                ),
              ],
            ),
            if (provider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            Expanded(
              child: GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 1100 ? 3 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  _SummaryCard(
                    title: 'Total Incidents',
                    value: provider.totalIncidents.toString(),
                    icon: Icons.report_gmailerrorred,
                  ),
                  _SummaryCard(
                    title: 'Fire Alerts',
                    value: provider.fireAlerts.toString(),
                    icon: Icons.local_fire_department_outlined,
                  ),
                  _SummaryCard(
                    title: 'Medical SOS',
                    value: provider.medicalAlerts.toString(),
                    icon: Icons.medical_services_outlined,
                  ),
                  _SummaryCard(
                    title: 'Trapped Guests',
                    value: provider.trappedGuests.toString(),
                    icon: Icons.person_off_outlined,
                  ),
                  _ProgressCard(progress: provider.evacuationProgress),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.accent),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: progress,
                color: AppColors.accent,
                backgroundColor: AppColors.background,
                strokeWidth: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Evacuation Progress',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).round()}%',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
