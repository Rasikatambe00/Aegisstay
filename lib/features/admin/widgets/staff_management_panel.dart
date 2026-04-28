import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _StaffMember {
  const _StaffMember({
    required this.id,
    required this.name,
    required this.department,
    required this.role,
    required this.status,   // on_duty | off_duty | on_leave
    required this.shift,    // Morning | Evening | Night
    required this.phone,
    required this.email,
    required this.avatarInitials,
    required this.avatarColor,
    this.joinedAt,
  });

  final String id;
  final String name;
  final String department;
  final String role;
  final String status;
  final String shift;
  final String phone;
  final String email;
  final String avatarInitials;
  final Color avatarColor;
  final DateTime? joinedAt;

  String get shortId => id.length > 6 ? id.substring(id.length - 6).toUpperCase() : id.toUpperCase();
}

class _LeaveRequest {
  const _LeaveRequest({
    required this.staffName,
    required this.department,
    required this.from,
    required this.to,
    required this.reason,
    required this.status, // pending | approved | rejected
  });
  final String staffName, department, reason, status;
  final DateTime from, to;
}

class _Activity {
  const _Activity({required this.text, required this.time, required this.icon, required this.color});
  final String text;
  final DateTime time;
  final IconData icon;
  final Color color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Supabase service
// ─────────────────────────────────────────────────────────────────────────────

class _StaffService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<_StaffMember>> fetchStaff() async {
    try {
      // Try the admin staff_profiles table first (richer schema).
      // Falls back to the staff table used by the staff app.
      List<dynamic> rows = [];
      bool usedStaffTable = false;
      try {
        rows = await _db
            .from('staff_profiles')
            .select('id,full_name,department,current_role,is_on_duty,shift,phone,email,created_at')
            .order('full_name');
      } catch (_) {}

      if (rows.isEmpty) {
        // Fallback: staff table (used by the staff-facing app)
        rows = await _db
            .from('staff')
            .select('id,staff_name,is_on_duty,created_at')
            .order('staff_name');
        usedStaffTable = true;
      }

      return rows.map<_StaffMember>((r) => usedStaffTable
          ? _fromStaffRow(r)
          : _fromRow(r)).toList();
    } catch (_) {
      return _mock();
    }
  }

  static Future<List<_LeaveRequest>> fetchLeaveRequests() async {
    try {
      final rows = await _db
          .from('leave_requests')
          .select('staff_name,department,from_date,to_date,reason,status')
          .order('from_date', ascending: false)
          .limit(10);
      return rows.map<_LeaveRequest>((r) => _LeaveRequest(
        staffName: r['staff_name'] ?? '',
        department: r['department'] ?? '',
        from: DateTime.tryParse(r['from_date'] ?? '') ?? DateTime.now(),
        to: DateTime.tryParse(r['to_date'] ?? '') ?? DateTime.now(),
        reason: r['reason'] ?? '',
        status: r['status'] ?? 'pending',
      )).toList();
    } catch (_) {
      return _mockLeave();
    }
  }

  static Future<void> updateDutyStatus(String id, bool onDuty) async {
    try {
      // Update staff_profiles (admin table)
      await _db.from('staff_profiles').update({'is_on_duty': onDuty}).eq('id', id);
    } catch (_) {}
    try {
      // Also update the staff table (used by the staff-facing app) — best effort
      await _db.from('staff').update({'is_on_duty': onDuty}).eq('id', id);
    } catch (_) {}
  }

  static Future<void> approveLeave(String staffName, bool approve) async {
    try {
      await _db.from('leave_requests')
          .update({'status': approve ? 'approved' : 'rejected'})
          .eq('staff_name', staffName)
          .eq('status', 'pending');
    } catch (_) {}
  }

