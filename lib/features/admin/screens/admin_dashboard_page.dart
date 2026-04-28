import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/features/admin/models/admin_models.dart';
import 'package:frontend/features/admin/providers/dashboard_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:frontend/features/admin/widgets/hotel_status_view.dart';
import 'package:frontend/features/admin/widgets/digital_twin_map.dart';
import 'package:frontend/features/admin/screens/evaluation_monitor_page.dart';
import 'package:frontend/features/admin/widgets/broadcast_panel.dart';

// ─────────────────────────────────────────────
// Data models for Supabase responses
// ─────────────────────────────────────────────

class _DashboardStats {
  final int totalIncidents;
  final int fireAlerts;
  final int medicalSos;
  final int trappedGuests;
  final double evacuationPercent;
  final String evacuationStatus;
  final String evacuationDescription;
  final List<_IncidentPoint> incidentTimeline;

  const _DashboardStats({
    required this.totalIncidents,
    required this.fireAlerts,
    required this.medicalSos,
    required this.trappedGuests,
    required this.evacuationPercent,
    required this.evacuationStatus,
    required this.evacuationDescription,
    required this.incidentTimeline,
  });

  factory _DashboardStats.empty() => const _DashboardStats(
        totalIncidents: 0,
        fireAlerts: 0,
        medicalSos: 0,
        trappedGuests: 0,
        evacuationPercent: 0,
        evacuationStatus: 'Not Started',
        evacuationDescription: 'Evacuation has not been initiated yet.',
        incidentTimeline: [],
      );
}

class _IncidentPoint {
  final String hour;
  final int totalIncidents;
  final int fireAlerts;
  final int medicalSos;

  const _IncidentPoint({
    required this.hour,
    required this.totalIncidents,
    required this.fireAlerts,
    required this.medicalSos,
  });
}

// ─────────────────────────────────────────────
// Supabase service
// ─────────────────────────────────────────────

class _DashboardService {
  // Lazy getter — resolved at call time, not class-load time.
  // Prevents "Supabase not initialized" crashes on startup.
  static SupabaseClient get _supabase => Supabase.instance.client;

