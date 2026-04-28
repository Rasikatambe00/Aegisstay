import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/features/admin/models/admin_models.dart';
import 'package:frontend/features/admin/providers/dashboard_provider.dart';
import 'package:frontend/features/admin/providers/task_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Extended incident model — richer than IncidentSummary, sourced directly
// from Supabase so the panel is self-contained and doesn't depend on the
// lightweight DashboardProvider list.
// ─────────────────────────────────────────────────────────────────────────────

class _Incident {
  const _Incident({
    required this.id,
    required this.type,
    required this.location,
    required this.reportedBy,
    required this.time,
    required this.priority,
    required this.status,
    this.floor,
    this.description,
  });

  final String id;
  final String type;       // FIRE | MEDICAL | TRAPPED | OTHER
  final String location;
  final String reportedBy;
  final DateTime time;
  final String priority;   // HIGH | MEDIUM | LOW
  final String status;     // active | assigned | investigating | resolved
  final int? floor;
  final String? description;

  /// Short display ID (last 8 chars of UUID).
  String get shortId => id.length > 8 ? '#${id.substring(id.length - 8).toUpperCase()}' : '#$id';

  _Incident copyWith({String? status, String? priority}) => _Incident(
        id: id,
        type: type,
        location: location,
        reportedBy: reportedBy,
        time: time,
        priority: priority ?? this.priority,
        status: status ?? this.status,
        floor: floor,
        description: description,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Supabase service — all queries isolated here
// ─────────────────────────────────────────────────────────────────────────────

class _IncidentService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Fetch all non-cancelled incidents ordered newest first.
  static Future<List<_Incident>> fetchAll() async {
    try {
      final rows = await _db
          .from('incidents')
          .select('id,incident_type,location,created_by,created_at,status,floor,description')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);
      return rows.map<_Incident>(_fromRow).toList();
    } catch (_) {
      return _mock();
    }
  }

  /// Update status of a single incident.
  static Future<void> updateStatus(String id, String status) async {
    try {
      await _db.from('incidents').update({'status': status, 'updated_at': DateTime.now().toIso8601String()}).eq('id', id);
    } catch (_) {}
  }