  static Stream<void> get changes {
    final ctrl = StreamController<void>.broadcast();
    final suffix = DateTime.now().millisecondsSinceEpoch;
    RealtimeChannel? ch1, ch2;
    void emit(_) { if (!ctrl.isClosed) ctrl.add(null); }
    try {
      ch1 = _db.channel('sm_staff_profiles_$suffix')
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
              table: 'staff_profiles', callback: emit).subscribe();
      ch2 = _db.channel('sm_staff_$suffix')
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
              table: 'staff', callback: emit).subscribe();
    } catch (_) {}
    ctrl.onCancel = () {
      try { if (ch1 != null) _db.removeChannel(ch1); } catch (_) {}
      try { if (ch2 != null) _db.removeChannel(ch2); } catch (_) {}
      ctrl.close();
    };
    return ctrl.stream;
  }

  static _StaffMember _fromRow(Map<String, dynamic> r) {
    final name = (r['full_name'] ?? 'Unknown').toString();
    final dept = (r['department'] ?? 'General').toString();
    final isOnDuty = r['is_on_duty'] as bool? ?? false;
    return _StaffMember(
      id: r['id'].toString(),
      name: name,
      department: dept,
      role: (r['current_role'] ?? 'Staff').toString(),
      status: isOnDuty ? 'on_duty' : 'off_duty',
      shift: (r['shift'] ?? 'Morning').toString(),
      phone: (r['phone'] ?? '—').toString(),
      email: (r['email'] ?? '—').toString(),
      avatarInitials: _initials(name),
      avatarColor: _deptColor(dept),
      joinedAt: DateTime.tryParse(r['created_at']?.toString() ?? ''),
    );
  }

  /// Mapper for the staff table (staff-facing app schema).
  static _StaffMember _fromStaffRow(Map<String, dynamic> r) {
    final name = (r['staff_name'] ?? 'Unknown').toString();
    final isOnDuty = r['is_on_duty'] as bool? ?? false;
    return _StaffMember(
      id: r['id'].toString(),
      name: name,
      department: (r['department'] ?? 'General').toString(),
      role: (r['role'] ?? r['current_role'] ?? 'Staff').toString(),
      status: isOnDuty ? 'on_duty' : 'off_duty',
      shift: (r['shift'] ?? 'Morning').toString(),
      phone: (r['phone'] ?? '—').toString(),
      email: (r['email'] ?? '—').toString(),
      avatarInitials: _initials(name),
      avatarColor: _deptColor((r['department'] ?? 'General').toString()),
      joinedAt: DateTime.tryParse(r['created_at']?.toString() ?? ''),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static Color _deptColor(String dept) {
    final d = dept.toLowerCase();
    if (d.contains('fire'))     return const Color(0xFFEF4444);
    if (d.contains('medical'))  return const Color(0xFF64B5F6);
    if (d.contains('security')) return const Color(0xFFFFB74D);
    if (d.contains('floor'))    return const Color(0xFF81C784);
    if (d.contains('manage'))   return const Color(0xFFCE93D8);
    return AppColors.accent;
  }

  static List<_StaffMember> _mock() {
    final now = DateTime.now();
    return [
      _StaffMember(id: 'staff-001', name: 'Alex Moreno',   department: 'Fire Safety',    role: 'Fire Marshal',    status: 'on_duty',  shift: 'Morning', phone: '+1-555-0101', email: 'alex@hotel.com',   avatarInitials: 'AM', avatarColor: const Color(0xFFEF4444), joinedAt: now.subtract(const Duration(days: 400))),
      _StaffMember(id: 'staff-002', name: 'Priya Sen',     department: 'Medical',         role: 'Paramedic',       status: 'on_duty',  shift: 'Morning', phone: '+1-555-0102', email: 'priya@hotel.com',  avatarInitials: 'PS', avatarColor: const Color(0xFF64B5F6), joinedAt: now.subtract(const Duration(days: 300))),
      _StaffMember(id: 'staff-003', name: 'Jordan Kim',    department: 'Floor Staff',     role: 'Floor Warden',    status: 'on_duty',  shift: 'Evening', phone: '+1-555-0103', email: 'jordan@hotel.com', avatarInitials: 'JK', avatarColor: const Color(0xFF81C784), joinedAt: now.subtract(const Duration(days: 200))),
      _StaffMember(id: 'staff-004', name: 'Riley Park',    department: 'Security',        role: 'Security Guard',  status: 'off_duty', shift: 'Night',   phone: '+1-555-0104', email: 'riley@hotel.com',  avatarInitials: 'RP', avatarColor: const Color(0xFFFFB74D), joinedAt: now.subtract(const Duration(days: 150))),
      _StaffMember(id: 'staff-005', name: 'Sam Torres',    department: 'Management',      role: 'Duty Manager',    status: 'on_duty',  shift: 'Morning', phone: '+1-555-0105', email: 'sam@hotel.com',    avatarInitials: 'ST', avatarColor: const Color(0xFFCE93D8), joinedAt: now.subtract(const Duration(days: 500))),
      _StaffMember(id: 'staff-006', name: 'Dana Lee',      department: 'Medical',         role: 'First Aider',     status: 'on_leave', shift: 'Morning', phone: '+1-555-0106', email: 'dana@hotel.com',   avatarInitials: 'DL', avatarColor: const Color(0xFF64B5F6), joinedAt: now.subtract(const Duration(days: 100))),
      _StaffMember(id: 'staff-007', name: 'Chris Patel',   department: 'Fire Safety',     role: 'Fire Warden',     status: 'off_duty', shift: 'Night',   phone: '+1-555-0107', email: 'chris@hotel.com',  avatarInitials: 'CP', avatarColor: const Color(0xFFEF4444), joinedAt: now.subtract(const Duration(days: 250))),
      _StaffMember(id: 'staff-008', name: 'Morgan Blake',  department: 'Security',        role: 'CCTV Operator',   status: 'on_duty',  shift: 'Evening', phone: '+1-555-0108', email: 'morgan@hotel.com', avatarInitials: 'MB', avatarColor: const Color(0xFFFFB74D), joinedAt: now.subtract(const Duration(days: 80))),
    ];
  }

  static List<_LeaveRequest> _mockLeave() {
    final now = DateTime.now();
    return [
      _LeaveRequest(staffName: 'Dana Lee',    department: 'Medical',    from: now,                                    to: now.add(const Duration(days: 3)),  reason: 'Personal',   status: 'pending'),
      _LeaveRequest(staffName: 'Riley Park',  department: 'Security',   from: now.add(const Duration(days: 5)),       to: now.add(const Duration(days: 7)),  reason: 'Vacation',   status: 'approved'),
      _LeaveRequest(staffName: 'Chris Patel', department: 'Fire Safety', from: now.subtract(const Duration(days: 2)), to: now.add(const Duration(days: 1)),  reason: 'Sick leave', status: 'pending'),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _statusColor(String s) {
  switch (s) {
    case 'on_duty':  return const Color(0xFF81C784);
    case 'off_duty': return const Color(0xFF9E9E9E);
    case 'on_leave': return const Color(0xFFFFB74D);
    default:         return Colors.white38;
  }
}

String _statusLabel(String s) {
  switch (s) {
    case 'on_duty':  return 'On Duty';
    case 'off_duty': return 'Off Duty';
    case 'on_leave': return 'On Leave';
    default:         return s;
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1)  return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24)   return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

// ─────────────────────────────────────────────────────────────────────────────
// Root widget — replaces StaffCoordinationPanel
// ─────────────────────────────────────────────────────────────────────────────

/// Full Staff Management dashboard.
/// Drop-in replacement for the old StaffCoordinationPanel stub.
class StaffCoordinationPanel extends StatefulWidget {
  const StaffCoordinationPanel({super.key});

  @override
  State<StaffCoordinationPanel> createState() => _StaffCoordinationPanelState();
}

class _StaffCoordinationPanelState extends State<StaffCoordinationPanel> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<_StaffMember> _all = [];
  List<_LeaveRequest> _leaves = [];
  bool _loading = true;
  StreamSubscription<void>? _sub;
  Timer? _debounce;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _liveEnabled = true;
  String _tabFilter = 'All';        // All | On Duty | Off Duty | On Leave
  String _deptFilter = 'All';
  String _roleFilter = 'All';
  String _search = '';
  String _sortCol = 'name';
  bool _sortAsc = true;
  int _page = 0;
  static const int _pageSize = 8;
  _StaffMember? _selected;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _StaffService.changes.listen((_) {
      if (!_liveEnabled) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _load);
    });
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _StaffService.fetchStaff(),
      _StaffService.fetchLeaveRequests(),
    ]);
    if (mounted) {
      setState(() {
        _all    = results[0] as List<_StaffMember>;
        _leaves = results[1] as List<_LeaveRequest>;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  // ── Derived ───────────────────────────────────────────────────────────────

  List<String> get _departments => ['All', ..._all.map((s) => s.department).toSet().toList()..sort()];
  List<String> get _roles       => ['All', ..._all.map((s) => s.role).toSet().toList()..sort()];

  List<_StaffMember> get _filtered {
    var list = _all.where((s) {
      if (_tabFilter == 'On Duty'  && s.status != 'on_duty')  return false;
      if (_tabFilter == 'Off Duty' && s.status != 'off_duty') return false;
      if (_tabFilter == 'On Leave' && s.status != 'on_leave') return false;
      if (_deptFilter != 'All' && s.department != _deptFilter) return false;
      if (_roleFilter != 'All' && s.role != _roleFilter)       return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!s.name.toLowerCase().contains(q) &&
            !s.department.toLowerCase().contains(q) &&
            !s.role.toLowerCase().contains(q) &&
            !s.shortId.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case 'dept':   cmp = a.department.compareTo(b.department); break;
        case 'role':   cmp = a.role.compareTo(b.role); break;
        case 'status': cmp = a.status.compareTo(b.status); break;
        case 'shift':  cmp = a.shift.compareTo(b.shift); break;
        default:       cmp = a.name.compareTo(b.name);
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  List<_StaffMember> get _pageItems {
    final f = _filtered;
    final start = _page * _pageSize;
    if (start >= f.length) return [];
    return f.sublist(start, math.min(start + _pageSize, f.length));
  }

  int get _totalPages => math.max(1, (_filtered.length / _pageSize).ceil());

  // Summary counts
  int get _onDuty   => _all.where((s) => s.status == 'on_duty').length;
  int get _offDuty  => _all.where((s) => s.status == 'off_duty').length;
  int get _deptCount => _all.map((s) => s.department).toSet().length;
  int get _roleCount => _all.map((s) => s.role).toSet().length;

  // ── Actions ───────────────────────────────────────────────────────────────

  void _sort(String col) => setState(() {
    if (_sortCol == col) { _sortAsc = !_sortAsc; } else { _sortCol = col; _sortAsc = true; }
    _page = 0;
  });

  Future<void> _toggleDuty(_StaffMember s) async {
    final newStatus = s.status == 'on_duty' ? 'off_duty' : 'on_duty';
    await _StaffService.updateDutyStatus(s.id, newStatus == 'on_duty');
    setState(() {
      _all = _all.map((m) => m.id == s.id
          ? _StaffMember(id: m.id, name: m.name, department: m.department, role: m.role,
              status: newStatus, shift: m.shift, phone: m.phone, email: m.email,
              avatarInitials: m.avatarInitials, avatarColor: m.avatarColor, joinedAt: m.joinedAt)
          : m).toList();
    });
  }

  Future<void> _handleLeave(String staffName, bool approve) async {
    await _StaffService.approveLeave(staffName, approve);
    setState(() {
      _leaves = _leaves.map((l) => l.staffName == staffName && l.status == 'pending'
          ? _LeaveRequest(staffName: l.staffName, department: l.department,
              from: l.from, to: l.to, reason: l.reason,
              status: approve ? 'approved' : 'rejected')
          : l).toList();
    });
  }

  void _showAddStaffDialog() {
    showDialog<void>(context: context, builder: (_) => _AddStaffDialog(onAdded: _load));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
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
        Expanded(flex: 7, child: _mainColumn()),
        const SizedBox(width: 14),
        SizedBox(width: 270, child: _SidePanel(
          all: _all,
          selected: _selected,
          onQuickAction: _handleQuickAction,
        )),
      ],
    );
  }

  Widget _narrowLayout() {
    return SingleChildScrollView(child: Column(children: [
      _mainColumn(),
      const SizedBox(height: 14),
      _SidePanel(all: _all, selected: _selected, onQuickAction: _handleQuickAction),
    ]));
  }

  Widget _mainColumn() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Header(
          liveEnabled: _liveEnabled,
          onLiveToggle: (v) => setState(() => _liveEnabled = v),
          search: _search,
          onSearch: (v) => setState(() { _search = v; _page = 0; }),
          deptFilter: _deptFilter,
          departments: _departments,
          onDeptFilter: (v) => setState(() { _deptFilter = v; _page = 0; }),
          roleFilter: _roleFilter,
          roles: _roles,
          onRoleFilter: (v) => setState(() { _roleFilter = v; _page = 0; }),
          onRefresh: _load,
          onAddStaff: _showAddStaffDialog,
          onExport: _exportCsv,
        ),
        const SizedBox(height: 18),
        _SummaryRow(
          total: _all.length, onDuty: _onDuty, offDuty: _offDuty,
          depts: _deptCount, roles: _roleCount,
          onTap: (tab) => setState(() { _tabFilter = tab; _page = 0; }),
        ),
        const SizedBox(height: 18),
        _StaffTable(
          items: _pageItems,
          allFiltered: _filtered,
          tabFilter: _tabFilter,
          onTabFilter: (t) => setState(() { _tabFilter = t; _page = 0; }),
          sortCol: _sortCol, sortAsc: _sortAsc, onSort: _sort,
          page: _page, totalPages: _totalPages,
          onPage: (p) => setState(() => _page = p),
          selected: _selected,
          onSelect: (s) => setState(() => _selected = _selected?.id == s.id ? null : s),
          onToggleDuty: _toggleDuty,
        ),
        const SizedBox(height: 18),
        _RecentActivities(staff: _all.take(5).toList()),
        const SizedBox(height: 18),
        _LeaveRequests(leaves: _leaves, onHandle: _handleLeave),
      ]),
    );
  }

  void _handleQuickAction(String action) {
    switch (action) {
      case 'add':      _showAddStaffDialog(); break;
      case 'schedule': _showScheduleDialog(); break;
      case 'broadcast':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Broadcast sent to all on-duty staff.')));
        break;
      case 'report':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Staff report generated.')));
        break;
    }
  }

  void _showScheduleDialog() {
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Shift Schedule', style: TextStyle(color: Colors.white)),
      content: const Text('Shift scheduling will be available in the next release.',
          style: TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  void _exportCsv() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Staff list exported to CSV.')));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.liveEnabled, required this.onLiveToggle,
    required this.search, required this.onSearch,
    required this.deptFilter, required this.departments, required this.onDeptFilter,
    required this.roleFilter, required this.roles, required this.onRoleFilter,
    required this.onRefresh, required this.onAddStaff, required this.onExport,
  });

  final bool liveEnabled;
  final ValueChanged<bool> onLiveToggle;
  final String search;
  final ValueChanged<String> onSearch;
  final String deptFilter;
  final List<String> departments;
  final ValueChanged<String> onDeptFilter;
  final String roleFilter;
  final List<String> roles;
  final ValueChanged<String> onRoleFilter;
  final VoidCallback onRefresh, onAddStaff, onExport;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Staff Management',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        const Spacer(),
        // Live toggle
        Row(children: [
          Icon(Icons.circle, size: 8,
              color: liveEnabled ? const Color(0xFF81C784) : Colors.white38),
          const SizedBox(width: 5),
          Text(liveEnabled ? 'LIVE' : 'PAUSED',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: liveEnabled ? const Color(0xFF81C784) : Colors.white38)),
          Switch(value: liveEnabled, onChanged: onLiveToggle,
              activeColor: AppColors.accent, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ]),
        const SizedBox(width: 6),
        // Export
        _HeaderBtn(icon: Icons.download_outlined, label: 'Export', onTap: onExport),
        const SizedBox(width: 6),
        // Add Staff
        GestureDetector(
          onTap: onAddStaff,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_add_outlined, size: 15, color: AppColors.accent),
              const SizedBox(width: 6),
              const Text('Add Staff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(tooltip: 'Refresh', onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: AppColors.accent, size: 20)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        // Search
        SizedBox(
          width: 220, height: 38,
          child: TextField(
            onChanged: onSearch,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search staff…',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
              filled: true, fillColor: AppColors.card,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent)),
            ),
          ),
        ),
        _DropFilter(label: 'Dept', value: deptFilter, options: departments, onChanged: onDeptFilter),
        _DropFilter(label: 'Role', value: roleFilter, options: roles, onChanged: onRoleFilter),
      ]),
    ]);
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ]),
    ),
  );
}