  /// Fetches all dashboard stats from the incidents table.
  ///
  /// Real schema (confirmed from Supabase screenshots):
  ///   id uuid, incident_type text, location text, floor int4, room text,
  ///   status text, created_by text, created_at timestamptz,
  ///   assigned_staff_id text, updated_at timestamptz
  ///
  /// incident_type values: 'FIRE', 'MEDICAL', 'trapped'
  /// status values:        'active', 'cancelled', 'assigned'
  ///
  /// NOTE: "trapped guests" are incidents with incident_type = 'trapped'
  ///       (no separate guests table needed).
  static Future<_DashboardStats> fetchStats() async {
    final results = await Future.wait([
      // All non-cancelled incidents (active + assigned) — used for counts
      _supabase
          .from('incidents')
          .select('id, incident_type, created_at, status')
          .neq('status', 'cancelled'),

      // All evacuation zones — used to derive overall progress
      // Columns confirmed: varies, but we look for 'status', 'evacuated',
      // 'is_evacuated', or a numeric 'percent' field and handle all gracefully.
      _supabase.from('evacuation_zones').select(),

      // Last 7 days of incidents for the timeline chart
      _supabase
          .from('incidents')
          .select('id, incident_type, created_at')
          .neq('status', 'cancelled')
          .gte(
            'created_at',
            DateTime.now()
                .toUtc()
                .subtract(const Duration(days: 6))
                .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
                .toIso8601String(),
          )
          .order('created_at', ascending: true),
    ]);

    final allRows = results[0] as List;

    // Derive counters from the single result set
    int totalIncidents = 0;
    int fireAlerts = 0;
    int medicalSos = 0;
    int trappedGuests = 0;

    for (final row in allRows) {
      final r = row as Map<String, dynamic>;
      final type = (r['incident_type'] as String? ?? '').toUpperCase();
      // Only count as an "incident" the operational types
      if (type == 'FIRE' || type == 'MEDICAL') totalIncidents++;
      if (type == 'FIRE') fireAlerts++;
      if (type == 'MEDICAL') medicalSos++;
      if (type == 'TRAPPED') trappedGuests++;
    }

    // Derive evacuation progress from evacuation_zones rows.
    // We handle multiple possible column shapes gracefully:
    //   • row has a top-level 'percent' numeric  → use it directly
    //   • row has 'status' == 'evacuated' / 'cleared' / 'safe' → count as cleared
    //   • row has boolean 'is_evacuated' == true → count as cleared
    // If none match we treat the evacuation as Not Started.
    final evacuationRows = results[1] as List;
    double evacuationPercent = 0;
    String evacuationStatus = 'Not Started';
    String evacuationDescription = 'Evacuation has not been initiated yet.';

    if (evacuationRows.isNotEmpty) {
      // Check if the first row carries a direct 'percent' field
      final firstRow = evacuationRows.first as Map<String, dynamic>;
      if (firstRow.containsKey('percent') && firstRow['percent'] != null) {
        // Single-row summary style
        evacuationPercent = (firstRow['percent'] as num).toDouble();
        evacuationStatus = firstRow['status'] as String? ?? 'In Progress';
        evacuationDescription =
            firstRow['description'] as String? ?? 'Evacuation is underway.';
      } else {
        // Multi-row zone style — derive percent from cleared zones
        int totalZones = evacuationRows.length;
        int clearedZones = 0;
        for (final r in evacuationRows) {
          final row = r as Map<String, dynamic>;
          final zoneStatus =
              (row['status'] as String? ?? '').toLowerCase();
          final isEvacuated = row['is_evacuated'] as bool? ?? false;
          final evacuatedFlag =
              (row['evacuated'] as bool?) ?? false;
          if (isEvacuated ||
              evacuatedFlag ||
              zoneStatus == 'evacuated' ||
              zoneStatus == 'cleared' ||
              zoneStatus == 'safe') {
            clearedZones++;
          }
        }
        evacuationPercent = totalZones > 0
            ? (clearedZones / totalZones * 100)
            : 0;
        if (evacuationPercent == 0) {
          evacuationStatus = 'Not Started';
          evacuationDescription = 'Evacuation has not been initiated yet.';
        } else if (evacuationPercent >= 100) {
          evacuationStatus = 'Complete';
          evacuationDescription =
              'All $totalZones zones have been evacuated.';
        } else {
          evacuationStatus = 'In Progress';
          evacuationDescription =
              '$clearedZones of $totalZones zones cleared.';
        }
      }
    }

    // Build hourly timeline from today's incidents
    final todayRows = results[2] as List;
    final timeline = _buildHourlyTimeline(todayRows);

    return _DashboardStats(
      totalIncidents: totalIncidents,
      fireAlerts: fireAlerts,
      medicalSos: medicalSos,
      trappedGuests: trappedGuests,
      evacuationPercent: evacuationPercent,
      evacuationStatus: evacuationStatus,
      evacuationDescription: evacuationDescription,
      incidentTimeline: timeline,
    );
  }