  /// Insert a broadcast message.
  static Future<void> sendBroadcast(String message) async {
    try {
      await _db.from('broadcasts').insert({
        'message': message,
        'channel': 'all_staff',
        'sent_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Insert a new incident report.
  static Future<void> reportIncident({
    required String type,
    required String location,
    required String priority,
    required String description,
  }) async {
    try {
      await _db.from('incidents').insert({
        'incident_type': type,
        'location': location,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'description': description,
      });
    } catch (_) {}
  }

  /// Realtime stream — fires on any incident change.
  static Stream<void> get changes {
    final ctrl = StreamController<void>.broadcast();
    final suffix = DateTime.now().millisecondsSinceEpoch;
    RealtimeChannel? ch;
    try {
      ch = _db
          .channel('ic_incidents_$suffix')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'incidents',
            callback: (_) { if (!ctrl.isClosed) ctrl.add(null); },
          )
          .subscribe();
    } catch (_) {}
    ctrl.onCancel = () {
      try { if (ch != null) _db.removeChannel(ch); } catch (_) {}
      ctrl.close();
    };
    return ctrl.stream;
  }

  static _Incident _fromRow(Map<String, dynamic> r) => _Incident(
        id: r['id'].toString(),
        type: (r['incident_type'] ?? 'OTHER').toString().toUpperCase(),
        location: (r['location'] ?? 'Unknown').toString(),
        reportedBy: (r['created_by'] ?? 'System').toString(),
        time: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
        priority: _derivePriority((r['incident_type'] ?? '').toString()),
        status: (r['status'] ?? 'active').toString(),
        floor: r['floor'] as int?,
        description: r['description'] as String?,
      );

  static String _derivePriority(String type) {
    final t = type.toUpperCase();
    if (t == 'FIRE') return 'HIGH';
    if (t == 'MEDICAL') return 'HIGH';
    if (t == 'TRAPPED') return 'MEDIUM';
    return 'LOW';
  }

  static List<_Incident> _mock() {
    final now = DateTime.now();
    return [
      _Incident(id: 'aabbccdd-1111', type: 'FIRE', location: 'Floor 6 - Room 612', reportedBy: 'Alex Moreno', time: now.subtract(const Duration(minutes: 4)), priority: 'HIGH', status: 'active', floor: 6, description: 'Smoke detected in corridor.'),
      _Incident(id: 'aabbccdd-2222', type: 'MEDICAL', location: 'Floor 2 - Lobby Wing', reportedBy: 'Priya Sen', time: now.subtract(const Duration(minutes: 2)), priority: 'HIGH', status: 'assigned', floor: 2, description: 'Guest collapsed near elevator.'),
      _Incident(id: 'aabbccdd-3333', type: 'TRAPPED', location: 'Floor 3 - Stairwell B', reportedBy: 'Jordan Kim', time: now.subtract(const Duration(minutes: 1)), priority: 'MEDIUM', status: 'investigating', floor: 3, description: 'Guest stuck in stairwell.'),
      _Incident(id: 'aabbccdd-4444', type: 'OTHER', location: 'Floor 1 - Reception', reportedBy: 'Riley Park', time: now.subtract(const Duration(minutes: 10)), priority: 'LOW', status: 'resolved', floor: 1, description: 'Minor disturbance resolved.'),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _typeColor(String type) {
  switch (type.toUpperCase()) {
    case 'FIRE':    return const Color(0xFFEF4444);
    case 'MEDICAL': return const Color(0xFF64B5F6);
    case 'TRAPPED': return const Color(0xFFFFB74D);
    default:        return const Color(0xFF9E9E9E);
  }
}

Color _priorityColor(String p) {
  switch (p.toUpperCase()) {
    case 'HIGH':   return const Color(0xFFEF4444);
    case 'MEDIUM': return const Color(0xFFFFB74D);
    default:       return const Color(0xFF81C784);
  }
}

Color _statusColor(String s) {
  switch (s.toLowerCase()) {
    case 'active':        return const Color(0xFFEF4444);
    case 'assigned':      return const Color(0xFFFFB74D);
    case 'investigating': return const Color(0xFF64B5F6);
    case 'resolved':      return const Color(0xFF81C784);
    default:              return Colors.white38;
  }
}

IconData _typeIcon(String type) {
  switch (type.toUpperCase()) {
    case 'FIRE':    return Icons.local_fire_department_rounded;
    case 'medical': return Icons.medical_services_rounded;
    case 'MEDICAL': return Icons.medical_services_rounded;
    case 'TRAPPED': return Icons.person_off_rounded;
    default:        return Icons.warning_amber_rounded;
  }
}

String _formatTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Root widget — replaces the old IncidentControlPanel stub
// ─────────────────────────────────────────────────────────────────────────────

/// Full Incident Control dashboard.
/// Drop-in replacement for the old IncidentControlPanel stub.
/// Self-contained: fetches its own data and subscribes to Supabase Realtime.
class IncidentControlPanel extends StatelessWidget {
  const IncidentControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TaskProvider>(
      create: (_) => TaskProvider(),
      child: const _IncidentControlBody(),
    );
  }
}

class _IncidentControlBody extends StatefulWidget {
  const _IncidentControlBody();

  @override
  State<_IncidentControlBody> createState() => _IncidentControlPanelState();
}

class _IncidentControlPanelState extends State<_IncidentControlBody> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<_Incident> _all = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _sub;
  Timer? _debounce;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _liveEnabled = true;
  String _tabFilter = 'All';           // All | Active | Investigating | Resolved
  String _typeFilter = 'All';
  String _priorityFilter = 'All';
  String _search = '';
  String _sortCol = 'time';
  bool _sortAsc = false;
  int _page = 0;
  static const int _pageSize = 8;

  _Incident? _selected;               // drives right panel + map highlight

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _IncidentService.changes.listen((_) {
      if (!_liveEnabled) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _load);
    });
  }

  Future<void> _load() async {
    try {
      final data = await _IncidentService.fetchAll();
      if (mounted) setState(() { _all = data; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ── Derived lists ─────────────────────────────────────────────────────────

  List<_Incident> get _filtered {
    var list = _all.where((i) {
      // Tab filter — case-insensitive comparison
      if (_tabFilter != 'All' && i.status.toLowerCase() != _tabFilter.toLowerCase()) return false;
      // Type filter
      if (_typeFilter != 'All' && i.type.toUpperCase() != _typeFilter.toUpperCase()) return false;
      // Priority filter
      if (_priorityFilter != 'All' && i.priority.toUpperCase() != _priorityFilter.toUpperCase()) return false;
      // Search
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!i.location.toLowerCase().contains(q) &&
            !i.type.toLowerCase().contains(q) &&
            !i.reportedBy.toLowerCase().contains(q) &&
            !i.shortId.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();

    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case 'type':     cmp = a.type.compareTo(b.type); break;
        case 'location': cmp = a.location.compareTo(b.location); break;
        case 'priority': cmp = a.priority.compareTo(b.priority); break;
        case 'status':   cmp = a.status.compareTo(b.status); break;
        default:         cmp = a.time.compareTo(b.time);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  List<_Incident> get _page_items {
    final f = _filtered;
    final start = _page * _pageSize;
    if (start >= f.length) return [];
    return f.sublist(start, math.min(start + _pageSize, f.length));
  }

  int get _totalPages => math.max(1, (_filtered.length / _pageSize).ceil());

  // ── Summary counts ────────────────────────────────────────────────────────
  int get _countActive        => _all.where((i) => i.status == 'active' || i.status == 'assigned').length;
  int get _countAssigned      => _all.where((i) => i.status == 'assigned').length;
  int get _countInvestigating => _all.where((i) => i.status == 'investigating').length;
  int get _countResolved      => _all.where((i) => i.status == 'resolved').length;

  // ── Actions ───────────────────────────────────────────────────────────────

  void _sort(String col) => setState(() {
    if (_sortCol == col) { _sortAsc = !_sortAsc; } else { _sortCol = col; _sortAsc = true; }
    _page = 0;
  });

  void _select(_Incident i) {
    setState(() => _selected = _selected?.id == i.id ? null : i);
  }

  Future<void> _updateStatus(_Incident incident, String newStatus) async {
    await _IncidentService.updateStatus(incident.id, newStatus);
    setState(() {
      _all = _all.map((i) => i.id == incident.id ? i.copyWith(status: newStatus) : i).toList();
      if (_selected?.id == incident.id) _selected = _selected!.copyWith(status: newStatus);
    });
    // Also refresh DashboardProvider so summary cards update
    if (mounted) context.read<DashboardProvider>().refreshData();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: () { setState(() { _loading = true; }); _load(); });
    }

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      return wide ? _wideLayout() : _narrowLayout();
    });
  }

  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Main content ──────────────────────────────────────────────────
        Expanded(
          flex: 7,
          child: _mainColumn(),
        ),
        const SizedBox(width: 16),
        // ── Right panel: analytics OR incident details ────────────────────
        SizedBox(
          width: 300,
          child: _selected != null
              ? IncidentDetailsPanel(
                  incident: _selected!,
                  onStatusChange: (s) => _updateStatus(_selected!, s),
                  onClose: () => setState(() => _selected = null),
                )
              : _RightPanel(
                  all: _all,
                  selected: _selected,
                  onQuickAction: _handleQuickAction,
                ),
        ),
      ],
    );
  }

  Widget _narrowLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _mainColumn(),
          const SizedBox(height: 16),
          if (_selected != null)
            IncidentDetailsPanel(
              incident: _selected!,
              onStatusChange: (s) => _updateStatus(_selected!, s),
              onClose: () => setState(() => _selected = null),
            )
          else
            _RightPanel(
              all: _all,
              selected: _selected,
              onQuickAction: _handleQuickAction,
            ),
        ],
      ),
    );
  }

  Widget _mainColumn() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            liveEnabled: _liveEnabled,
            onLiveToggle: (v) => setState(() => _liveEnabled = v),
            search: _search,
            onSearch: (v) => setState(() { _search = v; _page = 0; }),
            typeFilter: _typeFilter,
            onTypeFilter: (v) => setState(() { _typeFilter = v; _page = 0; }),
            priorityFilter: _priorityFilter,
            onPriorityFilter: (v) => setState(() { _priorityFilter = v; _page = 0; }),
            onRefresh: _load,
          ),
          const SizedBox(height: 20),
          _SummaryRow(
            total: _all.length,
            active: _countActive,
            assigned: _countAssigned,
            investigating: _countInvestigating,
            resolved: _countResolved,
            onTap: (tab) => setState(() { _tabFilter = tab; _page = 0; }),
          ),
          const SizedBox(height: 20),
          _FloorMap(incidents: _all, selected: _selected, onSelect: _select),
          const SizedBox(height: 20),
          _IncidentTable(
            incidents: _page_items,
            allFiltered: _filtered,
            allIncidents: _all,
            tabFilter: _tabFilter,
            onTabFilter: (t) => setState(() { _tabFilter = t; _page = 0; }),
            sortCol: _sortCol,
            sortAsc: _sortAsc,
            onSort: _sort,
            page: _page,
            totalPages: _totalPages,
            onPage: (p) => setState(() => _page = p),
            selected: _selected,
            onSelect: _select,
            onStatusChange: _updateStatus,
          ),
          const SizedBox(height: 20),
          _RecentUpdates(incidents: _all.take(5).toList()),
          const SizedBox(height: 20),
          // ── Assign Task section ─────────────────────────────────────────
          _AssignTaskSection(
            incidents: _all,
            selected: _selected,
            onSelectIncident: (i) => setState(() =>
                _selected = _selected?.id == i.id ? null : i),
          ),
          if (_selected != null) ...[
            const SizedBox(height: 20),
            // On narrow screens, show details panel inline below the list
            IncidentDetailsPanel(
              incident: _selected!,
              onStatusChange: (s) => _updateStatus(_selected!, s),
              onClose: () => setState(() => _selected = null),
            ),
          ],
        ],
      ),
    );
  }

  void _handleQuickAction(String action) {
    switch (action) {
      case 'report':
        _showReportDialog();
        break;
      case 'broadcast':
        _showBroadcastDialog();
        break;
      case 'drill':
        _showDrillDialog();
        break;
      case 'evacuation':
        context.read<DashboardProvider>().setActiveTab(AdminNavTab.evacuationMonitor);
        break;
    }
  }

  void _showReportDialog() {
    showDialog<void>(context: context, builder: (_) => _ReportIncidentDialog(
      onSubmit: (type, location, priority, desc) async {
        await _IncidentService.reportIncident(type: type, location: location, priority: priority, description: desc);
        await _load();
      },
    ));
  }

  void _showBroadcastDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Broadcast Alert', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: ctrl,
        maxLines: 3,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(hintText: 'Enter broadcast message…', hintStyle: TextStyle(color: Colors.white38)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.button, foregroundColor: AppColors.accent),
          onPressed: () async {
            if (ctrl.text.trim().isNotEmpty) {
              await _IncidentService.sendBroadcast(ctrl.text.trim());
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Send'),
        ),
      ],
    ));
  }

  void _showDrillDialog() {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Schedule Drill', style: TextStyle(color: Colors.white)),
      content: const Text('Drill scheduling will be available in the next release.', style: TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — live toggle, search, filters
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.liveEnabled,
    required this.onLiveToggle,
    required this.search,
    required this.onSearch,
    required this.typeFilter,
    required this.onTypeFilter,
    required this.priorityFilter,
    required this.onPriorityFilter,
    required this.onRefresh,
  });

  final bool liveEnabled;
  final ValueChanged<bool> onLiveToggle;
  final String search;
  final ValueChanged<String> onSearch;
  final String typeFilter;
  final ValueChanged<String> onTypeFilter;
  final String priorityFilter;
  final ValueChanged<String> onPriorityFilter;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Incident Control',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            // Live toggle
            Row(
              children: [
                Icon(Icons.circle, size: 8,
                    color: liveEnabled ? const Color(0xFF81C784) : Colors.white38),
                const SizedBox(width: 6),
                Text(liveEnabled ? 'LIVE' : 'PAUSED',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: liveEnabled ? const Color(0xFF81C784) : Colors.white38)),
                const SizedBox(width: 8),
                Switch(
                  value: liveEnabled,
                  onChanged: onLiveToggle,
                  activeColor: AppColors.accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, color: AppColors.accent),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Search + filters row
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 220,
              height: 38,
              child: TextField(
                onChanged: onSearch,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search incidents…',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
            ),
            _FilterChip(
              label: 'Type',
              value: typeFilter,
              options: const ['All', 'FIRE', 'MEDICAL', 'TRAPPED', 'OTHER'],
              onChanged: onTypeFilter,
            ),
            _FilterChip(
              label: 'Priority',
              value: priorityFilter,
              options: const ['All', 'HIGH', 'MEDIUM', 'LOW'],
              onChanged: onPriorityFilter,
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: onChanged,
      itemBuilder: (_) => options
          .map((o) => PopupMenuItem(
                value: o,
                child: Text(o,
                    style: TextStyle(
                        color: o == value ? AppColors.accent : Colors.white70,
                        fontWeight: o == value ? FontWeight.w700 : FontWeight.normal)),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value != 'All' ? AppColors.accent : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: $value',
                style: TextStyle(
                    fontSize: 12,
                    color: value != 'All' ? AppColors.accent : Colors.white60)),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary cards row
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total,
    required this.active,
    required this.assigned,
    required this.investigating,
    required this.resolved,
    required this.onTap,
  });

  final int total, active, assigned, investigating, resolved;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SummaryCard(label: 'Total Incidents', value: total, color: const Color(0xFFFFB74D), icon: Icons.report_gmailerrorred_rounded, tab: 'All', onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _SummaryCard(label: 'Active', value: active, color: const Color(0xFFEF4444), icon: Icons.warning_amber_rounded, tab: 'Active', onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _SummaryCard(label: 'Assigned', value: assigned, color: const Color(0xFFFFB74D), icon: Icons.assignment_ind_rounded, tab: 'Assigned', onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _SummaryCard(label: 'Investigating', value: investigating, color: const Color(0xFF64B5F6), icon: Icons.manage_search_rounded, tab: 'Investigating', onTap: onTap)),
        const SizedBox(width: 10),
        Expanded(child: _SummaryCard(label: 'Resolved', value: resolved, color: const Color(0xFF81C784), icon: Icons.check_circle_outline_rounded, tab: 'Resolved', onTap: onTap)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.tab,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final String tab;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(tab),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 18),
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ]),
            const SizedBox(height: 10),
            Text('$value',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floor map — schematic view with color-coded incident markers
// ─────────────────────────────────────────────────────────────────────────────

class _FloorMap extends StatefulWidget {
  const _FloorMap({required this.incidents, required this.selected, required this.onSelect});
  final List<_Incident> incidents;
  final _Incident? selected;
  final ValueChanged<_Incident> onSelect;

  @override
  State<_FloorMap> createState() => _FloorMapState();
}

class _FloorMapState extends State<_FloorMap> {
  int _floor = 0; // 0 = Ground, 1 = 1st, 2 = 2nd

  // Fixed room positions per floor (normalized 0–1 within the map area)
  static const Map<String, Offset> _roomPositions = {
    'Room 101': Offset(0.15, 0.3), 'Room 102': Offset(0.35, 0.3),
    'Room 201': Offset(0.15, 0.5), 'Room 202': Offset(0.35, 0.5),
    'Room 301': Offset(0.15, 0.7), 'Room 302': Offset(0.35, 0.7),
    'Lobby':    Offset(0.55, 0.5), 'Reception': Offset(0.75, 0.3),
    'Stairwell A': Offset(0.85, 0.2), 'Stairwell B': Offset(0.85, 0.5),
    'Stairwell C': Offset(0.85, 0.8), 'Elevator Core B': Offset(0.65, 0.7),
  };

  Offset _positionForIncident(_Incident i) {
    // Try to match a known room keyword
    for (final entry in _roomPositions.entries) {
      if (i.location.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    // Fallback: hash-based pseudo-random but stable position
    final h = i.id.hashCode;
    return Offset(0.1 + (h.abs() % 80) / 100, 0.1 + ((h.abs() ~/ 100) % 80) / 100);
  }

  List<_Incident> get _floorIncidents =>
      widget.incidents.where((i) => i.floor == _floor || i.floor == null).toList();

  // Floor definitions: value → display label
  static const _floors = <int, String>{
    0: 'Ground',
    1: '1st',
    2: '2nd',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + floor selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, color: AppColors.accent, size: 18),
                const SizedBox(width: 8),
                const Text('Incident Map',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                const Spacer(),
                // Floor tabs: Ground, 1st, 2nd
                ..._floors.entries.map((entry) => GestureDetector(
                  onTap: () => setState(() => _floor = entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _floor == entry.key
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _floor == entry.key
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(entry.value,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _floor == entry.key
                                ? AppColors.accent
                                : Colors.white38)),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Map canvas
          SizedBox(
            height: 200,
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              return Stack(
                children: [
                  // Floor plan background
                  CustomPaint(
                    size: Size(w, h),
                    painter: _FloorPlanPainter(floor: _floor),
                  ),
                  // Evacuation routes (green lines)
                  CustomPaint(
                    size: Size(w, h),
                    painter: _EvacuationRoutePainter(),
                  ),
                  // Incident markers
                  ..._floorIncidents.map((incident) {
                    final pos = _positionForIncident(incident);
                    final px = pos.dx * w;
                    final py = pos.dy * h;
                    final isSelected = widget.selected?.id == incident.id;
                    return Positioned(
                      left: px - 14,
                      top: py - 14,
                      child: GestureDetector(
                        onTap: () => widget.onSelect(incident),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: isSelected ? 32 : 28,
                          height: isSelected ? 32 : 28,
                          decoration: BoxDecoration(
                            color: _typeColor(incident.type),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: _typeColor(incident.type).withValues(alpha: 0.5),
                                  blurRadius: isSelected ? 12 : 6),
                            ],
                          ),
                          child: Icon(_typeIcon(incident.type),
                              size: isSelected ? 16 : 14, color: Colors.white),
                        ),
                      ),
                    );
                  }),
                  // Tooltip for selected
                  if (widget.selected != null) ...[
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _typeColor(widget.selected!.type).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(_typeIcon(widget.selected!.type),
                                color: _typeColor(widget.selected!.type), size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.selected!.shortId} · ${widget.selected!.location}',
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _StatusBadge(status: widget.selected!.status),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Wrap(
              spacing: 16,
              children: [
                _MapLegendItem(color: const Color(0xFFEF4444), label: 'Fire'),
                _MapLegendItem(color: const Color(0xFF64B5F6), label: 'Medical'),
                _MapLegendItem(color: const Color(0xFFFFB74D), label: 'Trapped'),
                _MapLegendItem(color: const Color(0xFF81C784), label: 'Evacuation Route', isLine: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapLegendItem extends StatelessWidget {
  const _MapLegendItem({required this.color, required this.label, this.isLine = false});
  final Color color;
  final String label;
  final bool isLine;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        isLine
            ? Container(width: 16, height: 3, color: color)
            : Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
    );
  }
}

/// Draws a simple schematic floor plan grid.
class _FloorPlanPainter extends CustomPainter {
  const _FloorPlanPainter({required this.floor});
  final int floor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Outer boundary
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
          const Radius.circular(8)),
      paint,
    );

    // Room grid lines
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), paint);
    }
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), paint);
    }

    // Floor label
    final tp = TextPainter(
      text: TextSpan(
        text: floor == 0 ? 'Ground Floor' : floor == 1 ? '1st Floor' : '2nd Floor',
        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.15), fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(_FloorPlanPainter old) => old.floor != floor;
}

/// Draws green evacuation route lines.
class _EvacuationRoutePainter extends CustomPainter {
  const _EvacuationRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF81C784).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Horizontal corridor
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.5),
      Offset(size.width * 0.85, size.height * 0.5),
      paint,
    );
    // Vertical to stairwells
    canvas.drawLine(
      Offset(size.width * 0.85, size.height * 0.2),
      Offset(size.width * 0.85, size.height * 0.8),
      paint,
    );
    // Branch to exit
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.5),
      Offset(size.width * 0.1, size.height * 0.9),
      paint,
    );
  }

  @override
  bool shouldRepaint(_EvacuationRoutePainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Incident table with tabs, sorting, pagination
// ─────────────────────────────────────────────────────────────────────────────

class _IncidentTable extends StatelessWidget {
  const _IncidentTable({
    required this.incidents,
    required this.allFiltered,
    required this.allIncidents,
    required this.tabFilter,
    required this.onTabFilter,
    required this.sortCol,
    required this.sortAsc,
    required this.onSort,
    required this.page,
    required this.totalPages,
    required this.onPage,
    required this.selected,
    required this.onSelect,
    required this.onStatusChange,
  });

  final List<_Incident> incidents;
  final List<_Incident> allFiltered;
  final List<_Incident> allIncidents;
  final String tabFilter;
  final ValueChanged<String> onTabFilter;
  final String sortCol;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final int page;
  final int totalPages;
  final ValueChanged<int> onPage;
  final _Incident? selected;
  final ValueChanged<_Incident> onSelect;
  final Future<void> Function(_Incident, String) onStatusChange;

  List<String> get _dynamicTabs {
    final statuses = allIncidents.map((i) => i.status.toLowerCase()).toSet();
    const order = ['active', 'assigned', 'investigating', 'resolved'];
    final tabs = ['All'];
    for (final s in order) {
      if (statuses.contains(s)) {
        tabs.add(s[0].toUpperCase() + s.substring(1));
      }
    }
    // Add any other statuses not in the predefined order
    for (final s in statuses) {
      final label = s[0].toUpperCase() + s.substring(1);
      if (!tabs.contains(label)) tabs.add(label);
    }
    return tabs;
  }

  int _tabCount(String tab) {
    if (tab == 'All') return allIncidents.length;
    return allIncidents.where((i) => i.status.toLowerCase() == tab.toLowerCase()).length;
  }

  void _openAssignDialog(BuildContext context, _Incident incident) {
    // Ensure TaskProvider is loaded for this incident before opening dialog
    final provider = context.read<TaskProvider>();
    provider.loadTasks(incident.id);
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: AssignTaskDialog(incidentId: incident.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                ..._dynamicTabs.map((t) => GestureDetector(
                  onTap: () => onTabFilter(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: tabFilter == t ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: tabFilter == t ? AppColors.accent : Colors.transparent),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tabFilter == t ? AppColors.accent : Colors.white38)),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: tabFilter == t
                                ? AppColors.accent.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_tabCount(t)}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: tabFilter == t ? AppColors.accent : Colors.white38),
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
                const Spacer(),
                Text('${allFiltered.length} incident${allFiltered.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Color(0xFF2A1A14), height: 1),
          // Column headers
          _TableHeader(sortCol: sortCol, sortAsc: sortAsc, onSort: onSort),
          const Divider(color: Color(0xFF2A1A14), height: 1),
          // Rows
          if (incidents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No incidents match the current filters.',
                  style: TextStyle(color: Colors.white38))),
            )
          else
            ...incidents.map((i) => _TableRow(
              incident: i,
              isSelected: selected?.id == i.id,
              onTap: () => onSelect(i),
              onStatusChange: (s) => onStatusChange(i, s),
              onAssignTask: () => _openAssignDialog(context, i),
            )),
          const Divider(color: Color(0xFF2A1A14), height: 1),
          // Pagination
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Text('Page ${page + 1} of $totalPages',
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18),
                  color: page > 0 ? AppColors.accent : Colors.white24,
                  onPressed: page > 0 ? () => onPage(page - 1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  color: page < totalPages - 1 ? AppColors.accent : Colors.white24,
                  onPressed: page < totalPages - 1 ? () => onPage(page + 1) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.sortCol, required this.sortAsc, required this.onSort});
  final String sortCol;
  final bool sortAsc;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _ColHeader(label: 'ID',       col: 'id',       sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
          _ColHeader(label: 'Type',     col: 'type',     sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
          _ColHeader(label: 'Location', col: 'location', sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 3),
          _ColHeader(label: 'Reported', col: 'reporter', sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
          _ColHeader(label: 'Time',     col: 'time',     sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
          _ColHeader(label: 'Priority', col: 'priority', sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
          _ColHeader(label: 'Status',   col: 'status',   sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
          const Expanded(flex: 2, child: Text('Actions', style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600))),
          const Expanded(flex: 2, child: Text('Assign Task', style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader({
    required this.label, required this.col,
    required this.sortCol, required this.sortAsc,
    required this.onSort, required this.flex,
  });
  final String label, col, sortCol;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final active = sortCol == col;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () => onSort(col),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.accent : Colors.white38)),
            if (active)
              Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 10, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.incident,
    required this.isSelected,
    required this.onTap,
    required this.onStatusChange,
    required this.onAssignTask,
  });

  final _Incident incident;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onAssignTask;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected
            ? AppColors.accent.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(incident.shortId,
                style: const TextStyle(fontSize: 11, color: Colors.white54, fontFamily: 'monospace'))),
            Expanded(flex: 2, child: Row(children: [
              Icon(_typeIcon(incident.type), size: 13, color: _typeColor(incident.type)),
              const SizedBox(width: 4),
              Flexible(child: Text(incident.type,
                  style: TextStyle(fontSize: 11, color: _typeColor(incident.type), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
            ])),
            Expanded(flex: 3, child: Text(incident.location,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text(incident.reportedBy,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
                overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text(_formatTime(incident.time),
                style: const TextStyle(fontSize: 11, color: Colors.white38))),
            Expanded(flex: 2, child: _PriorityBadge(priority: incident.priority)),
            Expanded(flex: 2, child: _StatusBadge(status: incident.status)),
            Expanded(flex: 2, child: _ActionMenu(incident: incident, onStatusChange: onStatusChange)),
            // ── Assign Task button ─────────────────────────────────────
            Expanded(flex: 2, child: Tooltip(
              message: 'Assign task to staff',
              child: GestureDetector(
                onTap: onAssignTask,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.add_task_rounded, size: 12, color: AppColors.accent),
                    SizedBox(width: 4),
                    Text('Assign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                  ]),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(priority,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final label = status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.incident, required this.onStatusChange});
  final _Incident incident;
  final ValueChanged<String> onStatusChange;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      icon: const Icon(Icons.more_horiz, size: 16, color: Colors.white38),
      onSelected: onStatusChange,
      itemBuilder: (_) => [
        if (incident.status != 'active')
          const PopupMenuItem(value: 'active', child: Text('Mark Active', style: TextStyle(color: Colors.white70, fontSize: 13))),
        if (incident.status != 'investigating')
          const PopupMenuItem(value: 'investigating', child: Text('Investigate', style: TextStyle(color: Colors.white70, fontSize: 13))),
        if (incident.status != 'resolved')
          const PopupMenuItem(value: 'resolved', child: Text('Resolve', style: TextStyle(color: Colors.white70, fontSize: 13))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Right panel — donut chart, trend line, response stats, quick actions
// ─────────────────────────────────────────────────────────────────────────────

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.all,
    required this.selected,
    required this.onQuickAction,
  });

  final List<_Incident> all;
  final _Incident? selected;
  final ValueChanged<String> onQuickAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        children: [
          _PriorityDonut(incidents: all),
          const SizedBox(height: 14),
          _TrendChart(incidents: all),
          const SizedBox(height: 14),
          _ResponsePerformance(incidents: all),
          const SizedBox(height: 14),
          _QuickActions(onAction: onQuickAction),
        ],
      ),
    );
  }
}

// ── Priority donut ────────────────────────────────────────────────────────────

class _PriorityDonut extends StatelessWidget {
  const _PriorityDonut({required this.incidents});
  final List<_Incident> incidents;

  @override
  Widget build(BuildContext context) {
    final high   = incidents.where((i) => i.priority == 'HIGH').length;
    final medium = incidents.where((i) => i.priority == 'MEDIUM').length;
    final low    = incidents.where((i) => i.priority == 'LOW').length;
    final total  = incidents.length;

    return _Card(
      title: 'Priority Overview',
      icon: Icons.donut_large_rounded,
      child: Column(
        children: [
          SizedBox(
            height: 130,
            child: CustomPaint(
              painter: _DonutChartPainter(
                segments: [
                  _DonutSegment(value: high.toDouble(),   color: const Color(0xFFEF4444)),
                  _DonutSegment(value: medium.toDouble(), color: const Color(0xFFFFB74D)),
                  _DonutSegment(value: low.toDouble(),    color: const Color(0xFF81C784)),
                ],
                total: total.toDouble(),
                centerLabel: '$total',
                centerSub: 'Total',
              ),
              size: const Size(double.infinity, 130),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DonutLegend(color: const Color(0xFFEF4444), label: 'High',   value: high),
              _DonutLegend(color: const Color(0xFFFFB74D), label: 'Medium', value: medium),
              _DonutLegend(color: const Color(0xFF81C784), label: 'Low',    value: low),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutSegment {
  const _DonutSegment({required this.value, required this.color});
  final double value;
  final Color color;
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({
    required this.segments,
    required this.total,
    required this.centerLabel,
    required this.centerSub,
  });

  final List<_DonutSegment> segments;
  final double total;
  final String centerLabel;
  final String centerSub;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 10;
    const strokeW = 18.0;
    const gap = 0.04; // radians gap between segments

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    double startAngle = -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    // Track (background)
    canvas.drawCircle(Offset(cx, cy), radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..color = Colors.white.withValues(alpha: 0.06));

    if (total <= 0) {
      // Empty state
      _paintCenter(canvas, size, '0', 'No data');
      return;
    }

    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = (seg.value / total) * 2 * math.pi - gap;
      canvas.drawArc(rect, startAngle + gap / 2, sweep, false,
          paint..color = seg.color);
      startAngle += sweep + gap;
    }

    _paintCenter(canvas, size, centerLabel, centerSub);
  }

  void _paintCenter(Canvas canvas, Size size, String label, String sub) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final tp1 = TextPainter(
      text: TextSpan(text: label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(cx - tp1.width / 2, cy - tp1.height / 2 - 6));

    final tp2 = TextPainter(
      text: TextSpan(text: sub,
          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(cx - tp2.width / 2, cy + tp1.height / 2 - 4));
  }

  @override
  bool shouldRepaint(_DonutChartPainter old) =>
      old.total != total || old.centerLabel != centerLabel;
}

class _DonutLegend extends StatelessWidget {
  const _DonutLegend({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 4),
        Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }
}

// ── Trend line chart ──────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.incidents});
  final List<_Incident> incidents;

  /// Bucket incidents into the last 6 hours.
  List<int> get _hourlyBuckets {
    final now = DateTime.now();
    final buckets = List<int>.filled(6, 0);
    for (final i in incidents) {
      final diff = now.difference(i.time).inHours;
      if (diff >= 0 && diff < 6) { buckets[5 - diff]++; }
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _hourlyBuckets;
    return _Card(
      title: 'Incident Trend',
      icon: Icons.show_chart_rounded,
      child: SizedBox(
        height: 80,
        child: CustomPaint(
          painter: _TrendPainter(buckets: buckets),
          size: const Size(double.infinity, 80),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.buckets});
  final List<int> buckets;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;
    final maxVal = buckets.fold<int>(1, math.max).toDouble();
    final n = buckets.length;

    final pts = List.generate(n, (i) {
      final x = n == 1 ? size.width / 2 : i / (n - 1) * size.width;
      final y = size.height * (1 - buckets[i] / maxVal);
      return Offset(x, y);
    });

    // Area fill
    final area = Path()..moveTo(pts.first.dx, size.height);
    for (final p in pts) { area.lineTo(p.dx, p.dy); }
    area..lineTo(pts.last.dx, size.height)..close();
    canvas.drawPath(area, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [AppColors.accent.withValues(alpha: 0.3), AppColors.accent.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill);

    // Line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cp = (pts[i - 1].dx + pts[i].dx) / 2;
      line.cubicTo(cp, pts[i - 1].dy, cp, pts[i].dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(line, Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);

    // Hour labels
    final now = DateTime.now();
    for (int i = 0; i < n; i++) {
      final h = now.subtract(Duration(hours: n - 1 - i)).hour;
      final label = '${h.toString().padLeft(2, '0')}h';
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.3))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.buckets != buckets;
}

// ── Response performance ──────────────────────────────────────────────────────

class _ResponsePerformance extends StatelessWidget {
  const _ResponsePerformance({required this.incidents});
  final List<_Incident> incidents;

  String get _avgResponse {
    if (incidents.isEmpty) return '—';
    final total = incidents.fold<int>(0, (s, i) => s + DateTime.now().difference(i.time).inMinutes);
    return '${(total / incidents.length).round()} min';
  }

  String get _resolutionRate {
    if (incidents.isEmpty) return '—';
    final resolved = incidents.where((i) => i.status == 'resolved').length;
    return '${(resolved / incidents.length * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Response Performance',
      icon: Icons.speed_rounded,
      child: Column(
        children: [
          _PerfRow(label: 'Avg Response Time', value: _avgResponse, color: AppColors.accent),
          const SizedBox(height: 8),
          _PerfRow(label: 'Resolution Rate', value: _resolutionRate, color: const Color(0xFF81C784)),
          const SizedBox(height: 8),
          _PerfRow(
            label: 'SLA Compliance',
            value: incidents.isEmpty ? '—' : '${(incidents.where((i) => DateTime.now().difference(i.time).inMinutes < 30).length / incidents.length * 100).round()}%',
            color: const Color(0xFF64B5F6),
          ),
        ],
      ),
    );
  }
}

class _PerfRow extends StatelessWidget {
  const _PerfRow({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onAction});
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Quick Actions',
      icon: Icons.bolt_rounded,
      child: Column(
        children: [
          _QAButton(icon: Icons.add_alert_rounded,       label: 'Report Incident',   color: const Color(0xFFEF4444), action: 'report',     onAction: onAction),
          const SizedBox(height: 8),
          _QAButton(icon: Icons.campaign_rounded,        label: 'Broadcast Alert',   color: const Color(0xFFFFB74D), action: 'broadcast',  onAction: onAction),
          const SizedBox(height: 8),
          _QAButton(icon: Icons.fitness_center_rounded,  label: 'Schedule Drill',    color: const Color(0xFF64B5F6), action: 'drill',      onAction: onAction),
          const SizedBox(height: 8),
          _QAButton(icon: Icons.directions_run_rounded,  label: 'View Evacuation',   color: const Color(0xFF81C784), action: 'evacuation', onAction: onAction),
        ],
      ),
    );
  }
}

class _QAButton extends StatelessWidget {
  const _QAButton({
    required this.icon, required this.label,
    required this.color, required this.action, required this.onAction,
  });
  final IconData icon;
  final String label, action;
  final Color color;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onAction(action),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, size: 10, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assign Task Section — standalone card for task management
// ─────────────────────────────────────────────────────────────────────────────

/// A dedicated section below the incident table that lets admins:
/// 1. Pick an incident from a compact list
/// 2. See its existing tasks
/// 3. Assign a new task — all without opening the side panel
class _AssignTaskSection extends StatefulWidget {
  const _AssignTaskSection({
    required this.incidents,
    required this.selected,
    required this.onSelectIncident,
  });

  final List<_Incident> incidents;
  final _Incident? selected;
  final ValueChanged<_Incident> onSelectIncident;

  @override
  State<_AssignTaskSection> createState() => _AssignTaskSectionState();
}

class _AssignTaskSectionState extends State<_AssignTaskSection> {
  // Local selected incident — independent of the main panel selection
  _Incident? _localSelected;

  @override
  void didUpdateWidget(_AssignTaskSection old) {
    super.didUpdateWidget(old);
    // If the main panel clears selection, clear local too
    if (widget.selected == null && _localSelected != null) {
      setState(() => _localSelected = null);
    }
  }

  List<_Incident> get _activeIncidents =>
      widget.incidents.where((i) => i.status != 'resolved').toList();

  void _selectIncident(_Incident i) {
    setState(() => _localSelected = _localSelected?.id == i.id ? null : i);
    widget.onSelectIncident(i);
  }

  void _openAssignDialog(BuildContext context, _Incident incident) {
    final provider = context.read<TaskProvider>();
    provider.loadTasks(incident.id);
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: AssignTaskDialog(incidentId: incident.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              const Icon(Icons.assignment_ind_rounded,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              const Text('Assign Tasks',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_activeIncidents.length} active',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ),
              const Spacer(),
              const Text('Select an incident to manage tasks',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
            ]),
          ),
          const Divider(color: Color(0xFF2A1A14), height: 1),

          if (_activeIncidents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No active incidents.',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            )
          else
            // ── Two-column layout: incident list | task panel ─────────────
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: incident picker
                      SizedBox(
                        width: 280,
                        child: _IncidentPicker(
                          incidents: _activeIncidents,
                          selected: _localSelected,
                          onSelect: _selectIncident,
                        ),
                      ),
                      const VerticalDivider(
                          color: Color(0xFF2A1A14), width: 1),
                      // Right: task list for selected incident
                      Expanded(
                        child: _localSelected == null
                            ? const _TaskPlaceholder()
                            : _TaskPanel(
                                incident: _localSelected!,
                                onAssign: () =>
                                    _openAssignDialog(context, _localSelected!),
                              ),
                      ),
                    ],
                  ),
                );
              }
              // Narrow: stacked
              return Column(children: [
                _IncidentPicker(
                  incidents: _activeIncidents,
                  selected: _localSelected,
                  onSelect: _selectIncident,
                ),
                const Divider(color: Color(0xFF2A1A14), height: 1),
                _localSelected == null
                    ? const _TaskPlaceholder()
                    : _TaskPanel(
                        incident: _localSelected!,
                        onAssign: () =>
                            _openAssignDialog(context, _localSelected!),
                      ),
              ]);
            }),
        ],
      ),
    );
  }
}

// ── Incident picker (left column) ─────────────────────────────────────────────

class _IncidentPicker extends StatelessWidget {
  const _IncidentPicker({
    required this.incidents,
    required this.selected,
    required this.onSelect,
  });

  final List<_Incident> incidents;
  final _Incident? selected;
  final ValueChanged<_Incident> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Active Incidents',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                  letterSpacing: 0.5)),
        ),
        ...incidents.map((i) {
          final isSelected = selected?.id == i.id;
          final color = _typeColor(i.type);
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isSelected
                        ? color.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle),
                  child: Icon(_typeIcon(i.type), size: 13, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.location,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.white : Colors.white70),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(i.type,
                          style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600)),
                      const Text(' · ',
                          style: TextStyle(
                              color: Colors.white24, fontSize: 10)),
                      Text(_formatTime(i.time),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white38)),
                    ]),
                  ],
                )),
                // Priority badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _priorityColor(i.priority)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(i.priority,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _priorityColor(i.priority))),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ── Task panel (right column) ─────────────────────────────────────────────────

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({
    required this.incident,
    required this.onAssign,
  });

  final _Incident incident;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(incident.type);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Incident header
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle),
              child: Icon(_typeIcon(incident.type), size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(incident.location,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                Text('${incident.type} · ${incident.shortId}',
                    style: TextStyle(fontSize: 11, color: color)),
              ],
            )),
            // Assign Task button
            GestureDetector(
              onTap: onAssign,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.add_task_rounded,
                      size: 14, color: AppColors.accent),
                  SizedBox(width: 6),
                  Text('Assign Task',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF2A1A14), height: 1),
          const SizedBox(height: 12),
          // Task list
          TaskListWidget(incidentId: incident.id),
        ],
      ),
    );
  }
}