class _DropFilter extends StatelessWidget {
  const _DropFilter({required this.label, required this.value, required this.options, required this.onChanged});
  final String label, value; final List<String> options; final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    color: AppColors.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    onSelected: onChanged,
    itemBuilder: (_) => options.map((o) => PopupMenuItem(value: o,
        child: Text(o, style: TextStyle(
            color: o == value ? AppColors.accent : Colors.white70,
            fontWeight: o == value ? FontWeight.w700 : FontWeight.normal)))).toList(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: value != 'All' ? AppColors.accent : Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: $value', style: TextStyle(fontSize: 12,
            color: value != 'All' ? AppColors.accent : Colors.white60)),
        const SizedBox(width: 4),
        const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white38),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary cards
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total, required this.onDuty, required this.offDuty,
    required this.depts, required this.roles, required this.onTap,
  });
  final int total, onDuty, offDuty, depts, roles;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _SCard(label: 'Total Staff',    value: total,  color: AppColors.accent,           icon: Icons.groups_rounded,          tab: 'All',      onTap: onTap)),
    const SizedBox(width: 10),
    Expanded(child: _SCard(label: 'On Duty',        value: onDuty, color: const Color(0xFF81C784),    icon: Icons.check_circle_outline,    tab: 'On Duty',  onTap: onTap)),
    const SizedBox(width: 10),
    Expanded(child: _SCard(label: 'Off Duty',       value: offDuty,color: const Color(0xFF9E9E9E),    icon: Icons.cancel_outlined,         tab: 'Off Duty', onTap: onTap)),
    const SizedBox(width: 10),
    Expanded(child: _SCard(label: 'Departments',    value: depts,  color: const Color(0xFF64B5F6),    icon: Icons.business_outlined,       tab: 'All',      onTap: onTap)),
    const SizedBox(width: 10),
    Expanded(child: _SCard(label: 'Roles',          value: roles,  color: const Color(0xFFCE93D8),    icon: Icons.badge_outlined,          tab: 'All',      onTap: onTap)),
  ]);
}