  /// Buckets incidents from the last 7 days into daily [_IncidentPoint] entries.
  static List<_IncidentPoint> _buildDailyTimeline(List<dynamic> rows) {
    final now = DateTime.now().toLocal();
    // Build 7 slots: day-6 (oldest) … day-0 (today)
    final totals = List<int>.filled(7, 0);
    final fires  = List<int>.filled(7, 0);
    final medics = List<int>.filled(7, 0);

    for (final row in rows) {
      final r = row as Map<String, dynamic>;
      final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
      if (createdAt == null) continue;
      final local = createdAt.toLocal();
      final dayDiff = now.difference(
        DateTime(local.year, local.month, local.day),
      ).inDays;
      if (dayDiff < 0 || dayDiff > 6) continue;
      final slot = 6 - dayDiff; // slot 6 = today, slot 0 = 6 days ago
      final type = (r['incident_type'] as String? ?? '').toUpperCase();
      if (type == 'FIRE' || type == 'MEDICAL') totals[slot]++;
      if (type == 'FIRE') fires[slot]++;
      if (type == 'MEDICAL') medics[slot]++;
    }

    // Label each slot as a short day name or "Today"
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      final label = i == 6 ? 'Today' : weekdays[date.weekday - 1];
      return _IncidentPoint(
        hour: label,
        totalIncidents: totals[i],
        fireAlerts: fires[i],
        medicalSos: medics[i],
      );
    });
  }

  // Keep old name as alias so call sites don't need changing
  static List<_IncidentPoint> _buildHourlyTimeline(List<dynamic> rows) =>
      _buildDailyTimeline(rows);

  /// Realtime stream that fires whenever incidents or evacuation zones change.
  ///
  /// Uses a timestamp suffix on channel names so each subscription gets a
  /// unique channel — prevents "channel already exists" conflicts on hot
  /// restart or widget rebuild, which silently killed the old subscription.
  static Stream<void> get changeStream {
    final controller = StreamController<void>.broadcast();
    final suffix = DateTime.now().millisecondsSinceEpoch;
    RealtimeChannel? incidentsCh;
    RealtimeChannel? evacuationCh;

    void emit(_) {
      if (!controller.isClosed) controller.add(null);
    }

    try {
      incidentsCh = _supabase
          .channel('incidents_ch_$suffix')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'incidents',
            callback: emit,
          )
          .subscribe();

      evacuationCh = _supabase
          .channel('evacuation_zones_ch_$suffix')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'evacuation_zones',
            callback: emit,
          )
          .subscribe();
    } catch (_) {
      // Supabase unavailable (offline / test) — stream stays open but silent.
    }

    controller.onCancel = () {
      try {
        if (incidentsCh != null) _supabase.removeChannel(incidentsCh);
        if (evacuationCh != null) _supabase.removeChannel(evacuationCh);
      } catch (_) {}
      controller.close();
    };

    return controller.stream;
  }
}

// ─────────────────────────────────────────────
// Main page
// ─────────────────────────────────────────────

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        // Desktop / tablet: sidebar layout
        // Mobile: drawer + bottom nav (retained for compatibility)
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 768;
            return isWide
                ? _WideLayout(provider: provider)
                : _NarrowLayout(provider: provider);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Wide (sidebar) layout
// ─────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.provider});
  final DashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          _Sidebar(
            selectedTab: provider.activeTab,
            onSelected: provider.setActiveTab,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(onRefresh: provider.refreshData),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _tabContent(provider),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabContent(DashboardProvider provider) {
    switch (provider.activeTab) {
      case AdminNavTab.dashboard:
        return const _DashboardHomeView(key: ValueKey('dashboard'));
      case AdminNavTab.incidentControl:
        return IncidentControlPanel(key: ValueKey('incident-control'));
      case AdminNavTab.staffManagement:
        return StaffCoordinationPanel(key: ValueKey('staff-management'));
      case AdminNavTab.digitalTwinMap:
        return const DigitalTwinMap(key: ValueKey('digital-twin-map'));
      case AdminNavTab.evacuationMonitor:
        return const EvaluationMonitorPage(key: ValueKey('evaluation-monitor'));
      case AdminNavTab.broadcast:
        return const BroadcastPanel(key: ValueKey('broadcast'));
      default:
        return _PlaceholderPanel(
          key: ValueKey(provider.activeTab.name),
          title: _tabTitle(provider.activeTab),
          subtitle: _tabSubtitle(provider.activeTab),
        );
    }
  }

  static String _tabTitle(AdminNavTab t) {
    const map = {
      AdminNavTab.digitalTwinMap: 'Digital Twin Map',
      AdminNavTab.evacuationMonitor: 'Evacuation Monitor',
      AdminNavTab.broadcast: 'Broadcast',
      AdminNavTab.equipment: 'Equipment',
      AdminNavTab.history: 'History',
      AdminNavTab.configuration: 'Configuration',
    };
    return map[t] ?? '';
  }

  static String _tabSubtitle(AdminNavTab t) {
    const map = {
      AdminNavTab.digitalTwinMap: 'Building simulation and zone rendering.',
      AdminNavTab.evacuationMonitor:
          'Live roll-up of floor-by-floor evacuation status.',
      AdminNavTab.broadcast: 'Emergency announcements and staff push alerts.',
      AdminNavTab.equipment: 'Responder gear and maintenance readiness.',
      AdminNavTab.history: 'Incident archive and post-mortem records.',
      AdminNavTab.configuration:
          'Building state, thresholds, and rule management.',
    };
    return map[t] ?? '';
  }
}