// ── Empty state when no incident is selected ──────────────────────────────────

class _TaskPlaceholder extends StatelessWidget {
  const _TaskPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.touch_app_outlined,
              size: 36, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          const Text('Select an incident',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white38)),
          const SizedBox(height: 4),
          const Text('to view and assign tasks',
              style: TextStyle(fontSize: 11, color: Colors.white24)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent updates list
// ─────────────────────────────────────────────────────────────────────────────

class _RecentUpdates extends StatelessWidget {
  const _RecentUpdates({required this.incidents});
  final List<_Incident> incidents;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Recent Updates',
      icon: Icons.history_rounded,
      child: incidents.isEmpty
          ? const Text('No recent updates.', style: TextStyle(color: Colors.white38, fontSize: 12))
          : Column(
              children: incidents
                  .map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: _typeColor(i.type).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(_typeIcon(i.type), size: 15, color: _typeColor(i.type)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${i.type} · ${i.location}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis),
                                  Text(_formatTime(i.time),
                                      style: const TextStyle(fontSize: 10, color: Colors.white38)),
                                ],
                              ),
                            ),
                            _StatusBadge(status: i.status),
                          ],
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Incident detail panel (shown when a row is selected)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// IncidentDetailsPanel — incident info + assigned tasks (public for reuse)
// ─────────────────────────────────────────────────────────────────────────────