class _SCard extends StatelessWidget {
  const _SCard({required this.label, required this.value, required this.color,
      required this.icon, required this.tab, required this.onTap});
  final String label, tab; final int value; final Color color;
  final IconData icon; final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onTap(tab),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 16),
          const Spacer(),
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color, height: 1)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Staff table
// ─────────────────────────────────────────────────────────────────────────────

class _StaffTable extends StatelessWidget {
  const _StaffTable({
    required this.items, required this.allFiltered,
    required this.tabFilter, required this.onTabFilter,
    required this.sortCol, required this.sortAsc, required this.onSort,
    required this.page, required this.totalPages, required this.onPage,
    required this.selected, required this.onSelect, required this.onToggleDuty,
  });

  final List<_StaffMember> items, allFiltered;
  final String tabFilter;
  final ValueChanged<String> onTabFilter;
  final String sortCol; final bool sortAsc;
  final ValueChanged<String> onSort;
  final int page, totalPages;
  final ValueChanged<int> onPage;
  final _StaffMember? selected;
  final ValueChanged<_StaffMember> onSelect;
  final Future<void> Function(_StaffMember) onToggleDuty;

  static const _tabs = ['All', 'On Duty', 'Off Duty', 'On Leave'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Tab bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            ..._tabs.map((t) => GestureDetector(
              onTap: () => onTabFilter(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: tabFilter == t ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tabFilter == t ? AppColors.accent : Colors.transparent),
                ),
                child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: tabFilter == t ? AppColors.accent : Colors.white38)),
              ),
            )),
            const Spacer(),
            Text('${allFiltered.length} staff', style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ]),
        ),
        const SizedBox(height: 10),
        const Divider(color: Color(0xFF2A1A14), height: 1),
        // Column headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _CH(label: 'ID',         col: 'id',     sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
            _CH(label: 'Name',       col: 'name',   sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 3),
            _CH(label: 'Department', col: 'dept',   sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 3),
            _CH(label: 'Role',       col: 'role',   sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 3),
            _CH(label: 'Status',     col: 'status', sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
            _CH(label: 'Shift',      col: 'shift',  sortCol: sortCol, sortAsc: sortAsc, onSort: onSort, flex: 2),
            const Expanded(flex: 2, child: Text('Actions',
                style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(color: Color(0xFF2A1A14), height: 1),
        // Rows
        if (items.isEmpty)
          const Padding(padding: EdgeInsets.all(28),
              child: Center(child: Text('No staff match the current filters.',
                  style: TextStyle(color: Colors.white38))))
        else
          ...items.map((s) => _StaffRow(
            staff: s,
            isSelected: selected?.id == s.id,
            onTap: () => onSelect(s),
            onToggleDuty: () => onToggleDuty(s),
          )),
        const Divider(color: Color(0xFF2A1A14), height: 1),
        // Pagination
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('Page ${page + 1} of $totalPages',
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.chevron_left, size: 18),
                color: page > 0 ? AppColors.accent : Colors.white24,
                onPressed: page > 0 ? () => onPage(page - 1) : null),
            IconButton(icon: const Icon(Icons.chevron_right, size: 18),
                color: page < totalPages - 1 ? AppColors.accent : Colors.white24,
                onPressed: page < totalPages - 1 ? () => onPage(page + 1) : null),
          ]),
        ),
      ]),
    );
  }
}