// ─────────────────────────────────────────────
// Narrow (mobile) layout — original chips + bottom nav
// ─────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({required this.provider});
  final DashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: provider.refreshData,
            icon: const Icon(Icons.refresh, color: AppColors.accent),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _MobileTabChips(
              selectedTab: provider.activeTab,
              onSelected: provider.setActiveTab,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: provider.activeTab == AdminNavTab.dashboard
                      ? const _DashboardHomeView(key: ValueKey('dashboard'))
                      : _WideLayout(provider: provider),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _AdminBottomNav(
        selectedTab: provider.activeTab,
        onSelected: provider.setActiveTab,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedTab, required this.onSelected});

  final AdminNavTab selectedTab;
  final ValueChanged<AdminNavTab> onSelected;

  static const _items = <({AdminNavTab tab, String label, IconData icon})>[
    (tab: AdminNavTab.dashboard, label: 'Dashboard', icon: Icons.dashboard_outlined),
    (tab: AdminNavTab.digitalTwinMap, label: 'Digital Twin Map', icon: Icons.view_in_ar_outlined),
    (tab: AdminNavTab.incidentControl, label: 'Incident Control', icon: Icons.shield_outlined),
    (tab: AdminNavTab.staffManagement, label: 'Staff Management', icon: Icons.groups_outlined),
    (tab: AdminNavTab.evacuationMonitor, label: 'Evacuation Monitor', icon: Icons.directions_run_outlined),
    (tab: AdminNavTab.broadcast, label: 'Broadcast', icon: Icons.campaign_outlined),
    (tab: AdminNavTab.history, label: 'History', icon: Icons.history_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          ..._items.map((item) => _SidebarItem(
                tab: item.tab,
                label: item.label,
                icon: item.icon,
                isSelected: selectedTab == item.tab,
                onTap: () => onSelected(item.tab),
              )),
          // Push Settings to the bottom
          const Spacer(),
          const Divider(color: Color(0xFF2A1A14), height: 1, indent: 12, endIndent: 12),
          const SizedBox(height: 8),
          _SidebarItem(
            tab: AdminNavTab.configuration,
            label: 'Settings',
            icon: Icons.settings_outlined,
            isSelected: selectedTab == AdminNavTab.configuration,
            onTap: () => onSelected(AdminNavTab.configuration),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tab,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final AdminNavTab tab;
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppColors.accent : Colors.white54,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? Colors.white : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Text(
            'Admin Dashboard',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Dashboard home view (fetches from Supabase)
// ─────────────────────────────────────────────

class _DashboardHomeView extends StatefulWidget {
  const _DashboardHomeView({super.key});

  @override
  State<_DashboardHomeView> createState() => _DashboardHomeViewState();
}

class _DashboardHomeViewState extends State<_DashboardHomeView> {
  _DashboardStats _stats = _DashboardStats.empty();
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _realtimeSub;
  // Debounce: prevents redundant fetches when multiple Realtime events
  // arrive in quick succession (e.g. bulk inserts or zone updates).
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    // Cancel any stale subscription before creating a fresh one.
    // This is important on hot restart where the widget is remounted.
    _realtimeSub?.cancel();
    _realtimeSub = _DashboardService.changeStream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), _loadStats);
    });
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _DashboardService.fetchStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () { setState(() { _loading = true; }); _loadStats(); },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return _DashboardContent(stats: _stats);
  }
}