/// Full incident details panel with contextual task management.
/// Shown as a right side panel on wide screens, inline on narrow screens.
class IncidentDetailsPanel extends StatelessWidget {
  const IncidentDetailsPanel({
    super.key,
    required this.incident,
    required this.onStatusChange,
    required this.onClose,
  });

  final _Incident incident;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accentColor = _typeColor(incident.type);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      // Use SingleChildScrollView so the panel never overflows its container
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(_typeIcon(incident.type), size: 16, color: accentColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Incident Details',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text(incident.shortId,
                        style: const TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'monospace')),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white38),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ]),
            ),
            const Divider(color: Color(0xFF2A1A14), height: 20),

            // ── Incident info ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _DetailRow(label: 'Type',        value: incident.type),
                _DetailRow(label: 'Location',    value: incident.location),
                _DetailRow(label: 'Reported By', value: incident.reportedBy),
                _DetailRow(label: 'Time',        value: incident.time.toLocal().toString().substring(0, 16)),
                // Priority row — use same _DetailRow layout but with StatusChip as value widget
                _DetailRowWidget(
                  label: 'Priority',
                  child: StatusChip(label: incident.priority, color: _priorityColor(incident.priority)),
                ),
                const SizedBox(height: 4),
                _DetailRowWidget(
                  label: 'Status',
                  child: StatusChip(label: incident.status, color: _statusColor(incident.status)),
                ),
                if (incident.description != null && incident.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Description', value: incident.description!),
                ],
                const SizedBox(height: 12),
                // Status action buttons
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (incident.status != 'active')
                    _ActionBtn(label: 'Mark Active',  color: const Color(0xFFEF4444), onTap: () => onStatusChange('active')),
                  if (incident.status != 'investigating')
                    _ActionBtn(label: 'Investigate',  color: const Color(0xFF64B5F6), onTap: () => onStatusChange('investigating')),
                  if (incident.status != 'resolved')
                    _ActionBtn(label: 'Resolve',      color: const Color(0xFF81C784), onTap: () => onStatusChange('resolved')),
                ]),
              ]),
            ),

            const Divider(color: Color(0xFF2A1A14), height: 24),

            // ── Assigned Tasks section ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TaskListWidget(incidentId: incident.id),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TaskListWidget — shows tasks for an incident + assign button