class _CH extends StatelessWidget {
  const _CH({required this.label, required this.col, required this.sortCol,
      required this.sortAsc, required this.onSort, required this.flex});
  final String label, col, sortCol; final bool sortAsc;
  final ValueChanged<String> onSort; final int flex;

  @override
  Widget build(BuildContext context) {
    final active = sortCol == col;
    return Expanded(flex: flex, child: GestureDetector(
      onTap: () => onSort(col),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: active ? AppColors.accent : Colors.white38)),
        if (active) Icon(sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
            size: 10, color: AppColors.accent),
      ]),
    ));
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.staff, required this.isSelected,
      required this.onTap, required this.onToggleDuty});
  final _StaffMember staff; final bool isSelected;
  final VoidCallback onTap, onToggleDuty;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected ? AppColors.accent.withValues(alpha: 0.07) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // ID
          Expanded(flex: 2, child: Text(staff.shortId,
              style: const TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'monospace'))),
          // Name with avatar
          Expanded(flex: 3, child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: staff.avatarColor.withValues(alpha: 0.25), shape: BoxShape.circle),
              child: Center(child: Text(staff.avatarInitials,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: staff.avatarColor))),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(staff.name,
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis)),
          ])),
          // Department
          Expanded(flex: 3, child: Text(staff.department,
              style: const TextStyle(fontSize: 11, color: Colors.white60), overflow: TextOverflow.ellipsis)),
          // Role
          Expanded(flex: 3, child: Text(staff.role,
              style: const TextStyle(fontSize: 11, color: Colors.white54), overflow: TextOverflow.ellipsis)),
          // Status badge
          Expanded(flex: 2, child: _StatusBadge(status: staff.status)),
          // Shift
          Expanded(flex: 2, child: Text(staff.shift,
              style: const TextStyle(fontSize: 11, color: Colors.white38))),
          // Actions
          Expanded(flex: 2, child: Row(children: [
            Tooltip(
              message: staff.status == 'on_duty' ? 'Set Off Duty' : 'Set On Duty',
              child: GestureDetector(
                onTap: onToggleDuty,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (staff.status == 'on_duty'
                        ? const Color(0xFF81C784) : const Color(0xFF9E9E9E)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    staff.status == 'on_duty' ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                    size: 16,
                    color: staff.status == 'on_duty' ? const Color(0xFF81C784) : const Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
          ])),
        ]),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(_statusLabel(status),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Side panel — overview chart, dept distribution, upcoming shifts, quick actions
// ─────────────────────────────────────────────────────────────────────────────

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.all, required this.selected, required this.onQuickAction});
  final List<_StaffMember> all;
  final _StaffMember? selected;
  final ValueChanged<String> onQuickAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(children: [
        _StaffOverviewChart(all: all, selected: selected),
        const SizedBox(height: 14),
        _DeptDistribution(all: all),
        const SizedBox(height: 14),
        _UpcomingShifts(all: all),
        const SizedBox(height: 14),
        _QuickActions(onAction: onQuickAction),
      ]),
    );
  }
}