// ─────────────────────────────────────────────
// Dashboard content (layout)
// ─────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.stats});
  final _DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hotel Status',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // ── Stat cards row ──
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.warning_amber_rounded,
                  label: 'Total Incidents',
                  value: stats.totalIncidents.toString(),
                  description: 'Active incidents reported',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Fire Alerts',
                  value: stats.fireAlerts.toString(),
                  description: 'Active fire alerts',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.medical_services_outlined,
                  label: 'Medical SOS',
                  value: stats.medicalSos.toString(),
                  description: 'Active medical emergencies',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.no_accounts_outlined,
                  label: 'Trapped Guests',
                  value: stats.trappedGuests.toString(),
                  description: 'Guests needing assistance',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Charts row ──
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _EvacuationCard(
                    percent: stats.evacuationPercent,
                    status: stats.evacuationStatus,
                    description: stats.evacuationDescription,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: _IncidentOverviewCard(
                    timeline: stats.incidentTimeline,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Quick actions ──
          _QuickActionsCard(
            onIncidentControl: () =>
                context.read<DashboardProvider>().setActiveTab(AdminNavTab.incidentControl),
            onBroadcast: () =>
                context.read<DashboardProvider>().setActiveTab(AdminNavTab.broadcast),
            onEvacuation: () =>
                context.read<DashboardProvider>().setActiveTab(AdminNavTab.evacuationMonitor),
            onStaff: () =>
                context.read<DashboardProvider>().setActiveTab(AdminNavTab.staffManagement),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Stat card
// ─────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(icon, color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Evacuation card with animated donut painter
// ─────────────────────────────────────────────

class _EvacuationCard extends StatefulWidget {
  const _EvacuationCard({
    required this.percent,
    required this.status,
    required this.description,
  });

  final double percent;
  final String status;
  final String description;

  @override
  State<_EvacuationCard> createState() => _EvacuationCardState();
}

class _EvacuationCardState extends State<_EvacuationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prevPercent = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(begin: 0, end: widget.percent / 100)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_EvacuationCard old) {
    super.didUpdateWidget(old);
    if (old.percent != widget.percent) {
      _prevPercent = old.percent / 100;
      _anim = Tween<double>(begin: _prevPercent, end: widget.percent / 100)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _statusColor {
    switch (widget.status.toLowerCase()) {
      case 'complete':
        return Colors.greenAccent;
      case 'in progress':
        return Colors.orange;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evacuation Progress',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      percent: _anim.value,
                      trackColor: Colors.white12,
                      fillColor: AppColors.accent,
                    ),
                    child: Center(
                      child: Text(
                        '${((_anim.value) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Evacuation Status',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.status,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _statusColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.description,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white54, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.percent,
    required this.trackColor,
    required this.fillColor,
  });

  final double percent;
  final Color trackColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.10;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Track
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Fill
    if (percent > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * percent,
        false,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );

      // Dot at the tip
      final angle = -math.pi / 2 + 2 * math.pi * percent;
      final r = (size.width - strokeWidth) / 2;
      final cx = size.width / 2 + r * math.cos(angle);
      final cy = size.height / 2 + r * math.sin(angle);
      canvas.drawCircle(
        Offset(cx, cy),
        strokeWidth * 0.6,
        Paint()..color = fillColor,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.percent != percent || old.fillColor != fillColor;
}

// ─────────────────────────────────────────────
// Incident overview card with animated area chart
// ─────────────────────────────────────────────

class _IncidentOverviewCard extends StatefulWidget {
  const _IncidentOverviewCard({required this.timeline});
  final List<_IncidentPoint> timeline;

  @override
  State<_IncidentOverviewCard> createState() => _IncidentOverviewCardState();
}

class _IncidentOverviewCardState extends State<_IncidentOverviewCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_IncidentOverviewCard old) {
    super.didUpdateWidget(old);
    if (old.timeline != widget.timeline) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Incident Overview',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              Text(
                'Today (hourly)',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.35)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: widget.timeline.isEmpty
                ? const Center(
                    child: Text(
                      'No incidents recorded today',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : AnimatedBuilder(
                    animation: _anim,
                    builder: (_, __) => CustomPaint(
                      painter: _AreaChartPainter(
                        timeline: widget.timeline,
                        progress: _anim.value,
                      ),
                      size: Size.infinite,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          if (widget.timeline.isNotEmpty)
            _XAxisLabels(timeline: widget.timeline),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _LegendDot(color: Color(0xFFFF6B6B), label: 'Total Incidents'),
              SizedBox(width: 16),
              _LegendDot(color: Color(0xFFFF9F43), label: 'Fire Alerts'),
              SizedBox(width: 16),
              _LegendDot(color: Color(0xFF54A0FF), label: 'Medical SOS'),
            ],
          ),
        ],
      ),
    );
  }
}

class _XAxisLabels extends StatelessWidget {
  const _XAxisLabels({required this.timeline});
  final List<_IncidentPoint> timeline;

  @override
  Widget build(BuildContext context) {
    final count = timeline.length;
    if (count == 0) return const SizedBox.shrink();

    // Always show first, last, and up to 4 evenly-spaced labels in between.
    // This avoids crowding on small datasets and gaps on large ones.
    const maxLabels = 6;
    final indices = <int>{0, count - 1};
    if (count > 2) {
      final step = (count - 1) / (maxLabels - 1);
      for (int i = 1; i < maxLabels - 1; i++) {
        indices.add((i * step).round().clamp(0, count - 1));
      }
    }
    final sorted = indices.toList()..sort();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(count, (i) {
        final label = sorted.contains(i) ? timeline[i].hour : '';
        return Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, color: Colors.white38),
          ),
        );
      }),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  const _AreaChartPainter({
    required this.timeline,
    this.progress = 1.0,
  });

  final List<_IncidentPoint> timeline;
  /// 0.0 → 1.0 animation progress (chart draws left→right)
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (timeline.isEmpty) return;

    // Reserve left margin so Y-axis labels don't overlap the chart lines.
    const leftMargin = 28.0;
    final chartWidth = size.width - leftMargin;
    final chartHeight = size.height;

    final maxVal = timeline
        .fold<int>(
            1,
            (prev, p) => math.max(
                prev,
                math.max(
                    p.totalIncidents,
                    math.max(p.fireAlerts, p.medicalSos))))
        .toDouble();

    // Clip canvas to animated width (offset by left margin)
    canvas.save();
    canvas.clipRect(
        Rect.fromLTWH(leftMargin, 0, chartWidth * progress, chartHeight));

    // Horizontal grid lines
    for (int i = 0; i <= 3; i++) {
      final y = chartHeight * (1 - i / 3);
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.07)
          ..strokeWidth = 1,
      );
    }

    // Helper: data index + value → canvas Offset
    Offset toOffset(int idx, double val) {
      final n = timeline.length;
      final x = leftMargin +
          (n == 1 ? chartWidth / 2 : idx / (n - 1) * chartWidth);
      final y = maxVal == 0 ? chartHeight : chartHeight * (1 - val / maxVal);
      return Offset(x, y);
    }

    _drawSeries(canvas, size, maxVal,
        timeline.map((p) => p.totalIncidents.toDouble()).toList(),
        const Color(0xFFFF6B6B), toOffset);
    _drawSeries(canvas, size, maxVal,
        timeline.map((p) => p.fireAlerts.toDouble()).toList(),
        const Color(0xFFFF9F43), toOffset);
    _drawSeries(canvas, size, maxVal,
        timeline.map((p) => p.medicalSos.toDouble()).toList(),
        const Color(0xFF54A0FF), toOffset);

    canvas.restore();

    // Y-axis value labels — drawn outside the clip so always visible
    final maxInt = maxVal.toInt();
    for (int i = 0; i <= 3; i++) {
      final val = (maxInt * i / 3).round();
      final y = chartHeight * (1 - i / 3);
      final tp = TextPainter(
        text: TextSpan(
          text: '$val',
          style: TextStyle(
              fontSize: 9, color: Colors.white.withValues(alpha: 0.4)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Right-align within the left margin
      tp.paint(canvas, Offset(leftMargin - tp.width - 4, y - tp.height / 2));
    }
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    double maxVal,
    List<double> values,
    Color color,
    Offset Function(int idx, double val) toOffset,
  ) {
    if (values.isEmpty) return;
    final pts = List.generate(values.length, (i) => toOffset(i, values[i]));

    // Filled area under the line
    final areaPath = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) { areaPath.lineTo(p.dx, p.dy); }
    areaPath
      ..lineTo(pts.last.dx, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );

    // Smooth cubic bezier line
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final cpX = (prev.dx + curr.dx) / 2;
      linePath.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Dots at each data point
    for (final p in pts) {
      canvas.drawCircle(p, 3.5, Paint()..color = color.withValues(alpha: 0.9));
      canvas.drawCircle(
          p,
          3.5,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_AreaChartPainter old) {
    if (old.progress != progress) return true;
    if (old.timeline.length != timeline.length) return true;
    for (int i = 0; i < timeline.length; i++) {
      final a = old.timeline[i];
      final b = timeline[i];
      if (a.totalIncidents != b.totalIncidents ||
          a.fireAlerts != b.fireAlerts ||
          a.medicalSos != b.medicalSos) { return true; }
    }
    return false;
  }
}

// ─────────────────────────────────────────────
// Quick actions card
// ─────────────────────────────────────────────

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onIncidentControl,
    required this.onBroadcast,
    required this.onEvacuation,
    required this.onStaff,
  });

  final VoidCallback onIncidentControl;
  final VoidCallback onBroadcast;
  final VoidCallback onEvacuation;
  final VoidCallback onStaff;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.shield_outlined,
                  label: 'Incident Control',
                  onTap: onIncidentControl,
                ),
              ),
              _Divider(),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.campaign_outlined,
                  label: 'Broadcast Alert',
                  onTap: onBroadcast,
                ),
              ),
              _Divider(),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.directions_run_outlined,
                  label: 'Evacuation Monitor',
                  onTap: onEvacuation,
                ),
              ),
              _Divider(),
              Expanded(
                child: _QuickActionButton(
                  icon: Icons.groups_outlined,
                  label: 'Staff Management',
                  onTap: onStaff,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 40, color: Colors.white.withValues(alpha: 0.08));
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.accent, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11.5, color: Colors.white70, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Placeholder panel (for unimplemented tabs)
// ─────────────────────────────────────────────

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Mobile tab chips (kept for narrow layout)
// ─────────────────────────────────────────────

class _MobileTabChips extends StatelessWidget {
  const _MobileTabChips({required this.selectedTab, required this.onSelected});

  final AdminNavTab selectedTab;
  final ValueChanged<AdminNavTab> onSelected;

  static const List<({AdminNavTab tab, String label})> _tabs = [
    (tab: AdminNavTab.dashboard, label: 'Dashboard'),
    (tab: AdminNavTab.digitalTwinMap, label: 'Digital Twin Map'),
    (tab: AdminNavTab.incidentControl, label: 'Incident Control'),
    (tab: AdminNavTab.staffManagement, label: 'Staff Management'),
    (tab: AdminNavTab.evacuationMonitor, label: 'Evacuation Monitor'),
    (tab: AdminNavTab.broadcast, label: 'Broadcast'),
    (tab: AdminNavTab.equipment, label: 'Equipment'),
    (tab: AdminNavTab.history, label: 'History'),
    (tab: AdminNavTab.configuration, label: 'Configuration'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: _tabs
            .map((item) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: selectedTab == item.tab,
                    onSelected: (_) => onSelected(item.tab),
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.card,
                    side: BorderSide(
                        color: AppColors.accent.withValues(alpha: 0.35)),
                    label: Text(
                      item.label,
                      style: TextStyle(
                        color: selectedTab == item.tab
                            ? AppColors.background
                            : Colors.white,
                      ),
                    ),
                  ),
                ))
            .toList(growable: false),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bottom nav (kept for narrow layout)
// ─────────────────────────────────────────────

class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({required this.selectedTab, required this.onSelected});

  final AdminNavTab selectedTab;
  final ValueChanged<AdminNavTab> onSelected;

  int get _indexFromTab {
    switch (selectedTab) {
      case AdminNavTab.dashboard:
        return 0;
      case AdminNavTab.incidentControl:
        return 1;
      case AdminNavTab.staffManagement:
        return 2;
      default:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      backgroundColor: AppColors.card,
      indicatorColor: AppColors.accent,
      selectedIndex: _indexFromTab,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            onSelected(AdminNavTab.dashboard);
          case 1:
            onSelected(AdminNavTab.incidentControl);
          case 2:
            onSelected(AdminNavTab.staffManagement);
          case 3:
            onSelected(AdminNavTab.digitalTwinMap);
        }
      },
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.dashboard_outlined), label: 'Home'),
        NavigationDestination(
            icon: Icon(Icons.warning_amber_rounded), label: 'Incidents'),
        NavigationDestination(
            icon: Icon(Icons.groups_outlined), label: 'Staff'),
        NavigationDestination(
            icon: Icon(Icons.map_outlined), label: 'Map'),
      ],
    );
  }
}