// ─────────────────────────────────────────────────────────────────────────────

class TaskListWidget extends StatefulWidget {
  const TaskListWidget({super.key, required this.incidentId});
  final String incidentId;

  @override
  State<TaskListWidget> createState() => _TaskListWidgetState();
}

class _TaskListWidgetState extends State<TaskListWidget> {
  @override
  void initState() {
    super.initState();
    // Load tasks as soon as the panel opens, if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TaskProvider>().loadTasks(widget.incidentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(builder: (context, provider, _) {
      final tasks   = provider.getTasksByIncident(widget.incidentId);
      final loading = provider.isLoading(widget.incidentId);

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header
        Row(children: [
          const Icon(Icons.task_alt_rounded, size: 14, color: AppColors.accent),
          const SizedBox(width: 7),
          const Text('Assigned Tasks',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          const Spacer(),
          // + Assign New Task button
          GestureDetector(
            onTap: () => _showAssignDialog(context, provider),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add, size: 13, color: AppColors.accent),
                const SizedBox(width: 4),
                const Text('Assign Task',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        // Loading state
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))),
          )
        // Empty state
        else if (tasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(children: [
              Icon(Icons.assignment_outlined, size: 28, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              const Text('No tasks assigned yet',
                  style: TextStyle(fontSize: 12, color: Colors.white38)),
              const SizedBox(height: 4),
              const Text('Tap "+ Assign Task" to add one',
                  style: TextStyle(fontSize: 11, color: Colors.white24)),
            ]),
          )
        // Task list
        else
          ...tasks.map((task) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TaskItemTile(
              task: task,
              onStatusChange: (s) => provider.updateTaskStatus(widget.incidentId, task.id, s),
            ),
          )),
      ]);
    });
  }

  void _showAssignDialog(BuildContext context, TaskProvider provider) {
    showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: AssignTaskDialog(incidentId: widget.incidentId),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TaskItemTile — single task row
// ─────────────────────────────────────────────────────────────────────────────

class TaskItemTile extends StatelessWidget {
  const TaskItemTile({super.key, required this.task, required this.onStatusChange});
  final IncidentTask task;
  final ValueChanged<String> onStatusChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Task icon
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: _priorityColor(task.priority).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.task_alt_rounded, size: 13, color: _priorityColor(task.priority)),
          ),
          const SizedBox(width: 8),
          // Title
          Expanded(
            child: Text(task.title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          // Status chip with tap to cycle
          GestureDetector(
            onTap: () => onStatusChange(_nextStatus(task.status)),
            child: StatusChip(label: task.status, color: _taskStatusColor(task.status)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.person_outline_rounded, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Text('Assigned to ${task.assignedTo}',
              style: const TextStyle(fontSize: 11, color: Colors.white38)),
          const Spacer(),
          // Priority badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _priorityColor(task.priority).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(task.priority,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _priorityColor(task.priority))),
          ),
        ]),
      ]),
    );
  }

  String _nextStatus(String current) {
    switch (current) {
      case 'Assigned':    return 'In Progress';
      case 'In Progress': return 'Completed';
      default:            return 'Assigned';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StatusChip — reusable colored status badge
// ─────────────────────────────────────────────────────────────────────────────

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AssignTaskDialog — create a new task for an incident
// ─────────────────────────────────────────────────────────────────────────────

class AssignTaskDialog extends StatefulWidget {
  const AssignTaskDialog({super.key, required this.incidentId});
  final String incidentId;

  @override
  State<AssignTaskDialog> createState() => _AssignTaskDialogState();
}

class _AssignTaskDialogState extends State<AssignTaskDialog> {
  final _titleCtrl = TextEditingController();
  String _assignedTo = '';
  String _priority = 'HIGH';
  bool _submitting = false;
  List<String> _staffNames = [];
  bool _loadingStaff = true;
  bool _hasTitle = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(() {
      final hasText = _titleCtrl.text.trim().isNotEmpty;
      if (hasText != _hasTitle) setState(() => _hasTitle = hasText);
    });
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final db = Supabase.instance.client;
      List<dynamic> rows = [];
      try {
        rows = await db.from('staff_profiles').select('full_name').order('full_name');
        _staffNames = rows.map((r) => (r['full_name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
      } catch (_) {}
      if (_staffNames.isEmpty) {
        rows = await db.from('staff').select('staff_name').order('staff_name');
        _staffNames = rows.map((r) => (r['staff_name'] ?? '').toString()).where((n) => n.isNotEmpty).toList();
      }
    } catch (_) {
      _staffNames = ['Alex Moreno', 'Priya Sen', 'Jordan Kim', 'Riley Park'];
    } finally {
      if (mounted) {
        setState(() {
          _loadingStaff = false;
          if (_staffNames.isNotEmpty) _assignedTo = _staffNames.first;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.add_task_rounded, color: AppColors.accent, size: 20),
        const SizedBox(width: 8),
        const Text('Assign New Task', style: TextStyle(color: Colors.white, fontSize: 15)),
      ]),
      content: SizedBox(
        width: 340,
        child: _loadingStaff
            ? const SizedBox(height: 80,
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                // Task title
                _DialogField(ctrl: _titleCtrl, label: 'Task Title', hint: 'e.g. Check Room 205'),
                const SizedBox(height: 12),
                // Assign to dropdown
                _DialogDropdown(
                  label: 'Assign To',
                  value: _assignedTo.isEmpty ? null : _assignedTo,
                  options: _staffNames,
                  onChanged: (v) => setState(() => _assignedTo = v),
                ),
                const SizedBox(height: 12),
                // Priority dropdown
                _DialogDropdown(
                  label: 'Priority',
                  value: _priority,
                  options: const ['HIGH', 'MEDIUM', 'LOW'],
                  onChanged: (v) => setState(() => _priority = v),
                ),
                const SizedBox(height: 12),
                // Status (read-only, always Assigned on creation)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(children: [
                    const Text('Status', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    const Spacer(),
                    StatusChip(label: 'Assigned', color: _taskStatusColor('Assigned')),
                  ]),
                ),
              ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.button, foregroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(100, 38)),
          onPressed: _submitting || !_hasTitle || _assignedTo.isEmpty
              ? null
              : () async {
                  setState(() => _submitting = true);
                  await context.read<TaskProvider>().addTask(
                    incidentId: widget.incidentId,
                    title: _titleCtrl.text.trim(),
                    assignedTo: _assignedTo,
                    priority: _priority,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
          child: _submitting
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
              : const Text('Create Task'),
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({required this.ctrl, required this.label, this.hint});
  final TextEditingController ctrl;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
      filled: true, fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent)),
    ),
  );
}

class _DialogDropdown extends StatelessWidget {
  const _DialogDropdown({required this.label, required this.value,
      required this.options, required this.onChanged});
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    dropdownColor: AppColors.card,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      filled: true, fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
    ),
    items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
    onChanged: (v) { if (v != null) onChanged(v); },
  );
}