// ── Staff overview donut ──────────────────────────────────────────────────────

class _StaffOverviewChart extends StatelessWidget {
  const _StaffOverviewChart({required this.all, required this.selected});
  final List<_StaffMember> all;
  final _StaffMember? selected;

  @override
  Widget build(BuildContext context) {
    final onDuty  = all.where((s) => s.status == 'on_duty').length;
    final offDuty = all.where((s) => s.status == 'off_duty').length;
    final onLeave = all.where((s) => s.status == 'on_leave').length;
    final total   = all.length;

    return _Card(title: 'Staff Overview', icon: Icons.donut_large_rounded, child: Column(children: [
      SizedBox(
        height: 130,
        child: CustomPaint(
          painter: _DonutPainter(segments: [
            _Seg(onDuty.toDouble(),  const Color(0xFF81C784)),
            _Seg(offDuty.toDouble(), const Color(0xFF9E9E9E)),
            _Seg(onLeave.toDouble(), const Color(0xFFFFB74D)),
          ], total: total.toDouble(), centerLabel: '$total', centerSub: 'Staff'),
          size: const Size(double.infinity, 130),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _DonutLeg(color: const Color(0xFF81C784), label: 'On Duty',  value: onDuty),
        _DonutLeg(color: const Color(0xFF9E9E9E), label: 'Off Duty', value: offDuty),
        _DonutLeg(color: const Color(0xFFFFB74D), label: 'On Leave', value: onLeave),
      ]),
      if (selected != null) ...[
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2A1A14), height: 1),
        const SizedBox(height: 10),
        Row(children: [
          Container(width: 32, height: 32,
            decoration: BoxDecoration(color: selected!.avatarColor.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Center(child: Text(selected!.avatarInitials,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected!.avatarColor)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(selected!.name, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
            Text(selected!.role, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ])),
          _StatusBadge(status: selected!.status),
        ]),
      ],
    ]));
  }
}

