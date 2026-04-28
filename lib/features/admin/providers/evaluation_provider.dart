import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

enum RiskLevel { high, medium, low }

class RiskArea {
  RiskArea({
    required this.id,
    required this.name,
    required this.floor,
    required this.level,
    required this.normalizedX,
    required this.normalizedY,
    required this.width,
    required this.height,
    this.icon,
  });

  final String id;
  final String name;
  final int floor;
  RiskLevel level;
  final double normalizedX;
  final double normalizedY;
  final double width;
  final double height;
  final IconData? icon;

  Color get color {
    switch (level) {
      case RiskLevel.high:   return const Color(0xFFEF4444);
      case RiskLevel.medium: return const Color(0xFFFFB74D);
      case RiskLevel.low:    return const Color(0xFF81C784);
    }
  }

  String get levelLabel {
    switch (level) {
      case RiskLevel.high:   return 'High';
      case RiskLevel.medium: return 'Medium';
      case RiskLevel.low:    return 'Low';
    }
  }
}

class ActiveEvaluation {
  ActiveEvaluation({
    required this.id,
    required this.type,
    required this.location,
    required this.riskLevel,
    required this.status,
    required this.time,
  });

  final String id;
  final String type;
  final String location;
  RiskLevel riskLevel;
  String status;
  final DateTime time;
}

class TrendPoint {
  const TrendPoint({
    required this.hour,
    required this.high,
    required this.medium,
    required this.low,
  });
  final int hour;
  final int high;
  final int medium;
  final int low;
}

class RecommendedAction {
  const RecommendedAction({
    required this.title,
    required this.location,
    required this.riskLevel,
    required this.icon,
  });
  final String title;
  final String location;
  final RiskLevel riskLevel;
  final IconData icon;
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

class EvaluationProvider extends ChangeNotifier {
  EvaluationProvider() {
    _init();
  }

  // ── State ──────────────────────────────────────────────────────────────────
  int safetyScore = 82;
  int activeIncidentCount = 0;
  String incidentSubtext = '—';
  int affectedAreas = 0;
  int evacuatedCount = 0;
  bool systemOperational = true;
  bool isLive = true;
  bool isLoading = false;
  String? errorMessage;

  List<RiskArea> riskAreas = [];
  List<ActiveEvaluation> evaluations = [];
  List<TrendPoint> trends = [];
  List<RecommendedAction> actions = [];

  // Internal
  RealtimeChannel? _incidentChannel;
  RealtimeChannel? _evacuationChannel;
  Timer? _debounce;

