import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/features/admin/widgets/equipment_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

/// A live incident shown on the map.
class _MapIncident {
  const _MapIncident({
    required this.id,
    required this.type,
    required this.location,
    required this.floor,
    required this.time,
    required this.status,
    this.roomKey,
    this.description,
    this.reportedBy,
  });

  final String id;
  final String type;     // FIRE | MEDICAL | TRAPPED | OTHER
  final String location;
  final int floor;
  final DateTime time;
  final String status;
  final String? roomKey; // matches a key in _FloorLayout.rooms
  final String? description;
  final String? reportedBy;

  String get shortId =>
      id.length > 8 ? '#${id.substring(id.length - 8).toUpperCase()}' : '#$id';

  String get severity {
    switch (type.toUpperCase()) {
      case 'FIRE':    return 'CRITICAL';
      case 'MEDICAL': return 'HIGH';
      case 'TRAPPED': return 'MEDIUM';
      default:        return 'LOW';
    }
  }
}

/// A room rectangle on the floor plan (normalized 0–1 coords).
class _Room {
  const _Room({
    required this.key,
    required this.label,
    required this.rect,
    this.isStairwell = false,
    this.isElevator = false,
    this.isCorridor = false,
  });

  final String key;
  final String label;
  final Rect rect;
  final bool isStairwell;
  final bool isElevator;
  final bool isCorridor;
}

/// An evacuation route segment (normalized 0–1 coords).
class _RouteSegment {
  const _RouteSegment(this.from, this.to);
  final Offset from;
  final Offset to;
}

// ─────────────────────────────────────────────────────────────────────────────
// Floor layout definitions — one per floor
// ─────────────────────────────────────────────────────────────────────────────

class _FloorLayout {
  const _FloorLayout({
    required this.floor,
    required this.rooms,
    required this.routes,
    required this.assemblyPoints,
    required this.exits,
  });

  final int floor;
  final List<_Room> rooms;
  final List<_RouteSegment> routes;
  final List<Offset> assemblyPoints; // normalized
  final List<Offset> exits;          // normalized