class _Seg { const _Seg(this.value, this.color); final double value; final Color color; }

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.segments, required this.total, required this.centerLabel, required this.centerSub});
  final List<_Seg> segments; final double total; final String centerLabel, centerSub;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final radius = math.min(cx, cy) - 10;
    const sw = 18.0, gap = 0.04;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = sw..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(Offset(cx, cy), radius, track);

    if (total <= 0) { _center(canvas, size, '0', 'No data'); return; }

    double start = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = (seg.value / total) * 2 * math.pi - gap;
      canvas.drawArc(rect, start + gap / 2, sweep, false, paint..color = seg.color);
      start += sweep + gap;
    }
    _center(canvas, size, centerLabel, centerSub);
  }

  void _center(Canvas canvas, Size size, String label, String sub) {
    final cx = size.width / 2, cy = size.height / 2;
    final tp1 = TextPainter(text: TextSpan(text: label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
        textDirection: TextDirection.ltr)..layout();
    tp1.paint(canvas, Offset(cx - tp1.width / 2, cy - tp1.height / 2 - 6));
    final tp2 = TextPainter(text: TextSpan(text: sub,
        style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
        textDirection: TextDirection.ltr)..layout();
    tp2.paint(canvas, Offset(cx - tp2.width / 2, cy + tp1.height / 2 - 4));
  }

  @override bool shouldRepaint(_DonutPainter old) => old.total != total;
}

class _DonutLeg extends StatelessWidget {
  const _DonutLeg({required this.color, required this.label, required this.value});
  final Color color; final String label; final int value;
  @override
  Widget build(BuildContext context) => Column(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(height: 4),
    Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
  ]);
}

// ── Department distribution bar chart ─────────────────────────────────────────

class _DeptDistribution extends StatelessWidget {
  const _DeptDistribution({required this.all});
  final List<_StaffMember> all;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final s in all) { counts[s.department] = (counts[s.department] ?? 0) + 1; }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = sorted.isEmpty ? 1 : sorted.first.value;

    return _Card(title: 'Department Distribution', icon: Icons.bar_chart_rounded, child: Column(
      children: sorted.map((e) {
        final color = _StaffService._deptColor(e.key);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 90, child: Text(e.key,
                style: const TextStyle(fontSize: 11, color: Colors.white60), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: e.value / max,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            )),
            const SizedBox(width: 8),
            Text('${e.value}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
        );
      }).toList(),
    ));
  }
}

// ── Upcoming shifts ───────────────────────────────────────────────────────────

class _UpcomingShifts extends StatelessWidget {
  const _UpcomingShifts({required this.all});
  final List<_StaffMember> all;

  @override
  Widget build(BuildContext context) {
    final shifts = all.where((s) => s.status != 'on_leave').take(5).toList();
    return _Card(title: 'Upcoming Shifts', icon: Icons.schedule_rounded, child: Column(
      children: shifts.map((s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(color: s.avatarColor.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Center(child: Text(s.avatarInitials,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: s.avatarColor)))),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            Text(s.role, style: const TextStyle(fontSize: 10, color: Colors.white38), overflow: TextOverflow.ellipsis),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
            child: Text(s.shift, style: const TextStyle(fontSize: 10, color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        ]),
      )).toList(),
    ));
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onAction});
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => _Card(title: 'Quick Actions', icon: Icons.bolt_rounded, child: Column(children: [
    _QABtn(icon: Icons.person_add_outlined,    label: 'Add Staff Member',   color: AppColors.accent,           action: 'add',       onAction: onAction),
    const SizedBox(height: 8),
    _QABtn(icon: Icons.calendar_month_outlined, label: 'Manage Schedules',  color: const Color(0xFF64B5F6),    action: 'schedule',  onAction: onAction),
    const SizedBox(height: 8),
    _QABtn(icon: Icons.campaign_outlined,       label: 'Broadcast to Staff',color: const Color(0xFFFFB74D),    action: 'broadcast', onAction: onAction),
    const SizedBox(height: 8),
    _QABtn(icon: Icons.assessment_outlined,     label: 'Generate Report',   color: const Color(0xFF81C784),    action: 'report',    onAction: onAction),
  ]));
}