  // ── Supabase client (lazy, null-safe) ─────────────────────────────────────
  SupabaseClient? get _db {
    try { return Supabase.instance.client; } catch (_) { return null; }
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  void _init() {
    _loadFromBackend();
    _subscribeRealtime();
  }

  // ── Backend fetch ──────────────────────────────────────────────────────────

  Future<void> _loadFromBackend() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final db = _db;
      if (db == null) throw Exception('Supabase unavailable');

      // Fetch all non-cancelled incidents in parallel with evacuation zones
      final results = await Future.wait([
        db.from('incidents')
            .select('id,incident_type,location,floor,created_at,status,description')
            .neq('status', 'cancelled')
            .order('created_at', ascending: false),
        db.from('evacuation_zones').select(),
      ]);

      final incidentRows  = results[0] as List;
      final evacuationRows = results[1] as List;

      _deriveFromIncidents(incidentRows);
      _deriveEvacuated(evacuationRows);
      _buildTrends(incidentRows);
    } catch (_) {
      // Supabase unavailable or query failed — fall back to mock data
      _loadMockData();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Derive all state from incident rows ────────────────────────────────────

  void _deriveFromIncidents(List<dynamic> rows) {
    // Active = not resolved/cancelled
    final active = rows.where((r) {
      final s = (r['status'] ?? '').toString().toLowerCase();
      return s != 'resolved' && s != 'cancelled';
    }).toList();

    activeIncidentCount = active.length;

    final critical = active.where((r) {
      final t = (r['incident_type'] ?? '').toString().toUpperCase();
      return t == 'FIRE' || t == 'MEDICAL';
    }).length;
    final warning = active.length - critical;
    incidentSubtext = '$critical Critical • $warning Warning';

    // Affected floors
    final floors = active
        .map((r) => r['floor'] as int?)
        .whereType<int>()
        .toSet();
    affectedAreas = floors.isEmpty ? active.isNotEmpty ? 1 : 0 : floors.length;

    // Safety score: 100 - (critical*15 + warning*5), clamped 0–100
    safetyScore = (100 - critical * 15 - warning * 5).clamp(0, 100);

    // System operational if no critical incidents
    systemOperational = critical == 0;

    // Build evaluations list from active incidents
    evaluations = active.take(10).map<ActiveEvaluation>((r) {
      final type = (r['incident_type'] ?? 'OTHER').toString().toUpperCase();
      return ActiveEvaluation(
        id:        r['id'].toString(),
        type:      _typeLabel(type),
        location:  (r['location'] ?? 'Unknown').toString(),
        riskLevel: _riskFromType(type),
        status:    _evalStatus((r['status'] ?? 'active').toString()),
        time:      DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
    }).toList();

    // Build risk areas from active incidents (map to floor plan positions)
    riskAreas = _buildRiskAreas(active);

    // Build recommended actions from evaluations
    actions = evaluations.take(5).map((e) => RecommendedAction(
      title:     _actionTitle(e.type),
      location:  e.location,
      riskLevel: e.riskLevel,
      icon:      _iconForType(e.type),
    )).toList();
  }

  // ── Build risk areas from incidents ───────────────────────────────────────

  List<RiskArea> _buildRiskAreas(List<dynamic> active) {
    // Static room positions on the floor plan canvas (1000 × 360 for upper floors).
    // These match the equipment_map.dart room rects exactly.
    const roomPositions = <String, _RoomPos>{
      'staircase 1':      _RoomPos(0.000, 0.000, 0.090, 0.411, 2),
      'classroom 201':    _RoomPos(0.092, 0.000, 0.118, 0.411, 2),
      'classroom 202':    _RoomPos(0.212, 0.000, 0.118, 0.411, 2),
      'lab 203':          _RoomPos(0.332, 0.000, 0.118, 0.411, 2),
      'staircase 2':      _RoomPos(0.452, 0.000, 0.090, 0.411, 2),
      'computer lab 204': _RoomPos(0.544, 0.000, 0.120, 0.411, 2),
      'library 205':      _RoomPos(0.666, 0.000, 0.118, 0.411, 2),
      'emergency exit':   _RoomPos(0.786, 0.000, 0.214, 0.411, 2),
      'classroom 206':    _RoomPos(0.000, 0.689, 0.090, 0.311, 2),
      'classroom 207':    _RoomPos(0.092, 0.689, 0.118, 0.311, 2),
      'store 208':        _RoomPos(0.212, 0.689, 0.104, 0.311, 2),
      'classroom 209':    _RoomPos(0.572, 0.689, 0.116, 0.311, 2),
      'classroom 210':    _RoomPos(0.690, 0.689, 0.116, 0.311, 2),
      'hallway a':        _RoomPos(0.000, 0.411, 1.000, 0.111, 2),
      'hallway b':        _RoomPos(0.000, 0.578, 1.000, 0.111, 2),
      // 1st floor
      'office 101':       _RoomPos(0.092, 0.000, 0.118, 0.411, 1),
      'office 102':       _RoomPos(0.212, 0.000, 0.118, 0.411, 1),
      'meeting room 103': _RoomPos(0.332, 0.000, 0.118, 0.411, 1),
      'conference room 104': _RoomPos(0.544, 0.000, 0.120, 0.411, 1),
      'training room 105':_RoomPos(0.666, 0.000, 0.118, 0.411, 1),
      'office 106':       _RoomPos(0.000, 0.689, 0.090, 0.311, 1),
      'office 107':       _RoomPos(0.092, 0.689, 0.118, 0.311, 1),
      'store 108':        _RoomPos(0.212, 0.689, 0.104, 0.311, 1),
      'office 109':       _RoomPos(0.572, 0.689, 0.116, 0.311, 1),
      'office 110':       _RoomPos(0.690, 0.689, 0.116, 0.311, 1),
      // Ground floor
      'reception':        _RoomPos(0.092, 0.000, 0.118, 0.321, 0),
      'admin office':     _RoomPos(0.212, 0.000, 0.118, 0.321, 0),
      'pantry':           _RoomPos(0.424, 0.000, 0.120, 0.321, 0),
      'cafe':             _RoomPos(0.424, 0.000, 0.120, 0.321, 0),
      'electrical room':  _RoomPos(0.546, 0.000, 0.118, 0.321, 0),
      'lobby':            _RoomPos(0.254, 0.548, 0.160, 0.262, 0),
      'waiting area':     _RoomPos(0.000, 0.548, 0.140, 0.262, 0),
      'meeting room':     _RoomPos(0.514, 0.548, 0.176, 0.262, 0),
      'store room':       _RoomPos(0.692, 0.548, 0.308, 0.262, 0),
    };

    final areas = <RiskArea>[];
    for (final row in active) {
      final location = (row['location'] ?? '').toString().toLowerCase();
      final type     = (row['incident_type'] ?? '').toString().toUpperCase();
      final floor    = (row['floor'] as int?) ?? _guessFloor(location);
      final id       = row['id'].toString();

      // Find matching room position
      _RoomPos? pos;
      for (final entry in roomPositions.entries) {
        if (location.contains(entry.key) && entry.value.floor == floor) {
          pos = entry.value;
          break;
        }
      }
      // Fallback: place in hallway A of the correct floor
      pos ??= _RoomPos(0.0, 0.411, 1.0, 0.111, floor);

      areas.add(RiskArea(
        id:          id,
        name:        (row['location'] ?? 'Unknown').toString(),
        floor:       floor,
        level:       _riskFromType(type),
        normalizedX: pos.x,
        normalizedY: pos.y,
        width:       pos.w,
        height:      pos.h,
        icon:        _iconForType(_typeLabel(type)),
      ));
    }
    return areas;
  }

  // ── Derive evacuated count from evacuation_zones ───────────────────────────

  void _deriveEvacuated(List<dynamic> rows) {
    if (rows.isEmpty) return;
    final first = rows.first as Map<String, dynamic>;
    if (first.containsKey('evacuated_count')) {
      evacuatedCount = (first['evacuated_count'] as int?) ?? 0;
      return;
    }
    // Multi-row zone style: count cleared zones × estimated occupancy
    int cleared = 0;
    for (final r in rows) {
      final row = r as Map<String, dynamic>;
      final s = (row['status'] ?? '').toString().toLowerCase();
      final isEvac = row['is_evacuated'] as bool? ?? false;
      if (isEvac || s == 'evacuated' || s == 'cleared' || s == 'safe') {
        cleared++;
      }
    }
    // Rough estimate: 12 people per cleared zone
    evacuatedCount = cleared * 12;
  }

  // ── Build 24-hour trend from incident timestamps ───────────────────────────

  void _buildTrends(List<dynamic> rows) {
    final now = DateTime.now();
    final high   = List<int>.filled(24, 0);
    final medium = List<int>.filled(24, 0);
    final low    = List<int>.filled(24, 0);

    for (final r in rows) {
      final created = DateTime.tryParse(r['created_at']?.toString() ?? '');
      if (created == null) continue;
      final diff = now.difference(created).inHours;
      if (diff < 0 || diff >= 24) continue;
      final slot = 23 - diff; // slot 23 = most recent hour
      final type = (r['incident_type'] ?? '').toString().toUpperCase();
      switch (_riskFromType(type)) {
        case RiskLevel.high:   high[slot]++;   break;
        case RiskLevel.medium: medium[slot]++; break;
        case RiskLevel.low:    low[slot]++;    break;
      }
    }

    trends = List.generate(24, (i) {
      final h = now.subtract(Duration(hours: 23 - i)).hour;
      return TrendPoint(hour: h, high: high[i], medium: medium[i], low: low[i]);
    });
  }

  // ── Realtime subscriptions ─────────────────────────────────────────────────

  void _subscribeRealtime() {
    final db = _db;
    if (db == null) return;

    final suffix = DateTime.now().millisecondsSinceEpoch;

    try {
      _incidentChannel = db
          .channel('eval_incidents_$suffix')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'incidents',
            callback: (_) => _onDataChanged(),
          )
          .subscribe();
    } catch (_) {}

    try {
      _evacuationChannel = db
          .channel('eval_evacuation_$suffix')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'evacuation_zones',
            callback: (_) => _onDataChanged(),
          )
          .subscribe();
    } catch (_) {}
  }

