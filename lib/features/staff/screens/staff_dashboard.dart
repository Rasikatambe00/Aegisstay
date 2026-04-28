import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/features/staff/screens/responder_map.dart';
import 'package:frontend/features/staff/widgets/incident_alert_overlay.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // FIX #4: Team Radio dialpad

class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({
    super.key,
    required this.staffName,
    required this.staffCategory,
  });

  final String staffName;
  final String staffCategory;

  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage> {
  bool _onDuty = false;
  bool _isTogglingDuty = false;

  RealtimeChannel? _assignmentChannel;
  RealtimeChannel? _incidentChannel;

  StaffTaskAssignment? _assignedTask;
  bool _isTaskActionLoading = false;
  bool _isRefreshing = false;

  int _activeAlertCount = 0;
  bool _isLoadingAlerts = true;

  bool _showingOverlay = false;
  StaffTaskAssignment? _pendingOverlayTask;

  // FIX #7: last-updated timestamp
  DateTime? _lastUpdated;

  // FIX #6: Safe zones loaded from Supabase
  List<_SafeZone> _safeZones = [];
  bool _isLoadingZones = false;

  // Activities feed loaded from Supabase
  List<_ActivityItem> _activities = [];
  bool _isLoadingActivities = false;
  RealtimeChannel? _activityChannel;


  @override
  void initState() {
    super.initState();
    _loadOnDutyStatus();
    _loadAssignedTask();
    _loadActiveAlertCount();
    _loadActivities();
    // FIX #1: subscriptions only started when on duty is confirmed;
    // _setOnDuty also gates subscribe/unsubscribe.
    _subscribeToAssignments();
    _subscribeToIncidents();
    _subscribeToActivities();
  }

  @override
  void dispose() {
    final c = _safeClient;
    if (c != null) {
      final a = _assignmentChannel;
      if (a != null) c.removeChannel(a);
      final i = _incidentChannel;
      if (i != null) c.removeChannel(i);
      final ac = _activityChannel;
      if (ac != null) c.removeChannel(ac);
    }
    super.dispose();
  }

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadOnDutyStatus() async {
    final client = _safeClient;
    if (client == null) return;
    try {
      final rows = await client
          .from('staff')
          .select('is_on_duty')
          .eq('staff_name', widget.staffName)
          .limit(1);
      if (!mounted || rows.isEmpty) return;
      final duty = (rows.first['is_on_duty'] as bool?) ?? false;
      setState(() => _onDuty = duty);
      // FIX #1: subscribe only after we know on-duty status
      if (duty) {
        _subscribeToAssignments();
        _subscribeToIncidents();
      }
    } catch (_) {}
  }

  Future<void> _setOnDuty(bool value) async {
    if (_isTogglingDuty) return;
    setState(() {
      _isTogglingDuty = true;
      _onDuty = value;
    });

    final client = _safeClient;
    if (client != null) {
      try {
        await client
            .from('staff')
            .update({'is_on_duty': value})
            .eq('staff_name', widget.staffName);
      } catch (_) {
        if (mounted) {
          setState(() => _onDuty = !value);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update duty status.')),
          );
        }
      }
    }

    // FIX #1: gate subscriptions on duty toggle
    if (value) {
      _subscribeToAssignments();
      _subscribeToIncidents();
    } else {
      _unsubscribeAll();
      // Clear overlay if going off-duty
      if (mounted) {
        setState(() {
          _showingOverlay = false;
          _pendingOverlayTask = null;
        });
      }
    }

    if (mounted) setState(() => _isTogglingDuty = false);
  }

  void _unsubscribeAll() {
    final c = _safeClient;
    if (c == null) return;
    final a = _assignmentChannel;
    if (a != null) {
      c.removeChannel(a);
      _assignmentChannel = null;
    }
    final i = _incidentChannel;
    if (i != null) {
      c.removeChannel(i);
      _incidentChannel = null;
    }
  }

  void _subscribeToAssignments() {
    // FIX #1: only subscribe when on duty
    if (!_onDuty) return;
    final client = _safeClient;
    if (client == null) return;
    // Avoid duplicate channels
    if (_assignmentChannel != null) return;

    _assignmentChannel = client
        .channel('staff-tasks-${widget.staffName}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'task_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_staff',
            value: widget.staffName,
          ),
          callback: (_) => _onNewAssignment(),
        )
        .subscribe();
  }

  void _subscribeToIncidents() {
    // FIX #1: only subscribe when on duty
    if (!_onDuty) return;
    final client = _safeClient;
    if (client == null) return;
    if (_incidentChannel != null) return;

    _incidentChannel = client
        .channel('incidents-${widget.staffName}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incidents',
          callback: (payload) {
            _loadActiveAlertCount();
            // Log new incident activity — non-blocking
            final location = (payload.newRecord['location'] ?? 'Unknown location').toString();
            _safeClient?.from('activities').insert({
              'type': 'alert',
              'title': 'New Incident',
              'subtitle': location,
            }).catchError((_) {});
          },
        )
        .subscribe();
  }

  Future<void> _onNewAssignment() async {
    // FIX #1: only process incoming assignments when on duty
    if (!_onDuty) return;
    await _loadAssignedTask();
    final task = _assignedTask;
    if (task != null && task.status == 'assigned' && !_showingOverlay) {
      // Log task assigned activity — non-blocking
      _safeClient?.from('activities').insert({
        'type': 'info',
        'title': 'Task Assigned',
        'subtitle': task.location,
      }).catchError((_) {});
      if (mounted) {
        setState(() {
          _pendingOverlayTask = task;
          _showingOverlay = true;
        });
      }
    }
  }

  Future<void> _loadActiveAlertCount() async {
    final client = _safeClient;
    if (client == null) {
      if (mounted) setState(() => _isLoadingAlerts = false);
      return;
    }
    try {
      final rows = await client
          .from('incidents')
          .select('id')
          .inFilter('status', const ['active', 'assigned']);
      if (!mounted) return;
      setState(() {
        _activeAlertCount = rows.length;
        _isLoadingAlerts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingAlerts = false);
    }
  }

  Future<void> _loadAssignedTask() async {
    final client = _safeClient;
    if (client == null) return;
    try {
      final rows = await client
          .from('task_assignments')
          .select('id,incident_type,location,role,route,assigned_staff,status,created_at')
          .eq('assigned_staff', widget.staffName)
          .inFilter('status', const ['assigned', 'accepted'])
          .order('created_at', ascending: false)
          .limit(1);

      if (!mounted) return;

      if (rows.isEmpty) {
        setState(() => _assignedTask = null);
        return;
      }

      final row = rows.first;
      setState(() {
        _assignedTask = StaffTaskAssignment(
          id: row['id'].toString(),
          incidentType: (row['incident_type'] ?? 'Unknown').toString(),
          location: (row['location'] ?? 'Unknown').toString(),
          role: (row['role'] ?? 'Support response').toString(),
          route: (row['route'] ?? 'Nearest safe route').toString(),
          status: (row['status'] ?? 'assigned').toString(),
        );
      });
    } catch (_) {}
  }

  Future<void> _refreshTasks() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await Future.wait([_loadAssignedTask(), _loadActiveAlertCount(), _loadActivities()]);
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _lastUpdated = DateTime.now(); // FIX #7: record last-updated time
      });
    }
  }

  Future<void> _updateTaskStatus(String nextStatus) async {
    final task = _assignedTask;
    if (task == null || _isTaskActionLoading) return;

    setState(() {
      _isTaskActionLoading = true;
      _assignedTask = StaffTaskAssignment(
        id: task.id,
        incidentType: task.incidentType,
        location: task.location,
        role: task.role,
        route: task.route,
        status: nextStatus,
      );
    });

    try {
      final client = _safeClient;
      if (client == null) throw Exception('no client');

      await client
          .from('task_assignments')
          .update({'status': nextStatus})
          .eq('id', task.id);

      // Log completed activity — non-blocking
      if (nextStatus == 'completed') {
        _safeClient?.from('activities').insert({
          'type': 'success',
          'title': 'All Clear',
          'subtitle': task.location,
        }).catchError((_) {});
      }

      await _loadAssignedTask();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'completed'
                ? 'Task marked completed ✓'
                : 'Task accepted.',
          ),
        ),
      );

      if (nextStatus == 'accepted' && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ResponderMapPage(
              room: task.location,
              floor: _floorFrom(task.location),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _assignedTask = task);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update task status.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTaskActionLoading = false);
    }
  }

  String _floorFrom(String location) {
    final m = RegExp(r'Floor\s*\d+', caseSensitive: false).firstMatch(location);
    return m?.group(0) ?? 'Floor 1';
  }

  void _acceptOverlay() {
    setState(() => _showingOverlay = false);
    _updateTaskStatus('accepted');
  }

  void _rejectOverlay() {
    setState(() {
      _showingOverlay = false;
      _pendingOverlayTask = null;
    });
  }

  void _confirmComplete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Mark as Completed?'),
        content: const Text(
          'Confirm the task is fully resolved.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateTaskStatus('completed');
            },
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  StaffIncidentType _overlayType(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('medical')) return StaffIncidentType.medical;
    return StaffIncidentType.fire;
  }

  String get _categoryHint {
    switch (widget.staffCategory) {
      case 'Fire Marshals':
        return 'Map objective: turn all guest dots from red to green.';
      case 'Medical Staff':
        return 'Priority mode: medical SOS alerts appear before fire alerts.';
      case 'Floor Staff':
        return 'Manual roll call mode is enabled for guests without the app.';
      default:
        return 'Responder dashboard ready. Follow active alerts.';
    }
  }

  // FIX #7: human-readable last-updated label
  String get _lastUpdatedLabel {
    final t = _lastUpdated;
    if (t == null) return 'Not yet refreshed';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    return 'Updated ${diff.inHours}h ago';
  }

  // Activities: load latest 20 from Supabase
  Future<void> _loadActivities() async {
    final client = _safeClient;
    if (client == null) return;
    if (mounted) setState(() => _isLoadingActivities = true);
    try {
      final rows = await client
          .from('activities')
          .select('type,title,subtitle,created_at')
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() {
        _activities = rows.map<_ActivityItem>((r) => _ActivityItem(
          type: (r['type'] ?? 'info').toString(),
          title: (r['title'] ?? '').toString(),
          subtitle: (r['subtitle'] ?? '').toString(),
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
        )).toList();
        _isLoadingActivities = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingActivities = false);
    }
  }

  // Activities: subscribe to realtime inserts so the feed updates live
  void _subscribeToActivities() {
    final client = _safeClient;
    if (client == null) return;
    if (_activityChannel != null) return;
    _activityChannel = client
        .channel('activities-feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'activities',
          callback: (_) => _loadActivities(),
        )
        .subscribe();
  }

  // FIX #6: load safe zones from Supabase
  // [sheetSetState] is the StatefulBuilder's setter so the sheet rebuilds too
  Future<void> _loadSafeZones([StateSetter? sheetSetState]) async {
    final client = _safeClient;
    if (client == null) return;

    void update(VoidCallback fn) {
      if (mounted) setState(fn);
      if (sheetSetState != null) sheetSetState(fn);
    }

    update(() => _isLoadingZones = true);
    try {
      final rows = await client
          .from('safe_zones')
          .select('name,location,capacity,map_url')
          .order('name');
      if (!mounted) return;
      update(() {
        _safeZones = rows
            .map<_SafeZone>(
              (r) => _SafeZone(
                zone: (r['name'] ?? '').toString(),
                location: (r['location'] ?? '').toString(),
                capacity: (r['capacity'] ?? '').toString(),
                mapUrl: r['map_url'] as String?,
              ),
            )
            .toList();
        _isLoadingZones = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingZones = false);
      if (sheetSetState != null) sheetSetState(() => _isLoadingZones = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          drawer: _DashboardDrawer(
            staffName: widget.staffName,
            onRadio: () => _showRadioSheet(context),
            onSafeZones: () => _showSafeZonesSheet(context),
            onSettings: () => _showSettingsSheet(context),
            onLiveAlerts: () => _showLiveAlertsSheet(context),
            onPatrols: () => _showPatrolsSheet(context),
            onReports: () => _showReportsSheet(context),
            onEquipment: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ResponderMapPage(
                  room: 'Equipment Store',
                  floor: 'Floor 1',
                  equipmentMode: true,
                ),
              ),
            ),
          ),
          appBar: AppBar(
            backgroundColor: AppColors.card,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppColors.accent),
            title: const Text(
              'Staff Dashboard',
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            actions: [
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    color: AppColors.accent,
                    onPressed: () => _showNotificationsSheet(context),
                  ),
                  if (_activeAlertCount > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                color: AppColors.accent,
                onPressed: () => _showSettingsSheet(context),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.accent,
              onRefresh: _refreshTasks,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 160),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Welcome gradient header ──────────────────────────
                        _WelcomeCard(
                          staffName: widget.staffName,
                          staffCategory: widget.staffCategory,
                          onDuty: _onDuty,
                          isToggling: _isTogglingDuty,
                          onToggleDuty: _setOnDuty,
                        ),
                        const SizedBox(height: 16),

                        // ── Stats row ────────────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: 'Live Incidents',
                                value: _isLoadingAlerts
                                    ? '—'
                                    : '$_activeAlertCount',
                                icon: Icons.warning_amber_rounded,
                                iconColor: const Color(0xFFEF4444),
                                sub: _lastUpdatedLabel,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                label: 'Task Status',
                                value: _assignedTask == null
                                    ? 'None'
                                    : _assignedTask!.status.toUpperCase(),
                                icon: Icons.task_alt_rounded,
                                iconColor: _assignedTask == null
                                    ? Colors.white38
                                    : const Color(0xFF8DF0A2),
                                sub: _assignedTask?.incidentType ?? 'Standing by',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── Assigned task / no-task card ─────────────────────
                        if (_assignedTask != null)
                          _AssignedTaskCard(
                            task: _assignedTask!,
                            isLoading: _isTaskActionLoading,
                            onAccept: () => _updateTaskStatus('accepted'),
                            onComplete: _confirmComplete,
                          )
                        else
                          _NoTaskCard(onDuty: _onDuty),
                        const SizedBox(height: 20),

                        // ── Quick actions ────────────────────────────────────
                        const _SectionLabel(text: 'Quick Actions'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _QuickActionCard(
                                label: 'Team Radio',
                                icon: Icons.phone_in_talk_rounded,
                                color: const Color(0xFF64B5F6),
                                onTap: () => _showRadioSheet(context),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionCard(
                                label: 'Equipment Map',
                                icon: Icons.fire_extinguisher_rounded,
                                color: const Color(0xFFFFB74D),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const ResponderMapPage(
                                      room: 'Equipment Store',
                                      floor: 'Floor 1',
                                      equipmentMode: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _QuickActionCard(
                                label: 'Safe Zones',
                                icon: Icons.shield_rounded,
                                color: const Color(0xFF81C784),
                                onTap: () => _showSafeZonesSheet(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Category hint ────────────────────────────────────
                        const _SectionLabel(text: 'Category Briefing'),
                        const SizedBox(height: 10),
                        _BriefingCard(hint: _categoryHint),
                        const SizedBox(height: 20),

                        // ── Recent activity ──────────────────────────────────
                        const _SectionLabel(text: 'Recent Activity'),
                        const SizedBox(height: 10),
                        _RecentActivityCard(
                          activities: _activities,
                          isLoading: _isLoadingActivities,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showingOverlay && _pendingOverlayTask != null)
          IncidentAlertOverlay(
            type: _overlayType(_pendingOverlayTask?.incidentType),
            locationText: _pendingOverlayTask?.location ?? 'Unknown Location',
            onAccept: _acceptOverlay,
            onReject: _rejectOverlay,
          ),
      ],
    );
  }

  void _showReportsSheet(BuildContext context) {
    List<Map<String, dynamic>> reports = [];
    bool loading = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (loading) {
            _safeClient
                ?.from('reports')
                .select('id,title,type,submitted_by,status,created_at,summary')
                .order('created_at', ascending: false)
                .limit(30)
                .then((rows) {
              if (ctx.mounted) {
                setSheet(() {
                  reports = List<Map<String, dynamic>>.from(rows);
                  loading = false;
                });
              }
            }).catchError((_) {
              if (ctx.mounted) setSheet(() => loading = false);
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            minChildSize: 0.35,
            builder: (ctx2, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A1F16),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.bar_chart_rounded, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Reports',
                        style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          loading ? '…' : '${reports.length} report${reports.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2A1A14), height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                      : reports.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bar_chart_rounded, color: Colors.white24, size: 40),
                                    SizedBox(height: 12),
                                    Text('No reports found', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: reports.length,
                              separatorBuilder: (context, i) => const Divider(color: Color(0xFF2A1A14), height: 1),
                              itemBuilder: (_, i) {
                                final r       = reports[i];
                                final title   = (r['title'] ?? 'Untitled').toString();
                                final type    = (r['type'] ?? '').toString();
                                final by      = (r['submitted_by'] ?? '').toString();
                                final status  = (r['status'] ?? 'submitted').toString();
                                final summary = (r['summary'] ?? '').toString();
                                final ts      = DateTime.tryParse(r['created_at']?.toString() ?? '');
                                final ago     = ts == null ? '' : _timeAgo(ts);

                                final statusColor = switch (status.toLowerCase()) {
                                  'reviewed'  => const Color(0xFF8DF0A2),
                                  'submitted' => AppColors.accent,
                                  'pending'   => const Color(0xFFFFD54F),
                                  _           => Colors.white38,
                                };

                                final typeIcon = switch (type.toLowerCase()) {
                                  'incident' => Icons.local_fire_department_rounded,
                                  'patrol'   => Icons.directions_walk_rounded,
                                  'medical'  => Icons.medical_services_rounded,
                                  _          => Icons.description_rounded,
                                };

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                  leading: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(typeIcon, color: AppColors.accent, size: 20),
                                  ),
                                  title: Text(title, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (by.isNotEmpty)
                                        Text('By $by', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                      if (summary.isNotEmpty)
                                        Text(summary, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(ago, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPatrolsSheet(BuildContext context) {
    List<Map<String, dynamic>> patrols = [];
    bool loading = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          if (loading) {
            _safeClient
                ?.from('patrols')
                .select('id,area,assigned_staff,status,started_at,notes')
                .order('started_at', ascending: false)
                .limit(30)
                .then((rows) {
              if (ctx.mounted) {
                setSheet(() {
                  patrols = List<Map<String, dynamic>>.from(rows);
                  loading = false;
                });
              }
            }).catchError((_) {
              if (ctx.mounted) setSheet(() => loading = false);
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            minChildSize: 0.35,
            builder: (ctx2, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A1F16),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_walk_rounded, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Patrols',
                        style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          loading ? '…' : '${patrols.length} patrol${patrols.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2A1A14), height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                      : patrols.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions_walk_rounded, color: Colors.white24, size: 40),
                                    SizedBox(height: 12),
                                    Text('No patrols recorded', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: patrols.length,
                              separatorBuilder: (context, i) => const Divider(color: Color(0xFF2A1A14), height: 1),
                              itemBuilder: (_, i) {
                                final p      = patrols[i];
                                final area   = (p['area'] ?? 'Unknown area').toString();
                                final staff  = (p['assigned_staff'] ?? '').toString();
                                final status = (p['status'] ?? 'active').toString();
                                final notes  = (p['notes'] ?? '').toString();
                                final ts     = DateTime.tryParse(p['started_at']?.toString() ?? '');
                                final ago    = ts == null ? '' : _timeAgo(ts);

                                final statusColor = switch (status.toLowerCase()) {
                                  'completed' => const Color(0xFF8DF0A2),
                                  'active'    => AppColors.accent,
                                  _           => Colors.white38,
                                };

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                  leading: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.directions_walk_rounded, color: statusColor, size: 20),
                                  ),
                                  title: Text(area, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (staff.isNotEmpty)
                                        Text(staff, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                      if (notes.isNotEmpty)
                                        Text(notes, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(ago, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showLiveAlertsSheet(BuildContext context) {
    // Local state for the sheet — holds incidents loaded from Supabase
    List<Map<String, dynamic>> incidents = [];
    bool loading = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Load on first build
          if (loading) {
            _safeClient
                ?.from('incidents')
                .select('id,type,location,status,created_at')
                .inFilter('status', const ['active', 'assigned'])
                .order('created_at', ascending: false)
                .limit(30)
                .then((rows) {
              if (ctx.mounted) {
                setSheet(() {
                  incidents = List<Map<String, dynamic>>.from(rows);
                  loading = false;
                });
              }
            }).catchError((_) {
              if (ctx.mounted) setSheet(() => loading = false);
            });
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.92,
            minChildSize: 0.35,
            builder: (ctx2, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A1F16),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Live Alerts',
                        style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const Spacer(),
                      // Live count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          loading ? '…' : '${incidents.length} active',
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2A1A14), height: 1),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                      : incidents.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline, color: Color(0xFF8DF0A2), size: 40),
                                    SizedBox(height: 12),
                                    Text('No active alerts', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: incidents.length,
                              separatorBuilder: (context, i) => const Divider(color: Color(0xFF2A1A14), height: 1),
                              itemBuilder: (_, i) {
                                final inc = incidents[i];
                                final status = (inc['status'] ?? '').toString();
                                final type   = (inc['type'] ?? 'Incident').toString();
                                final loc    = (inc['location'] ?? 'Unknown').toString();
                                final ts     = DateTime.tryParse(inc['created_at']?.toString() ?? '');
                                final ago    = ts == null ? '' : _timeAgo(ts);

                                final statusColor = status == 'active'
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFFFD54F);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                  leading: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      type.toLowerCase().contains('medical')
                                          ? Icons.medical_services_rounded
                                          : Icons.local_fire_department_rounded,
                                      color: statusColor,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(type, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                  subtitle: Text(loc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(ago, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Simple relative time helper used by the live alerts sheet.
  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1F16),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded, color: AppColors.accent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    // Staff name badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        widget.staffName,
                        style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Color(0xFF2A1A14)),
              // Duty toggle
              SwitchListTile(
                value: _onDuty,
                onChanged: _isTogglingDuty
                    ? null
                    : (v) {
                        setSheet(() {});
                        _setOnDuty(v);
                      },
                activeThumbColor: AppColors.accent,
                secondary: Icon(
                  _onDuty ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _onDuty ? AppColors.accent : Colors.white38,
                ),
                title: const Text('On Duty', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _onDuty ? 'You are receiving task assignments' : 'You will not receive assignments',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
              const Divider(color: Color(0xFF2A1A14), height: 1),
              // Staff category (read-only)
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: AppColors.accent),
                title: const Text('Category', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                trailing: Text(
                  widget.staffCategory,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const Divider(color: Color(0xFF2A1A14), height: 1),
              // Clear activity log
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFFFB74D)),
                title: const Text('Clear Activity Log', style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Remove all entries from the activities feed', style: TextStyle(color: Colors.white38, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      backgroundColor: AppColors.card,
                      title: const Text('Clear Activity Log?'),
                      content: const Text(
                        'This will delete all activity entries.',
                        style: TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Clear', style: TextStyle(color: Color(0xFFEF4444))),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _safeClient?.from('activities').delete().neq('id', '').catchError((_) {});
                    await _loadActivities();
                  }
                },
              ),
              const Divider(color: Color(0xFF2A1A14), height: 1),
              // Sign out
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                title: const Text('Sign Out', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final nav = Navigator.of(context);
                  await _safeClient?.auth.signOut().catchError((_) {});
                  if (mounted) nav.popUntil((r) => r.isFirst);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A1F16),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.notifications_rounded, color: AppColors.accent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Notifications',
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoadingActivities
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _activities.isEmpty
                      ? const Center(
                          child: Text(
                            'No notifications yet',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _activities.length,
                          itemBuilder: (_, i) => _ActivityTile(item: _activities[i]),
                        ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRadioSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Team Radio',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 16),
            // FIX #4: _RadioTile now uses url_launcher tel: URI
            _RadioTile(name: 'Duty Manager', number: '+18000000001'),
            _RadioTile(name: 'Security Control', number: '+18000000002'),
            _RadioTile(name: 'Medical Team', number: '+18000000003'),
            _RadioTile(name: 'Fire Control', number: '+18000000004'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSafeZonesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // Load zones and pass setSheetState so the sheet rebuilds on data
          if (!_isLoadingZones && _safeZones.isEmpty) {
            _loadSafeZones(setSheetState);
          }
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Safe Muster Zones',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoadingZones)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  )
                else if (_safeZones.isEmpty)
                  // Fallback to hardcoded defaults if Supabase returns nothing
                  ...[
                    _ZoneRow(
                        zone: 'Zone A',
                        location: 'North Parking Lot',
                        capacity: '200',
                        mapUrl: null),
                    _ZoneRow(
                        zone: 'Zone B',
                        location: 'East Garden',
                        capacity: '150',
                        mapUrl: null),
                    _ZoneRow(
                        zone: 'Zone C',
                        location: 'Main Lobby Exit',
                        capacity: '100',
                        mapUrl: null),
                  ]
                else
                  ..._safeZones.map(
                    (z) => _ZoneRow(
                      zone: z.zone,
                      location: z.location,
                      capacity: z.capacity,
                      mapUrl: z.mapUrl,
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawer
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardDrawer extends StatelessWidget {
  const _DashboardDrawer({
    required this.staffName,
    required this.onRadio,
    required this.onSafeZones,
    required this.onEquipment,
    required this.onSettings,
    required this.onLiveAlerts,
    required this.onPatrols,
    required this.onReports,
  });

  final String staffName;
  final VoidCallback onRadio;
  final VoidCallback onSafeZones;
  final VoidCallback onEquipment;
  final VoidCallback onSettings;
  final VoidCallback onLiveAlerts;
  final VoidCallback onPatrols;
  final VoidCallback onReports;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2A1A14), Color(0xFF1C1614)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                    child: const Icon(Icons.person, color: AppColors.accent, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    staffName,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Staff Member',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerItem(icon: Icons.dashboard_rounded, label: 'Dashboard', onTap: () => Navigator.pop(context)),
                  _DrawerItem(icon: Icons.warning_amber_rounded, label: 'Live Alerts', onTap: () { Navigator.pop(context); onLiveAlerts(); }),
                  _DrawerItem(icon: Icons.local_fire_department_rounded, label: 'Incidents', onTap: () => Navigator.pop(context)),
                  _DrawerItem(icon: Icons.directions_walk_rounded, label: 'Patrols', onTap: () { Navigator.pop(context); onPatrols(); }),
                  _DrawerItem(icon: Icons.bar_chart_rounded, label: 'Reports', onTap: () { Navigator.pop(context); onReports(); }),
                  const Divider(color: Color(0xFF2A1A14), height: 24),
                  _DrawerItem(
                    icon: Icons.phone_in_talk_rounded,
                    label: 'Team Radio',
                    onTap: () { Navigator.pop(context); onRadio(); },
                  ),
                  _DrawerItem(icon: Icons.message_rounded, label: 'Messages', onTap: () => Navigator.pop(context)),
                  _DrawerItem(
                    icon: Icons.shield_rounded,
                    label: 'Safe Zones',
                    onTap: () { Navigator.pop(context); onSafeZones(); },
                  ),
                  _DrawerItem(
                    icon: Icons.fire_extinguisher_rounded,
                    label: 'Equipment',
                    onTap: () { Navigator.pop(context); onEquipment(); },
                  ),
                  const Divider(color: Color(0xFF2A1A14), height: 24),
                  _DrawerItem(icon: Icons.settings_rounded, label: 'Settings', onTap: () { Navigator.pop(context); onSettings(); }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent, size: 20),
      title: Text(label, style: const TextStyle(color: AppColors.white, fontSize: 14)),
      onTap: onTap,
      dense: true,
      horizontalTitleGap: 8,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome gradient header card
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.staffName,
    required this.staffCategory,
    required this.onDuty,
    required this.isToggling,
    required this.onToggleDuty,
  });

  final String staffName;
  final String staffCategory;
  final bool onDuty;
  final bool isToggling;
  final ValueChanged<bool> onToggleDuty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTheme.cardRadius,
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1A14), Color(0xFF1C1614)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            child: const Icon(Icons.person, color: AppColors.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $staffName',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  staffCategory,
                  style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Column(
            children: [
              isToggling
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                    )
                  : Switch(
                      value: onDuty,
                      onChanged: onToggleDuty,
                      activeThumbColor: AppColors.accent,
                    ),
              Text(
                onDuty ? 'On Duty' : 'Off Duty',
                style: TextStyle(
                  color: onDuty ? AppColors.accent : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat card (Live Incidents / Task Status)
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.sub,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: const Color(0xFF2A1A14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick action card
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category briefing card
// ─────────────────────────────────────────────────────────────────────────────

class _BriefingCard extends StatelessWidget {
  const _BriefingCard({required this.hint});
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: const Color(0xFF2A1A14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent activity card (static UI)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Activity data model
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityItem {
  const _ActivityItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
  });

  final String type;   // 'alert' | 'info' | 'success'
  final String title;
  final String subtitle;
  final DateTime createdAt;

  Color get color {
    switch (type) {
      case 'alert':   return const Color(0xFFEF4444);
      case 'success': return const Color(0xFF8DF0A2);
      default:        return const Color(0xFF64B5F6);
    }
  }

  IconData get icon {
    switch (type) {
      case 'alert':   return Icons.warning_amber_rounded;
      case 'success': return Icons.check_circle_rounded;
      default:        return Icons.info_rounded;
    }
  }

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity tile (shared by card + notification sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final _ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(item.icon, color: item.color, size: 16),
      ),
      title: Text(
        item.title,
        style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: item.subtitle.isNotEmpty
          ? Text(item.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11))
          : null,
      trailing: Text(item.timeAgo, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent activity card — live data from Supabase activities table
// ─────────────────────────────────────────────────────────────────────────────

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({
    required this.activities,
    required this.isLoading,
  });

  final List<_ActivityItem> activities;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppTheme.cardRadius,
        border: Border.all(color: const Color(0xFF2A1A14)),
      ),
      child: isLoading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
            )
          : activities.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No recent activity', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                )
              : Column(
                  children: activities
                      .take(5)
                      .map((item) => _ActivityTile(item: item))
                      .toList(),
                ),
    );
  }
}

// FIX #2: empty-state card when no task is assigned
class _NoTaskCard extends StatelessWidget {
  const _NoTaskCard({required this.onDuty});

  final bool onDuty;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: Column(
          children: [
            Icon(
              onDuty ? Icons.check_circle_outline : Icons.pause_circle_outline,
              color: onDuty ? const Color(0xFF7CF29D) : Colors.white38,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              onDuty ? 'No task assigned' : 'Go on duty to receive tasks',
              style: TextStyle(
                color: onDuty ? Colors.white70 : Colors.white38,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (onDuty) ...[
              const SizedBox(height: 6),
              const Text(
                'Standing by — you will be notified when a task arrives.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssignedTaskCard extends StatelessWidget {
  const _AssignedTaskCard({
    required this.task,
    required this.isLoading,
    required this.onAccept,
    required this.onComplete,
  });

  final StaffTaskAssignment task;
  final bool isLoading;
  final VoidCallback onAccept;
  final VoidCallback onComplete;

  // FIX #3: full status colour map
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return const Color(0xFF8DF0A2);
      case 'assigned':
        return const Color(0xFFFFD54F); // amber
      case 'completed':
        return const Color(0xFF64B5F6); // blue
      case 'rejected':
        return const Color(0xFFEF9A9A); // red
      case 'pending':
        return Colors.white54;
      default:
        return Colors.white38;
    }
  }

  Color _statusBackground(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return const Color(0xFF1B5E20);
      case 'assigned':
        return const Color(0xFF4E3B00);
      case 'completed':
        return const Color(0xFF0D2B4E);
      case 'rejected':
        return const Color(0xFF4E0D0D);
      case 'pending':
        return const Color(0xFF2A2A2A);
      default:
        return AppColors.accent.withValues(alpha: 0.12);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAccepted = task.status.toLowerCase() == 'accepted';

    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppTheme.cardRadius,
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(task.incidentType), color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text(
                    'TASK ASSIGNED',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  // FIX #3: uses full colour map instead of binary accepted check
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusBackground(task.status),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      task.status.toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(task.status),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _line('Incident', task.incidentType),
              _line('Location', task.location),
              _line('Role', task.role),
              _line('Route', task.route),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: StandardButton(
                      label: isAccepted ? '✓ Accepted' : 'Accept Task',
                      onPressed: isLoading || isAccepted ? null : onAccept,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StandardButton(
                      label: 'Mark Completed',
                      isOutlined: true,
                      onPressed: isLoading ? null : onComplete,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('fire')) return Icons.local_fire_department;
    if (t.contains('medical')) return Icons.medical_services;
    if (t.contains('trapped')) return Icons.person_pin_circle_outlined;
    return Icons.warning_amber_rounded;
  }
}

// FIX #4: _RadioTile launches tel: URI via url_launcher
class _RadioTile extends StatelessWidget {
  const _RadioTile({required this.name, required this.number});

  final String name;
  final String number; // digits only, e.g. '+18000000001'

  Future<void> _dial() async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.phone, color: AppColors.accent),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        number,
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: const Icon(Icons.dialpad, color: AppColors.accent, size: 20),
      onTap: _dial,
    );
  }
}

// FIX #6: data class for Supabase-loaded safe zones
class _SafeZone {
  const _SafeZone({
    required this.zone,
    required this.location,
    required this.capacity,
    this.mapUrl,
  });

  final String zone;
  final String location;
  final String capacity;
  final String? mapUrl;
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.location,
    required this.capacity,
    required this.mapUrl,
  });

  final String zone;
  final String location;
  final String capacity;
  final String? mapUrl; // FIX #6: optional deep-link to map

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.shield, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                Text('$location • Capacity: $capacity',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          // FIX #6: map link icon when URL available
          if (mapUrl != null)
            IconButton(
              icon: const Icon(Icons.map_outlined,
                  color: AppColors.accent, size: 20),
              tooltip: 'View on map',
              onPressed: () async {
                final uri = Uri.parse(mapUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
    );
  }
}

class StaffTaskAssignment {
  const StaffTaskAssignment({
    required this.id,
    required this.incidentType,
    required this.location,
    required this.role,
    required this.route,
    required this.status,
  });

  final String id;
  final String incidentType;
  final String location;
  final String role;
  final String route;
  final String status;
}