class _QABtn extends StatelessWidget {
  const _QABtn({required this.icon, required this.label, required this.color, required this.action, required this.onAction});
  final IconData icon; final String label, action; final Color color; final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onAction(action),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        const Spacer(),
        Icon(Icons.arrow_forward_ios_rounded, size: 10, color: color.withValues(alpha: 0.5)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent activities
// ─────────────────────────────────────────────────────────────────────────────

class _RecentActivities extends StatelessWidget {
  const _RecentActivities({required this.staff});
  final List<_StaffMember> staff;

  @override
  Widget build(BuildContext context) {
    final activities = staff.map((s) => _Activity(
      text: '${s.name} — ${_statusLabel(s.status)}',
      time: s.joinedAt ?? DateTime.now().subtract(const Duration(hours: 1)),
      icon: s.status == 'on_duty' ? Icons.login_rounded : Icons.logout_rounded,
      color: _statusColor(s.status),
    )).toList();

    return _Card(title: 'Recent Activities', icon: Icons.history_rounded, child: activities.isEmpty
        ? const Text('No recent activity.', style: TextStyle(color: Colors.white38, fontSize: 12))
        : Column(children: activities.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 30, height: 30,
              decoration: BoxDecoration(color: a.color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(a.icon, size: 14, color: a.color)),
            const SizedBox(width: 10),
            Expanded(child: Text(a.text,
                style: const TextStyle(fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis)),
            Text(_timeAgo(a.time), style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ]),
        )).toList()));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leave requests
// ─────────────────────────────────────────────────────────────────────────────

class _LeaveRequests extends StatelessWidget {
  const _LeaveRequests({required this.leaves, required this.onHandle});
  final List<_LeaveRequest> leaves;
  final Future<void> Function(String, bool) onHandle;

  @override
  Widget build(BuildContext context) {
    return _Card(title: 'Leave Requests', icon: Icons.event_busy_rounded, child: leaves.isEmpty
        ? const Text('No leave requests.', style: TextStyle(color: Colors.white38, fontSize: 12))
        : Column(children: leaves.map((l) {
          final isPending = l.status == 'pending';
          final statusColor = l.status == 'approved'
              ? const Color(0xFF81C784)
              : l.status == 'rejected'
                  ? const Color(0xFFEF4444)
                  : const Color(0xFFFFB74D);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(l.staffName,
                    style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(l.status[0].toUpperCase() + l.status.substring(1),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ]),
              const SizedBox(height: 4),
              Text('${l.department} · ${l.reason}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
              Text('${_formatDate(l.from)} → ${_formatDate(l.to)}',
                  style: const TextStyle(fontSize: 10, color: Colors.white24)),
              if (isPending) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => onHandle(l.staffName, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF81C784).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF81C784).withValues(alpha: 0.4)),
                      ),
                      child: const Center(child: Text('Approve',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF81C784)))),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GestureDetector(
                    onTap: () => onHandle(l.staffName, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                      ),
                      child: const Center(child: Text('Reject',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF4444)))),
                    ),
                  )),
                ]),
              ],
            ]),
          );
        }).toList()));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Staff dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog({required this.onAdded});
  final VoidCallback onAdded;
  @override State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _dept  = 'Fire Safety';
  String _role  = 'Fire Marshal';
  String _shift = 'Morning';
  bool _submitting = false;

  @override void dispose() { _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Add Staff Member', style: TextStyle(color: Colors.white)),
      content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _DField(ctrl: _nameCtrl,  label: 'Full Name'),
        const SizedBox(height: 10),
        _DField(ctrl: _emailCtrl, label: 'Email'),
        const SizedBox(height: 10),
        _DField(ctrl: _phoneCtrl, label: 'Phone'),
        const SizedBox(height: 10),
        _DDrop(label: 'Department', value: _dept,
            options: const ['Fire Safety','Medical','Security','Floor Staff','Management'],
            onChanged: (v) => setState(() => _dept = v)),
        const SizedBox(height: 10),
        _DDrop(label: 'Shift', value: _shift,
            options: const ['Morning','Evening','Night'],
            onChanged: (v) => setState(() => _shift = v)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.button, foregroundColor: AppColors.accent),
          onPressed: _submitting ? null : () async {
            if (_nameCtrl.text.trim().isEmpty) return;
            setState(() => _submitting = true);
            try {
              final db = Supabase.instance.client;
              // Insert into staff_profiles (admin table)
              await db.from('staff_profiles').insert({
                'full_name': _nameCtrl.text.trim(),
                'email': _emailCtrl.text.trim(),
                'phone': _phoneCtrl.text.trim(),
                'department': _dept,
                'current_role': _role,
                'shift': _shift,
                'is_on_duty': false,
              });
              // Also insert into staff table (staff-facing app) — best effort
              try {
                await db.from('staff').insert({
                  'staff_name': _nameCtrl.text.trim(),
                  'is_on_duty': false,
                });
              } catch (_) {}
            } catch (_) {}
            widget.onAdded();
            if (context.mounted) Navigator.pop(context);
          },
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _DField extends StatelessWidget {
  const _DField({required this.ctrl, required this.label});
  final TextEditingController ctrl; final String label;
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
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

class _DDrop extends StatelessWidget {
  const _DDrop({required this.label, required this.value, required this.options, required this.onChanged});
  final String label, value; final List<String> options; final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value, dropdownColor: AppColors.card,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.child});
  final String title; final IconData icon; final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: AppColors.accent, size: 15),
        const SizedBox(width: 7),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
      ]),
      const SizedBox(height: 14),
      child,
    ]),
  );
}