  void _onDataChanged() {
    if (!isLive) return;
    // Debounce: wait 600 ms after last event before re-fetching
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _loadFromBackend);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  void toggleLive() {
    isLive = !isLive;
    notifyListeners();
  }

  Future<void> refresh() => _loadFromBackend();

  // Computed getters for charts
  int get highRiskCount   => riskAreas.where((r) => r.level == RiskLevel.high).length;
  int get mediumRiskCount => riskAreas.where((r) => r.level == RiskLevel.medium).length;
  int get lowRiskCount    => riskAreas.where((r) => r.level == RiskLevel.low).length;

  List<RiskArea> get topRiskAreas {
    final sorted = List<RiskArea>.from(riskAreas)
      ..sort((a, b) => a.level.index.compareTo(b.level.index));
    return sorted.take(4).toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static RiskLevel _riskFromType(String type) {
    switch (type.toUpperCase()) {
      case 'FIRE':    return RiskLevel.high;
      case 'MEDICAL': return RiskLevel.high;
      case 'TRAPPED': return RiskLevel.medium;
      default:        return RiskLevel.low;
    }
  }

  static String _typeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'FIRE':    return 'Fire';
      case 'MEDICAL': return 'Medical';
      case 'TRAPPED': return 'Trapped';
      default:        return type.isEmpty ? 'Other' : type;
    }
  }