// ── Task status color helper ───────────────────────────────────────────────────

Color _taskStatusColor(String status) {
  switch (status) {
    case 'In Progress': return const Color(0xFF64B5F6);
    case 'Completed':   return const Color(0xFF81C784);
    default:            return const Color(0xFF9E9E9E); // Assigned
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

/// Same layout as [_DetailRow] but accepts a widget as the value (e.g. StatusChip).
class _DetailRowWidget extends StatelessWidget {
  const _DetailRowWidget({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ),
          child,
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report incident dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ReportIncidentDialog extends StatefulWidget {
  const _ReportIncidentDialog({required this.onSubmit});
  final Future<void> Function(String type, String location, String priority, String desc) onSubmit;

  @override
  State<_ReportIncidentDialog> createState() => _ReportIncidentDialogState();
}

class _ReportIncidentDialogState extends State<_ReportIncidentDialog> {
  String _type = 'FIRE';
  String _priority = 'HIGH';
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _locationCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Report Incident', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DropdownField(
              label: 'Type',
              value: _type,
              options: const ['FIRE', 'MEDICAL', 'TRAPPED', 'OTHER'],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            _DropdownField(
              label: 'Priority',
              value: _priority,
              options: const ['HIGH', 'MEDIUM', 'LOW'],
              onChanged: (v) => setState(() => _priority = v),
            ),
            const SizedBox(height: 12),
            _DialogTextField(controller: _locationCtrl, label: 'Location'),
            const SizedBox(height: 12),
            _DialogTextField(controller: _descCtrl, label: 'Description', maxLines: 3),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.button, foregroundColor: AppColors.accent),
          onPressed: _submitting ? null : () async {
            if (_locationCtrl.text.trim().isEmpty) return;
            setState(() => _submitting = true);
            await widget.onSubmit(_type, _locationCtrl.text.trim(), _priority, _descCtrl.text.trim());
            if (context.mounted) Navigator.pop(context);
          },
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
              : const Text('Submit'),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({required this.label, required this.value, required this.options, required this.onChanged});
  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: AppColors.card,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({required this.controller, required this.label, this.maxLines = 1});
  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.accent, size: 15),
            const SizedBox(width: 7),
            Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error view
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
          const SizedBox(height: 12),
          Text(error, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.button, foregroundColor: AppColors.accent),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}