  /// Build a standard hotel floor layout.
  /// Rooms are arranged in two wings with a central corridor.
  static _FloorLayout forFloor(int f) {
    // Left wing rooms (3 rooms)
    final leftRooms = List.generate(3, (i) => _Room(
      key: 'F${f}L${i + 1}',
      label: 'Room ${f}0${i + 1}',
      rect: Rect.fromLTWH(0.04, 0.08 + i * 0.27, 0.18, 0.22),
    ));

    // Right wing rooms (3 rooms)
    final rightRooms = List.generate(3, (i) => _Room(
      key: 'F${f}R${i + 1}',
      label: 'Room ${f}0${4 + i}',
      rect: Rect.fromLTWH(0.78, 0.08 + i * 0.27, 0.18, 0.22),
    ));

    // Central corridor
    const corridor = _Room(
      key: 'corridor',
      label: 'Corridor',
      rect: Rect.fromLTWH(0.24, 0.35, 0.52, 0.12),
      isCorridor: true,
    );

    // Stairwells
    const stairA = _Room(
      key: 'stairA',
      label: 'Stair A',
      rect: Rect.fromLTWH(0.04, 0.78, 0.10, 0.14),
      isStairwell: true,
    );
    const stairB = _Room(
      key: 'stairB',
      label: 'Stair B',
      rect: Rect.fromLTWH(0.86, 0.78, 0.10, 0.14),
      isStairwell: true,
    );

    // Elevator
    const elevator = _Room(
      key: 'elevator',
      label: 'Elevator',
      rect: Rect.fromLTWH(0.45, 0.78, 0.10, 0.14),
      isElevator: true,
    );

    // Lobby / reception on floor 1 only
    final lobbyRooms = f == 1
        ? [
            const _Room(
              key: 'lobby',
              label: 'Lobby',
              rect: Rect.fromLTWH(0.24, 0.08, 0.52, 0.24),
            ),
            const _Room(
              key: 'reception',
              label: 'Reception',
              rect: Rect.fromLTWH(0.24, 0.08, 0.24, 0.24),
            ),
          ]
        : <_Room>[];

    // Exits (bottom-left and bottom-right)
    final exits = [
      const Offset(0.09, 0.95),
      const Offset(0.91, 0.95),
    ];

    // Assembly points (outside, below exits) — only floor 1
    final assembly = f == 1
        ? [const Offset(0.09, 0.98), const Offset(0.91, 0.98)]
        : <Offset>[];

    // Evacuation routes: corridor → stairwells → exits
    final routes = [
      // Main corridor spine
      const _RouteSegment(Offset(0.24, 0.41), Offset(0.76, 0.41)),
      // Left branch to stair A
      const _RouteSegment(Offset(0.24, 0.41), Offset(0.09, 0.41)),
      const _RouteSegment(Offset(0.09, 0.41), Offset(0.09, 0.78)),
      // Right branch to stair B
      const _RouteSegment(Offset(0.76, 0.41), Offset(0.91, 0.41)),
      const _RouteSegment(Offset(0.91, 0.41), Offset(0.91, 0.78)),
      // Down to exits
      const _RouteSegment(Offset(0.09, 0.92), Offset(0.09, 0.95)),
      const _RouteSegment(Offset(0.91, 0.92), Offset(0.91, 0.95)),
    ];

    return _FloorLayout(
      floor: f,
      rooms: [
        ...leftRooms,
        ...rightRooms,
        corridor,
        stairA,
        stairB,
        elevator,
        ...lobbyRooms,
      ],
      routes: routes,
      assemblyPoints: assembly,
      exits: exits,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supabase service
// ─────────────────────────────────────────────────────────────────────────────

class _MapService {
  static SupabaseClient get _db => Supabase.instance.client;

  static Future<List<_MapIncident>> fetchIncidents() async {
    try {
      final rows = await _db
          .from('incidents')
          .select('id,incident_type,location,floor,created_at,status,description,created_by')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);
      return rows.map<_MapIncident>(_fromRow).toList();
    } catch (_) {
      return _mock();
    }
  }

  static Stream<void> get changes {
    final ctrl = StreamController<void>.broadcast();
    final suffix = DateTime.now().millisecondsSinceEpoch;
    RealtimeChannel? ch;
    try {
      ch = _db
          .channel('dtm_incidents_$suffix')
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

  static _MapIncident _fromRow(Map<String, dynamic> r) {
    final type = (r['incident_type'] ?? 'OTHER').toString().toUpperCase();
    final location = (r['location'] ?? 'Unknown').toString();
    return _MapIncident(
      id: r['id'].toString(),
      type: type,
      location: location,
      floor: (r['floor'] as int?) ?? _guessFloor(location),
      time: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
      status: (r['status'] ?? 'active').toString(),
      description: r['description'] as String?,
      reportedBy: r['created_by'] as String?,
      roomKey: _guessRoomKey(location),
    );
  }

  static int _guessFloor(String location) {
    final m = RegExp(r'floor\s*(\d+)', caseSensitive: false).firstMatch(location);
    return int.tryParse(m?.group(1) ?? '') ?? 1;
  }

  static String? _guessRoomKey(String location) {
    final m = RegExp(r'room\s*(\d+)', caseSensitive: false).firstMatch(location);
    if (m == null) return null;
    final num = m.group(1) ?? '';
    if (num.isEmpty) return null;
    final floor = int.tryParse(num.substring(0, 1)) ?? 1;
    final roomNum = int.tryParse(num.substring(1)) ?? 1;
    final wing = roomNum <= 3 ? 'L' : 'R';
    final idx = roomNum <= 3 ? roomNum : roomNum - 3;
    return 'F${floor}${wing}$idx';
  }

  static List<_MapIncident> _mock() {
    final now = DateTime.now();
    return [
      _MapIncident(id: 'mock-fire-1', type: 'FIRE', location: 'Floor 6 - Room 601', floor: 6, time: now.subtract(const Duration(minutes: 4)), status: 'active', roomKey: 'F6L1', description: 'Smoke detected in corridor.', reportedBy: 'Alex Moreno'),
      _MapIncident(id: 'mock-med-1', type: 'MEDICAL', location: 'Floor 2 - Room 204', floor: 2, time: now.subtract(const Duration(minutes: 2)), status: 'assigned', roomKey: 'F2R1', description: 'Guest collapsed near elevator.', reportedBy: 'Priya Sen'),
      _MapIncident(id: 'mock-trap-1', type: 'TRAPPED', location: 'Floor 3 - Stairwell B', floor: 3, time: now.subtract(const Duration(minutes: 1)), status: 'investigating', roomKey: 'stairB', description: 'Guest stuck in stairwell.', reportedBy: 'Jordan Kim'),
      _MapIncident(id: 'mock-other-1', type: 'OTHER', location: 'Floor 1 - Reception', floor: 1, time: now.subtract(const Duration(minutes: 10)), status: 'resolved', roomKey: 'reception', description: 'Minor disturbance.', reportedBy: 'Riley Park'),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _incidentColor(String type) {
  switch (type.toUpperCase()) {
    case 'FIRE':    return const Color(0xFFEF4444);
    case 'MEDICAL': return const Color(0xFF64B5F6);
    case 'TRAPPED': return const Color(0xFFFFB74D);
    default:        return const Color(0xFF9E9E9E);
  }
}

IconData _incidentIcon(String type) {
  switch (type.toUpperCase()) {
    case 'FIRE':    return Icons.local_fire_department_rounded;
    case 'MEDICAL': return Icons.medical_services_rounded;
    case 'TRAPPED': return Icons.person_off_rounded;
    default:        return Icons.warning_amber_rounded;
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24)   return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Root widget
// ─────────────────────────────────────────────────────────────────────────────

/// Full Digital Twin Map panel.
/// Self-contained: fetches incidents from Supabase with realtime updates.
class DigitalTwinMap extends StatefulWidget {
  const DigitalTwinMap({super.key});

  @override
  State<DigitalTwinMap> createState() => _DigitalTwinMapState();
}

class _DigitalTwinMapState extends State<DigitalTwinMap>
    with SingleTickerProviderStateMixin {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<_MapIncident> _incidents = [];
  bool _loading = true;
  StreamSubscription<void>? _sub;
  Timer? _debounce;

  // ── UI state ──────────────────────────────────────────────────────────────
  int _floor = 1;
  bool _is3D = false;
  bool _showRoutes = true;
  bool _showExits = true;
  bool _showAssembly = true;
  String _typeFilter = 'All'; // All | FIRE | MEDICAL | TRAPPED
  String _search = '';
  _MapIncident? _selected;
  bool _equipmentMode = false; // false = incident map, true = equipment map

  // ── Zoom / pan ─────────────────────────────────────────────────────────────
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _MapService.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _load);
    });
  }

  Future<void> _load() async {
    final data = await _MapService.fetchIncidents();
    if (mounted) setState(() { _incidents = data; _loading = false; });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _transformCtrl.dispose();
    super.dispose();
  }

  // ── Derived ───────────────────────────────────────────────────────────────

  List<_MapIncident> get _floorIncidents =>
      _incidents.where((i) => i.floor == _floor).toList();

  List<_MapIncident> get _filteredSideList {
    return _incidents.where((i) {
      if (_typeFilter != 'All' && i.type != _typeFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!i.location.toLowerCase().contains(q) &&
            !i.type.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  List<_MapIncident> get _top3Critical {
    final sorted = List<_MapIncident>.from(_incidents)
      ..sort((a, b) {
        const order = {'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3};
        return (order[a.severity] ?? 3).compareTo(order[b.severity] ?? 3);
      });
    return sorted.take(3).toList();
  }

  void _zoomToIncident(_MapIncident incident) {
    setState(() {
      _floor = incident.floor;
      _selected = incident;
    });
    // Reset zoom then animate to incident position
    _transformCtrl.value = Matrix4.identity();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      return wide ? _wideLayout() : _narrowLayout();
    });
  }

  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Side panel (hidden in equipment mode) ─────────────────────────
        if (!_equipmentMode)
          SizedBox(
            width: 260,
            child: _SidePanel(
              floor: _floor,
              onFloorChanged: (f) => setState(() { _floor = f; _selected = null; }),
              typeFilter: _typeFilter,
              onTypeFilter: (t) => setState(() => _typeFilter = t),
              search: _search,
              onSearch: (s) => setState(() => _search = s),
              showRoutes: _showRoutes,
              onShowRoutes: (v) => setState(() => _showRoutes = v),
              showExits: _showExits,
              onShowExits: (v) => setState(() => _showExits = v),
              showAssembly: _showAssembly,
              onShowAssembly: (v) => setState(() => _showAssembly = v),
              top3: _top3Critical,
              liveList: _filteredSideList,
              selected: _selected,
              onSelect: (i) { _zoomToIncident(i); },
            ),
          ),
        if (!_equipmentMode) const SizedBox(width: 12),
        // ── Map area ──────────────────────────────────────────────────────
        Expanded(
          child: Column(
            children: [
              _TopBar(
                floor: _floor,
                is3D: _is3D,
                onToggle3D: (v) => setState(() => _is3D = v),
                onZoomIn: () => _zoom(1.3),
                onZoomOut: () => _zoom(1 / 1.3),
                onReset: () => _transformCtrl.value = Matrix4.identity(),
                search: _search,
                onSearch: (s) => setState(() => _search = s),
                incidentCount: _floorIncidents.length,
                equipmentMode: _equipmentMode,
                onToggleEquipment: (v) => setState(() => _equipmentMode = v),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _equipmentMode
                    ? const EquipmentMapView()
                    : _MapCanvas(
                        floor: _floor,
                        is3D: _is3D,
                        incidents: _floorIncidents,
                        selected: _selected,
                        showRoutes: _showRoutes,
                        showExits: _showExits,
                        showAssembly: _showAssembly,
                        transformCtrl: _transformCtrl,
                        onSelect: (i) => setState(() => _selected = _selected?.id == i.id ? null : i),
                        loading: _loading,
                      ),
              ),
              if (!_equipmentMode && _selected != null) ...[
                const SizedBox(height: 10),
                _IncidentTooltip(
                  incident: _selected!,
                  onClose: () => setState(() => _selected = null),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrowLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _TopBar(
            floor: _floor, is3D: _is3D,
            onToggle3D: (v) => setState(() => _is3D = v),
            onZoomIn: () => _zoom(1.3),
            onZoomOut: () => _zoom(1 / 1.3),
            onReset: () => _transformCtrl.value = Matrix4.identity(),
            search: _search,
            onSearch: (s) => setState(() => _search = s),
            incidentCount: _floorIncidents.length,
            equipmentMode: _equipmentMode,
            onToggleEquipment: (v) => setState(() => _equipmentMode = v),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 340,
            child: _equipmentMode
                ? const EquipmentMapView()
                : _MapCanvas(
                    floor: _floor, is3D: _is3D,
                    incidents: _floorIncidents, selected: _selected,
                    showRoutes: _showRoutes, showExits: _showExits,
                    showAssembly: _showAssembly,
                    transformCtrl: _transformCtrl,
                    onSelect: (i) => setState(() => _selected = _selected?.id == i.id ? null : i),
                    loading: _loading,
                  ),
          ),
          if (!_equipmentMode && _selected != null) ...[
            const SizedBox(height: 8),
            _IncidentTooltip(incident: _selected!, onClose: () => setState(() => _selected = null)),
          ],
          if (!_equipmentMode) ...[
            const SizedBox(height: 10),
            _SidePanel(
              floor: _floor,
              onFloorChanged: (f) => setState(() { _floor = f; _selected = null; }),
              typeFilter: _typeFilter,
              onTypeFilter: (t) => setState(() => _typeFilter = t),
              search: _search,
              onSearch: (s) => setState(() => _search = s),
              showRoutes: _showRoutes,
              onShowRoutes: (v) => setState(() => _showRoutes = v),
              showExits: _showExits,
              onShowExits: (v) => setState(() => _showExits = v),
              showAssembly: _showAssembly,
              onShowAssembly: (v) => setState(() => _showAssembly = v),
              top3: _top3Critical,
              liveList: _filteredSideList,
              selected: _selected,
              onSelect: (i) { _zoomToIncident(i); },
            ),
          ],
        ],
      ),
    );
  }

  void _zoom(double factor) {
    final m = _transformCtrl.value.clone();
    m.scale(factor);
    _transformCtrl.value = m;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar — 2D/3D toggle, zoom controls, search, floor indicator
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.floor,
    required this.is3D,
    required this.onToggle3D,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.search,
    required this.onSearch,
    required this.incidentCount,
    required this.equipmentMode,
    required this.onToggleEquipment,
  });

  final int floor;
  final bool is3D;
  final ValueChanged<bool> onToggle3D;
  final VoidCallback onZoomIn, onZoomOut, onReset;
  final String search;
  final ValueChanged<String> onSearch;
  final int incidentCount;
  final bool equipmentMode;
  final ValueChanged<bool> onToggleEquipment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          // Floor badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
            ),
            child: Text('Floor $floor',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
          ),
          const SizedBox(width: 10),
          // Incident count badge
          if (incidentCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$incidentCount incident${incidentCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
            ),
          const Spacer(),
          // Search
          SizedBox(
            width: 180,
            height: 34,
            child: TextField(
              onChanged: onSearch,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search location…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                filled: true,
                fillColor: AppColors.background,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Equipment map toggle
          _ToggleButton(label: '🗺 Equipment', active: equipmentMode, onTap: () => onToggleEquipment(!equipmentMode)),
          const SizedBox(width: 10),
          // 2D / 3D toggle (only relevant in incident mode)
          if (!equipmentMode) ...[
            _ToggleButton(label: '2D', active: !is3D, onTap: () => onToggle3D(false)),
            const SizedBox(width: 4),
            _ToggleButton(label: '3D', active: is3D, onTap: () => onToggle3D(true)),
            const SizedBox(width: 10),
          ],
          // Zoom controls
          _IconBtn(icon: Icons.add, tooltip: 'Zoom in', onTap: onZoomIn),
          _IconBtn(icon: Icons.remove, tooltip: 'Zoom out', onTap: onZoomOut),
          _IconBtn(icon: Icons.center_focus_strong_outlined, tooltip: 'Reset view', onTap: onReset),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.15)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.accent : Colors.white38)),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Icon(icon, size: 15, color: Colors.white54),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Side panel — floor selector, filters, priority section, live list
// ─────────────────────────────────────────────────────────────────────────────

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.floor,
    required this.onFloorChanged,
    required this.typeFilter,
    required this.onTypeFilter,
    required this.search,
    required this.onSearch,
    required this.showRoutes,
    required this.onShowRoutes,
    required this.showExits,
    required this.onShowExits,
    required this.showAssembly,
    required this.onShowAssembly,
    required this.top3,
    required this.liveList,
    required this.selected,
    required this.onSelect,
  });

  final int floor;
  final ValueChanged<int> onFloorChanged;
  final String typeFilter;
  final ValueChanged<String> onTypeFilter;
  final String search;
  final ValueChanged<String> onSearch;
  final bool showRoutes, showExits, showAssembly;
  final ValueChanged<bool> onShowRoutes, onShowExits, onShowAssembly;
  final List<_MapIncident> top3;
  final List<_MapIncident> liveList;
  final _MapIncident? selected;
  final ValueChanged<_MapIncident> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Floor selector ──────────────────────────────────────────
            const _SectionLabel(text: 'Floor'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(6, (i) {
                final f = i + 1;
                return GestureDetector(
                  onTap: () => onFloorChanged(f),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: floor == f
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: floor == f
                              ? AppColors.accent
                              : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Center(
                      child: Text('F$f',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: floor == f ? AppColors.accent : Colors.white38)),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // ── Quick filters ───────────────────────────────────────────
            const _SectionLabel(text: 'Filter by Type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['All', 'FIRE', 'MEDICAL', 'TRAPPED'].map((t) {
                final active = typeFilter == t;
                final color = t == 'All'
                    ? AppColors.accent
                    : _incidentColor(t);
                return GestureDetector(
                  onTap: () => onTypeFilter(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: active ? color.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: active ? color : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active ? color : Colors.white38)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Layer toggles ───────────────────────────────────────────
            const _SectionLabel(text: 'Map Layers'),
            const SizedBox(height: 6),
            _LayerToggle(label: 'Evacuation Routes', color: const Color(0xFF81C784), value: showRoutes, onChanged: onShowRoutes),
            _LayerToggle(label: 'Exits', color: const Color(0xFFFFB74D), value: showExits, onChanged: onShowExits),
            _LayerToggle(label: 'Assembly Points', color: const Color(0xFF64B5F6), value: showAssembly, onChanged: onShowAssembly),
            const SizedBox(height: 16),

            // ── Priority section ────────────────────────────────────────
            const _SectionLabel(text: '🔴 Top Critical Incidents'),
            const SizedBox(height: 8),
            if (top3.isEmpty)
              const Text('No critical incidents.', style: TextStyle(fontSize: 11, color: Colors.white38))
            else
              ...top3.map((i) => _PriorityCard(
                incident: i,
                isSelected: selected?.id == i.id,
                onTap: () => onSelect(i),
              )),
            const SizedBox(height: 16),

            // ── Live incident list ───────────────────────────────────────
            Row(children: [
              const _SectionLabel(text: 'Live Alerts'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${liveList.length}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            if (liveList.isEmpty)
              const Text('No active alerts.', style: TextStyle(fontSize: 11, color: Colors.white38))
            else
              ...liveList.map((i) => _LiveAlertRow(
                incident: i,
                isSelected: selected?.id == i.id,
                onTap: () => onSelect(i),
              )),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white54, letterSpacing: 0.5));
  }
}

class _LayerToggle extends StatelessWidget {
  const _LayerToggle({required this.label, required this.color, required this.value, required this.onChanged});
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _PriorityCard extends StatelessWidget {
  const _PriorityCard({required this.incident, required this.isSelected, required this.onTap});
  final _MapIncident incident;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _incidentColor(incident.type);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(_incidentIcon(incident.type), size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(incident.location,
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(incident.severity,
                        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                    const Text(' · ', style: TextStyle(color: Colors.white24, fontSize: 10)),
                    Text(_timeAgo(incident.time),
                        style: const TextStyle(fontSize: 10, color: Colors.white38)),
                  ]),
                ],
              ),
            ),
            Icon(Icons.my_location_rounded, size: 14, color: color.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _LiveAlertRow extends StatelessWidget {
  const _LiveAlertRow({required this.incident, required this.isSelected, required this.onTap});
  final _MapIncident incident;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _incidentColor(incident.type);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(_incidentIcon(incident.type), size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(incident.location,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                      overflow: TextOverflow.ellipsis),
                  Text('Floor ${incident.floor} · ${_timeAgo(incident.time)}',
                      style: const TextStyle(fontSize: 10, color: Colors.white38)),
                ],
              ),
            ),
            _StatusDot(status: incident.status),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  Color get _color {
    switch (status.toLowerCase()) {
      case 'active':        return const Color(0xFFEF4444);
      case 'assigned':      return const Color(0xFFFFB74D);
      case 'investigating': return const Color(0xFF64B5F6);
      case 'resolved':      return const Color(0xFF81C784);
      default:              return Colors.white24;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map canvas — interactive floor plan with incident markers
// ─────────────────────────────────────────────────────────────────────────────

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({
    required this.floor,
    required this.is3D,
    required this.incidents,
    required this.selected,
    required this.showRoutes,
    required this.showExits,
    required this.showAssembly,
    required this.transformCtrl,
    required this.onSelect,
    required this.loading,
  });

  final int floor;
  final bool is3D;
  final List<_MapIncident> incidents;
  final _MapIncident? selected;
  final bool showRoutes, showExits, showAssembly;
  final TransformationController transformCtrl;
  final ValueChanged<_MapIncident> onSelect;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final layout = _FloorLayout.forFloor(floor);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.hardEdge,
      child: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : InteractiveViewer(
              transformationController: transformCtrl,
              minScale: 0.5,
              maxScale: 4.0,
              boundaryMargin: const EdgeInsets.all(80),
              child: LayoutBuilder(builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  children: [
                    // ── Floor plan background ──────────────────────────
                    CustomPaint(
                      size: Size(w, h),
                      painter: _FloorPlanPainter(
                        layout: layout,
                        is3D: is3D,
                        incidents: incidents,
                        selected: selected,
                      ),
                    ),
                    // ── Evacuation routes ──────────────────────────────
                    if (showRoutes)
                      CustomPaint(
                        size: Size(w, h),
                        painter: _RoutePainter(routes: layout.routes),
                      ),
                    // ── Exit markers ───────────────────────────────────
                    if (showExits)
                      ...layout.exits.map((pos) => Positioned(
                        left: pos.dx * w - 14,
                        top: pos.dy * h - 14,
                        child: const _ExitMarker(),
                      )),
                    // ── Assembly point markers ─────────────────────────
                    if (showAssembly)
                      ...layout.assemblyPoints.map((pos) => Positioned(
                        left: pos.dx * w - 14,
                        top: pos.dy * h - 14,
                        child: const _AssemblyMarker(),
                      )),
                    // ── Incident markers ───────────────────────────────
                    ...incidents.map((incident) {
                      final pos = _positionForIncident(incident, layout, w, h);
                      final isSelected = selected?.id == incident.id;
                      return Positioned(
                        left: pos.dx - 16,
                        top: pos.dy - 16,
                        child: GestureDetector(
                          onTap: () => onSelect(incident),
                          child: _IncidentMarker(
                            incident: incident,
                            isSelected: isSelected,
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ),
    );
  }

  Offset _positionForIncident(_MapIncident incident, _FloorLayout layout, double w, double h) {
    // Try to find the room by key
    if (incident.roomKey != null) {
      try {
        final room = layout.rooms.firstWhere((r) => r.key == incident.roomKey);
        final cx = (room.rect.left + room.rect.width / 2) * w;
        final cy = (room.rect.top + room.rect.height / 2) * h;
        return Offset(cx, cy);
      } catch (_) {}
    }
    // Fallback: stable hash-based position
    final hash = incident.id.hashCode.abs();
    return Offset(
      (0.15 + (hash % 70) / 100) * w,
      (0.15 + ((hash ~/ 100) % 70) / 100) * h,
    );
  }
}

// ── Floor plan painter ────────────────────────────────────────────────────────

class _FloorPlanPainter extends CustomPainter {
  const _FloorPlanPainter({
    required this.layout,
    required this.is3D,
    required this.incidents,
    required this.selected,
  });

  final _FloorLayout layout;
  final bool is3D;
  final List<_MapIncident> incidents;
  final _MapIncident? selected;

  // Rooms that have an active incident
  Set<String> get _alertedRooms {
    final keys = <String>{};
    for (final i in incidents) {
      if (i.roomKey != null && i.status != 'resolved') keys.add(i.roomKey!);
    }
    return keys;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final alerted = _alertedRooms;

    // Background grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 20; i++) {
      final x = size.width * i / 20;
      final y = size.height * i / 20;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final room in layout.rooms) {
      final rect = Rect.fromLTWH(
        room.rect.left * size.width,
        room.rect.top * size.height,
        room.rect.width * size.width,
        room.rect.height * size.height,
      );

      final hasAlert = alerted.contains(room.key);
      Color fillColor;
      Color borderColor;

      if (room.isCorridor) {
        fillColor = Colors.white.withValues(alpha: 0.03);
        borderColor = Colors.white.withValues(alpha: 0.08);
      } else if (room.isStairwell) {
        fillColor = const Color(0xFF2A2A1A).withValues(alpha: 0.8);
        borderColor = const Color(0xFFFFB74D).withValues(alpha: 0.4);
      } else if (room.isElevator) {
        fillColor = const Color(0xFF1A2A2A).withValues(alpha: 0.8);
        borderColor = const Color(0xFF64B5F6).withValues(alpha: 0.4);
      } else if (hasAlert) {
        final incident = incidents.firstWhere(
          (i) => i.roomKey == room.key && i.status != 'resolved',
          orElse: () => incidents.first,
        );
        fillColor = _incidentColor(incident.type).withValues(alpha: 0.12);
        borderColor = _incidentColor(incident.type).withValues(alpha: 0.6);
      } else {
        fillColor = const Color(0xFF1C1614).withValues(alpha: 0.9);
        borderColor = Colors.white.withValues(alpha: 0.1);
      }

      // 3D effect: draw a shadow offset rectangle
      if (is3D && !room.isCorridor) {
        final shadowRect = rect.translate(4, 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(shadowRect, const Radius.circular(4)),
          Paint()..color = Colors.black.withValues(alpha: 0.4),
        );
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = fillColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = hasAlert ? 1.5 : 1.0,
      );

      // Room label
      if (!room.isCorridor && rect.width > 30 && rect.height > 20) {
        final tp = TextPainter(
          text: TextSpan(
            text: room.label,
            style: TextStyle(
              fontSize: math.min(rect.width * 0.18, 10),
              color: hasAlert
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.35),
              fontWeight: hasAlert ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width - 4);
        tp.paint(
          canvas,
          Offset(rect.left + (rect.width - tp.width) / 2,
              rect.top + (rect.height - tp.height) / 2),
        );
      }
    }

    // Floor label watermark
    final floorTp = TextPainter(
      text: TextSpan(
        text: 'Floor ${layout.floor}',
        style: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.03),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    floorTp.paint(
      canvas,
      Offset(size.width / 2 - floorTp.width / 2, size.height / 2 - floorTp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FloorPlanPainter old) =>
      old.layout.floor != layout.floor ||
      old.is3D != is3D ||
      old.incidents.length != incidents.length ||
      old.selected?.id != selected?.id;
}

// ── Route painter ─────────────────────────────────────────────────────────────

class _RoutePainter extends CustomPainter {
  const _RoutePainter({required this.routes});
  final List<_RouteSegment> routes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF81C784).withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final arrowPaint = Paint()
      ..color = const Color(0xFF81C784).withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final seg in routes) {
      final from = Offset(seg.from.dx * size.width, seg.from.dy * size.height);
      final to = Offset(seg.to.dx * size.width, seg.to.dy * size.height);
      canvas.drawLine(from, to, paint);

      // Draw small directional arrow at midpoint
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
      const arrowLen = 6.0;
      const arrowAngle = 0.4;
      canvas.drawLine(
        mid,
        Offset(mid.dx - arrowLen * math.cos(angle - arrowAngle),
            mid.dy - arrowLen * math.sin(angle - arrowAngle)),
        arrowPaint,
      );
      canvas.drawLine(
        mid,
        Offset(mid.dx - arrowLen * math.cos(angle + arrowAngle),
            mid.dy - arrowLen * math.sin(angle + arrowAngle)),
        arrowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => false;
}

// ── Incident marker ───────────────────────────────────────────────────────────

class _IncidentMarker extends StatefulWidget {
  const _IncidentMarker({required this.incident, required this.isSelected});
  final _MapIncident incident;
  final bool isSelected;

  @override
  State<_IncidentMarker> createState() => _IncidentMarkerState();
}

class _IncidentMarkerState extends State<_IncidentMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _incidentColor(widget.incident.type);
    final size = widget.isSelected ? 36.0 : 30.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring
            if (widget.incident.status == 'active')
              Container(
                width: size + 12 + _pulse.value * 8,
                height: size + 12 + _pulse.value * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: 0.3 * (1 - _pulse.value)),
                    width: 2,
                  ),
                ),
              ),
            // Main marker
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isSelected ? Colors.white : color.withValues(alpha: 0.5),
                  width: widget.isSelected ? 2.5 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: widget.isSelected ? 0.6 : 0.3),
                    blurRadius: widget.isSelected ? 14 : 8,
                  ),
                ],
              ),
              child: Icon(
                _incidentIcon(widget.incident.type),
                size: size * 0.45,
                color: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Exit marker ───────────────────────────────────────────────────────────────

class _ExitMarker extends StatelessWidget {
  const _ExitMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFFFB74D).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.7)),
      ),
      child: const Icon(Icons.exit_to_app_rounded, size: 14, color: Color(0xFFFFB74D)),
    );
  }
}

// ── Assembly point marker ─────────────────────────────────────────────────────

class _AssemblyMarker extends StatelessWidget {
  const _AssemblyMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF64B5F6).withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF64B5F6).withValues(alpha: 0.7)),
      ),
      child: const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFF64B5F6)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Incident tooltip (shown below map when an incident is selected)
// ─────────────────────────────────────────────────────────────────────────────

class _IncidentTooltip extends StatelessWidget {
  const _IncidentTooltip({required this.incident, required this.onClose});
  final _MapIncident incident;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final color = _incidentColor(incident.type);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(_incidentIcon(incident.type), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(incident.type,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                  const Text(' · ', style: TextStyle(color: Colors.white24)),
                  Text(incident.severity,
                      style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
                ]),
                const SizedBox(height: 2),
                Text(incident.location,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if (incident.description != null) ...[
                  const SizedBox(height: 2),
                  Text(incident.description!,
                      style: const TextStyle(fontSize: 11, color: Colors.white38),
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeAgo(incident.time),
                  style: const TextStyle(fontSize: 10, color: Colors.white38)),
              if (incident.reportedBy != null) ...[
                const SizedBox(height: 2),
                Text('by ${incident.reportedBy}',
                    style: const TextStyle(fontSize: 10, color: Colors.white38)),
              ],
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, size: 16, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