  static String _evalStatus(String status) {
    switch (status.toLowerCase()) {
      case 'active':   return 'Active';
      case 'assigned': return 'Investigating';
      default:         return 'Monitoring';
    }
  }

  static String _actionTitle(String type) {
    switch (type.toLowerCase()) {
      case 'fire':    return 'Investigate fire alarm';
      case 'medical': return 'Dispatch medical response';
      case 'trapped': return 'Assist trapped person';
      default:        return 'Review incident';
    }
  }

  static IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'fire':    return Icons.local_fire_department_rounded;
      case 'medical': return Icons.medical_services_rounded;
      case 'trapped': return Icons.person_off_rounded;
      default:        return Icons.warning_amber_rounded;
    }
  }

  static int _guessFloor(String location) {
    final m = RegExp(r'floor\s*(\d+)', caseSensitive: false).firstMatch(location);
    return int.tryParse(m?.group(1) ?? '') ?? 2;
  }

  // ── Mock fallback (used when Supabase is unavailable) ─────────────────────

  void _loadMockData() {
    final now = DateTime.now();
    final mockIncidents = [
      {'id': 'mock-1', 'incident_type': 'FIRE',    'location': 'Classroom 202', 'floor': 2, 'status': 'active',   'created_at': now.subtract(const Duration(minutes: 4)).toIso8601String(),  'description': 'Smoke detected.'},
      {'id': 'mock-2', 'incident_type': 'MEDICAL', 'location': 'Library 205',   'floor': 2, 'status': 'assigned', 'created_at': now.subtract(const Duration(minutes: 2)).toIso8601String(),  'description': 'Guest collapsed.'},
      {'id': 'mock-3', 'incident_type': 'TRAPPED', 'location': 'Classroom 201', 'floor': 2, 'status': 'active',   'created_at': now.subtract(const Duration(minutes: 8)).toIso8601String(),  'description': 'Guest stuck.'},
    ];
    _deriveFromIncidents(mockIncidents);
    _deriveEvacuated([]);
    evacuatedCount = 48;
    _buildTrends(mockIncidents);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _debounce?.cancel();
    final db = _db;
    if (db != null) {
      try { if (_incidentChannel  != null) db.removeChannel(_incidentChannel!);  } catch (_) {}
      try { if (_evacuationChannel != null) db.removeChannel(_evacuationChannel!); } catch (_) {}
    }
    super.dispose();
  }
}

// ── Internal helper ────────────────────────────────────────────────────────────

class _RoomPos {
  const _RoomPos(this.x, this.y, this.w, this.h, this.floor);
  final double x, y, w, h;
  final int floor;
}
