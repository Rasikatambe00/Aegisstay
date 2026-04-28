// ignore_for_file: library_private_types_in_public_api
import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─── App colours ──────────────────────────────────────────────────────────────
class _C {
  static const surface   = Color(0xFF1C1210);
  static const card      = Color(0xFF221714);
  static const border    = Color(0xFF3A1F16);
  static const peach     = Color(0xFFFFB499);
  static const deepBrown = Color(0xFF4A342E);
  static const wall      = Color(0xFF2A1A14);
  static const hallway   = Color(0xFF130907);
  static const roomFill  = Color(0xFF1A0F0C);
  static const roomText  = Color(0xFF6A4035);
  static const exitGreen = Color(0xFF22C55E);
  static const extRed    = Color(0xFFEF4444);
  static const hoseOrg   = Color(0xFFF97316);
  static const mcpYellow = Color(0xFFEAB308);
  static const apTeal    = Color(0xFF14B8A6);
  static const evac      = Color(0xFF4ADE80);
  static const pathColor = Color(0xFFFF8C00);
}

// ─── Data models ──────────────────────────────────────────────────────────────
enum EquipType { exit, extinguisher, hoseReel, callPoint, assembly }

class FloorRoom {
  const FloorRoom(this.label, this.rect, {this.subLabel});
  final String label;
  final String? subLabel;
  final Rect rect;
}

class Equipment {
  const Equipment(this.type, this.label, this.location, this.pos);
  final EquipType type;
  final String label;
  final String location;
  final Offset pos; // normalised 0–1000
}

class EvacLine {
  const EvacLine(this.a, this.b);
  final Offset a, b;
}

// ─── A* Pathfinding ───────────────────────────────────────────────────────────
class _GridCell {
  final int x, y;
  const _GridCell(this.x, this.y);
  @override bool operator ==(Object o) => o is _GridCell && o.x == x && o.y == y;
  @override int get hashCode => x * 10000 + y;
}

class _AStarGrid {
  static const _cellSize = 10.0;
  final int cols;
  final int rows;
  final List<List<bool>> walkable;

  _AStarGrid._(this.cols, this.rows, this.walkable);

  factory _AStarGrid.forFloor(_FloorData floor, double canvasH) {
    final cols = (1000 / _cellSize).ceil();
    final rows = (canvasH / _cellSize).ceil();
    final walkable = List.generate(rows, (_) => List.filled(cols, true));

    for (final room in floor.rooms) {
      final r = room.rect.deflate(2);
      final c0 = (r.left  / _cellSize).floor().clamp(0, cols - 1);
      final c1 = (r.right / _cellSize).ceil() .clamp(0, cols - 1);
      final r0 = (r.top   / _cellSize).floor().clamp(0, rows - 1);
      final r1 = (r.bottom/ _cellSize).ceil() .clamp(0, rows - 1);
      for (var ry = r0; ry <= r1; ry++) {
        for (var cx = c0; cx <= c1; cx++) { walkable[ry][cx] = false; }
      }
    }

    for (final hw in [floor.hallwayA, floor.hallwayB]) {
      final c0 = (hw.left  / _cellSize).floor().clamp(0, cols - 1);
      final c1 = (hw.right / _cellSize).ceil() .clamp(0, cols - 1);
      final r0 = (hw.top   / _cellSize).floor().clamp(0, rows - 1);
      final r1 = (hw.bottom/ _cellSize).ceil() .clamp(0, rows - 1);
      for (var ry = r0; ry <= r1; ry++) {
        for (var cx = c0; cx <= c1; cx++) { walkable[ry][cx] = true; }
      }
    }
    return _AStarGrid._(cols, rows, walkable);
  }

  _GridCell canvasToCell(Offset p) => _GridCell(
    (p.dx / _cellSize).round().clamp(0, cols - 1),
    (p.dy / _cellSize).round().clamp(0, rows - 1),
  );

  Offset cellToCanvas(_GridCell c) =>
      Offset(c.x * _cellSize + _cellSize / 2, c.y * _cellSize + _cellSize / 2);

  bool isWalkable(_GridCell c) =>
      c.x >= 0 && c.x < cols && c.y >= 0 && c.y < rows && walkable[c.y][c.x];

  List<_GridCell> neighbours(_GridCell c) {
    final result = <_GridCell>[];
    for (final d in const [[-1,0],[1,0],[0,-1],[0,1]]) {
      final n = _GridCell(c.x + d[0], c.y + d[1]);
      if (isWalkable(n)) result.add(n);
    }
    return result;
  }
}

class _AStarNode {
  final _GridCell cell;
  final _AStarNode? parent;
  final double g, h;
  double get f => g + h;
  _AStarNode(this.cell, this.parent, this.g, this.h);
}

class _AStarFinder {
  static List<Offset>? findPath(_AStarGrid grid, Offset startCanvas, Offset goalCanvas) {
    final start = grid.canvasToCell(startCanvas);
    final goal  = grid.canvasToCell(goalCanvas);
    if (!grid.isWalkable(start) || !grid.isWalkable(goal)) return null;
    if (start == goal) return [startCanvas, goalCanvas];

    double h(_GridCell a, _GridCell b) =>
        ((a.x - b.x).abs() + (a.y - b.y).abs()).toDouble();

    final open   = <_AStarNode>[];
    final closed = <_GridCell>{};
    final gScore = <_GridCell, double>{};

    void push(_AStarNode n) {
      open.add(n);
      open.sort((a, b) => a.f.compareTo(b.f));
    }

    push(_AStarNode(start, null, 0, h(start, goal)));
    gScore[start] = 0;

    while (open.isNotEmpty) {
      final current = open.removeAt(0);
      if (current.cell == goal) {
        final path = <Offset>[];
        _AStarNode? node = current;
        while (node != null) { path.add(grid.cellToCanvas(node.cell)); node = node.parent; }
        return path.reversed.toList();
      }
      closed.add(current.cell);
      for (final nb in grid.neighbours(current.cell)) {
        if (closed.contains(nb)) continue;
        final tg = current.g + 1;
        if (tg < (gScore[nb] ?? double.infinity)) {
          gScore[nb] = tg;
          push(_AStarNode(nb, current, tg, h(nb, goal)));
        }
      }
    }
    return null;
  }
}

class _NearestExitResult {
  final Equipment exit;
  final List<Offset> path;
  _NearestExitResult(this.exit, this.path);
}

_NearestExitResult? findNearestExit(Offset from, _FloorData floor, double canvasH) {
  final grid = _AStarGrid.forFloor(floor, canvasH);
  final exits = floor.equipment.where((e) => e.type == EquipType.exit).toList();
  _NearestExitResult? best;
  for (final exit in exits) {
    final path = _AStarFinder.findPath(grid, from, exit.pos);
    if (path == null) continue;
    if (best == null || path.length < best.path.length) {
      best = _NearestExitResult(exit, path);
    }
  }
  return best;
}

// ─── Floor definitions ────────────────────────────────────────────────────────
class _FloorData {
  const _FloorData({
    required this.label,
    required this.rooms,
    required this.equipment,
    required this.evacLines,
    required this.hallwayA,
    required this.hallwayB,
  });
  final String label;
  final List<FloorRoom> rooms;
  final List<Equipment> equipment;
  final List<EvacLine> evacLines;
  final Rect hallwayA;
  final Rect hallwayB;
}

final _secondFloor = _FloorData(
  label: '2ND FLOOR',
  hallwayA: const Rect.fromLTWH(0, 148, 1000, 40),
  hallwayB: const Rect.fromLTWH(0, 208, 1000, 40),
  rooms: const [
    FloorRoom('STAIRCASE 1', Rect.fromLTWH(0, 0, 90, 148), subLabel: '(NORMAL)'),
    FloorRoom('CLASSROOM\n201', Rect.fromLTWH(92, 0, 118, 148)),
    FloorRoom('CLASSROOM\n202', Rect.fromLTWH(212, 0, 118, 148)),
    FloorRoom('LAB\n203', Rect.fromLTWH(332, 0, 118, 148)),
    FloorRoom('STAIRCASE 2', Rect.fromLTWH(452, 0, 90, 148), subLabel: '(NORMAL)'),
    FloorRoom('COMPUTER\nLAB 204', Rect.fromLTWH(544, 0, 120, 148)),
    FloorRoom('LIBRARY\n205', Rect.fromLTWH(666, 0, 118, 148)),
    FloorRoom('EMERGENCY EXIT\n(FIRE STAIRCASE)', Rect.fromLTWH(786, 0, 214, 148)),
    FloorRoom('CLASSROOM\n206', Rect.fromLTWH(0, 248, 90, 112)),
    FloorRoom('CLASSROOM\n207', Rect.fromLTWH(92, 248, 118, 112)),
    FloorRoom('STORE\n208', Rect.fromLTWH(212, 248, 104, 112)),
    FloorRoom('TOILET\n(M/F)', Rect.fromLTWH(318, 248, 70, 56)),
    FloorRoom('TOILET\n(M/F)', Rect.fromLTWH(500, 248, 70, 56)),
    FloorRoom('CLASSROOM\n209', Rect.fromLTWH(572, 248, 116, 112)),
    FloorRoom('CLASSROOM\n210', Rect.fromLTWH(690, 248, 116, 112)),
  ],
  evacLines: [
    EvacLine(Offset(30, 168), Offset(970, 168)),
    EvacLine(Offset(30, 228), Offset(970, 228)),
    EvacLine(Offset(497, 148), Offset(497, 248)),
    EvacLine(Offset(30, 168), Offset(0, 168)),
    EvacLine(Offset(970, 168), Offset(1000, 168)),
  ],
  equipment: [
    Equipment(EquipType.exit, 'EXIT 1', 'North-west — Staircase 1 (Normal)', Offset(18, 8)),
    Equipment(EquipType.exit, 'EXIT 2', 'Centre north — Staircase 2 (Normal)', Offset(452, 8)),
    Equipment(EquipType.exit, 'EXIT 3', 'North-east — Emergency Exit (Fire Staircase)', Offset(786, 8)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway A — near Lab 203', Offset(350, 158)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway A — east wing', Offset(720, 158)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway B — west centre', Offset(270, 218)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway B — east wing', Offset(780, 218)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway A — near Classroom 201', Offset(100, 153)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway A — near Emergency Exit', Offset(900, 153)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway B — west end', Offset(100, 213)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway A — west zone', Offset(200, 148)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway A — east zone', Offset(640, 148)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway B — east end', Offset(870, 208)),
    Equipment(EquipType.assembly, 'Assembly Point', 'Staircase 2 — Hallway A/B junction', Offset(487, 178)),
  ],
);

final _firstFloor = _FloorData(
  label: '1ST FLOOR',
  hallwayA: const Rect.fromLTWH(0, 148, 1000, 40),
  hallwayB: const Rect.fromLTWH(0, 208, 1000, 40),
  rooms: const [
    FloorRoom('STAIRCASE 1', Rect.fromLTWH(0, 0, 90, 148), subLabel: '(NORMAL)'),
    FloorRoom('OFFICE\n101', Rect.fromLTWH(92, 0, 118, 148)),
    FloorRoom('OFFICE\n102', Rect.fromLTWH(212, 0, 118, 148)),
    FloorRoom('MEETING\nROOM 103', Rect.fromLTWH(332, 0, 118, 148)),
    FloorRoom('STAIRCASE 2', Rect.fromLTWH(452, 0, 90, 148), subLabel: '(NORMAL)'),
    FloorRoom('CONFERENCE\nROOM 104', Rect.fromLTWH(544, 0, 120, 148)),
    FloorRoom('TRAINING\nROOM 105', Rect.fromLTWH(666, 0, 118, 148)),
    FloorRoom('EMERGENCY EXIT\n(FIRE STAIRCASE)', Rect.fromLTWH(786, 0, 214, 148)),
    FloorRoom('OFFICE\n106', Rect.fromLTWH(0, 248, 90, 112)),
    FloorRoom('OFFICE\n107', Rect.fromLTWH(92, 248, 118, 112)),
    FloorRoom('STORE\n108', Rect.fromLTWH(212, 248, 104, 112)),
    FloorRoom('TOILET\n(M/F)', Rect.fromLTWH(318, 248, 70, 56)),
    FloorRoom('TOILET\n(M/F)', Rect.fromLTWH(500, 248, 70, 56)),
    FloorRoom('OFFICE\n109', Rect.fromLTWH(572, 248, 116, 112)),
    FloorRoom('OFFICE\n110', Rect.fromLTWH(690, 248, 116, 112)),
  ],
  evacLines: [
    EvacLine(Offset(30, 168), Offset(970, 168)),
    EvacLine(Offset(30, 228), Offset(970, 228)),
    EvacLine(Offset(497, 148), Offset(497, 248)),
    EvacLine(Offset(30, 168), Offset(0, 168)),
    EvacLine(Offset(970, 168), Offset(1000, 168)),
  ],
  equipment: [
    Equipment(EquipType.exit, 'EXIT 1', 'North-west — Staircase 1 (Normal)', Offset(18, 8)),
    Equipment(EquipType.exit, 'EXIT 2', 'Centre north — Staircase 2 (Normal)', Offset(452, 8)),
    Equipment(EquipType.exit, 'EXIT 3', 'North-east — Emergency Exit (Fire Staircase)', Offset(786, 8)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway A — near Meeting Room 103', Offset(350, 158)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway A — near Training Room 105', Offset(720, 158)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway B — west centre', Offset(270, 218)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway B — east wing', Offset(780, 218)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway A — near Office 101', Offset(100, 153)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway A — near Emergency Exit', Offset(900, 153)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway B — west end', Offset(100, 213)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway A — near Office 102', Offset(200, 148)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway A — east zone', Offset(640, 148)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway B — east end', Offset(870, 208)),
    Equipment(EquipType.assembly, 'Assembly Point', 'Staircase 2 — Hallway A/B junction', Offset(487, 178)),
  ],
);

final _groundFloor = _FloorData(
  label: 'GROUND FLOOR',
  hallwayA: const Rect.fromLTWH(0, 135, 1000, 38),
  hallwayB: const Rect.fromLTWH(0, 192, 1000, 38),
  rooms: const [
    FloorRoom('STAIRCASE 1', Rect.fromLTWH(0, 0, 90, 135), subLabel: '(NORMAL)'),
    FloorRoom('RECEPTION', Rect.fromLTWH(92, 0, 118, 135)),
    FloorRoom('ADMIN\nOFFICE', Rect.fromLTWH(212, 0, 118, 135)),
    FloorRoom('STAIRCASE 2', Rect.fromLTWH(332, 0, 90, 135), subLabel: '(NORMAL)'),
    FloorRoom('PANTRY /\nCAFE', Rect.fromLTWH(424, 0, 120, 135)),
    FloorRoom('ELECTRICAL\nROOM', Rect.fromLTWH(546, 0, 118, 135)),
    FloorRoom('EMERGENCY EXIT\n(FIRE STAIRCASE)', Rect.fromLTWH(666, 0, 334, 135)),
    FloorRoom('WAITING\nAREA', Rect.fromLTWH(0, 230, 140, 110)),
    FloorRoom('MAIN\nENTRANCE', Rect.fromLTWH(142, 230, 110, 110)),
    FloorRoom('LOBBY', Rect.fromLTWH(254, 230, 160, 110)),
    FloorRoom('LOBBY', Rect.fromLTWH(440, 230, 70, 50)),
    FloorRoom('MEETING\nROOM', Rect.fromLTWH(514, 230, 176, 110)),
    FloorRoom('STORE\nROOM', Rect.fromLTWH(692, 230, 308, 110)),
  ],
  evacLines: [
    EvacLine(Offset(30, 154), Offset(970, 154)),
    EvacLine(Offset(30, 211), Offset(970, 211)),
    EvacLine(Offset(377, 135), Offset(377, 230)),
    EvacLine(Offset(30, 154), Offset(0, 154)),
    EvacLine(Offset(970, 154), Offset(1000, 154)),
    EvacLine(Offset(197, 340), Offset(197, 360)),
    EvacLine(Offset(490, 340), Offset(490, 360)),
    EvacLine(Offset(820, 340), Offset(820, 360)),
  ],
  equipment: [
    Equipment(EquipType.exit, 'EXIT 1', 'North-west — Staircase 1 (Normal)', Offset(18, 8)),
    Equipment(EquipType.exit, 'EXIT 3', 'North-east — Emergency Exit (Fire Staircase)', Offset(666, 8)),
    Equipment(EquipType.exit, 'EXIT 4', 'Street level — Main Entrance', Offset(155, 354)),
    Equipment(EquipType.exit, 'EXIT 5', 'Street level — Lobby', Offset(456, 354)),
    Equipment(EquipType.exit, 'EXIT 6', 'Street level — East exit', Offset(786, 354)),
    Equipment(EquipType.exit, 'EXIT 1', 'Street level — West exit', Offset(18, 354)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway A — near Admin Office', Offset(250, 144)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway A — near Electrical Room', Offset(620, 144)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway B — west centre', Offset(250, 202)),
    Equipment(EquipType.extinguisher, 'Fire Extinguisher', 'Hallway B — east wing', Offset(740, 202)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway A — near Reception', Offset(100, 140)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway A — near Emergency Exit', Offset(870, 140)),
    Equipment(EquipType.hoseReel, 'Fire Hose Reel', 'Hallway B — west end', Offset(100, 197)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway A — near Admin Office east', Offset(180, 135)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway B — near Lobby junction', Offset(377, 192)),
    Equipment(EquipType.callPoint, 'Manual Call Point', 'Hallway B — east centre', Offset(560, 192)),
    Equipment(EquipType.assembly, 'Assembly Point', 'Lobby — Hallway A/B junction', Offset(367, 164)),
    Equipment(EquipType.assembly, 'Assembly Point', 'Ground floor lobby entrance', Offset(300, 240)),
  ],
);


// ─── Equipment Map Widget (embeddable, no Scaffold/AppBar) ────────────────────
/// Embeddable version of the equipment map — no Scaffold, no AppBar.
/// Designed to be hosted inside the Digital Twin Map tab.
class EquipmentMapView extends StatefulWidget {
  const EquipmentMapView({super.key});

  @override
  State<EquipmentMapView> createState() => _EquipmentMapViewState();
}

class _EquipmentMapViewState extends State<EquipmentMapView>
    with SingleTickerProviderStateMixin {
  int _selectedFloor = 0; // 0=Ground, 1=1st, 2=2nd
  Equipment? _tapped;
  _NearestExitResult? _exitPath;
  late final AnimationController _pulse;

  final _floors      = [_groundFloor, _firstFloor, _secondFloor];
  final _floorLabels = ['Ground', '1st Floor', '2nd Floor'];

  double get _canvasH => _selectedFloor == 0 ? 420.0 : 360.0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final floor = _floors[_selectedFloor];
    return Column(
      children: [
        // ── Floor selector ──────────────────────────────────────────────
        Container(
          color: _C.surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              const Icon(Icons.layers_outlined, color: _C.peach, size: 16),
              const SizedBox(width: 8),
              const Text('Equipment Map',
                  style: TextStyle(color: _C.peach, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const Spacer(),
              ...List.generate(3, (i) {
                final active = i == _selectedFloor;
                return GestureDetector(
                  onTap: () => setState(() { _selectedFloor = i; _tapped = null; _exitPath = null; }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _C.peach : _C.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: active ? _C.peach : _C.border, width: active ? 0 : 1),
                    ),
                    child: Text(_floorLabels[i],
                        style: TextStyle(
                          color: active ? const Color(0xFF1A0A06) : _C.peach.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                );
              }),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showLegendSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _C.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _C.border),
                  ),
                  child: const Icon(Icons.info_outline, color: _C.peach, size: 16),
                ),
              ),
            ],
          ),
        ),

        // ── Map canvas ──────────────────────────────────────────────────
        Expanded(
          child: GestureDetector(
            onTapDown: (d) => _handleTap(d.localPosition, floor, context),
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AspectRatio(
                  aspectRatio: _selectedFloor == 0 ? 1000 / 420 : 1000 / 360,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _FloorPainter(
                        floor: floor,
                        tapped: _tapped,
                        pulseValue: _pulse.value,
                        exitPath: _exitPath,
                        canvasH: _canvasH,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── A* path banner ──────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          height: _exitPath != null ? 44 : 0,
          child: _exitPath != null
              ? _PathBanner(exit: _exitPath!.exit)
              : const SizedBox.shrink(),
        ),

        // ── Tooltip card ────────────────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          height: _tapped != null ? 88 : 0,
          child: _tapped != null
              ? _TooltipCard(
                  equipment: _tapped!,
                  onClose: () => setState(() { _tapped = null; _exitPath = null; }),
                )
              : const SizedBox.shrink(),
        ),

        // ── Legend strip ────────────────────────────────────────────────
        const _LegendStrip(),
      ],
    );
  }

  void _handleTap(Offset local, _FloorData floor, BuildContext context) {
    // Approximate canvas coordinate from tap position.
    // The map is inside an AspectRatio + Padding(8), so we subtract padding.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;

    // Header height: floor selector (~44) + padding
    const headerH = 44.0;
    const padding = 8.0;
    final mapH = size.height - headerH - padding * 2 - 44 - 88 - 32;
    final mapW = size.width - padding * 2;

    const canvasW = 1000.0;
    final scaleX = mapW / canvasW;
    final scaleY = mapH / _canvasH;

    final tapOnMap = Offset(local.dx - padding, local.dy - headerH - padding);
    final normX = tapOnMap.dx / scaleX;
    final normY = tapOnMap.dy / scaleY;

    Equipment? hit;
    double bestDist = 40;
    for (final eq in floor.equipment) {
      final d = (eq.pos - Offset(normX, normY)).distance;
      if (d < bestDist) { bestDist = d; hit = eq; }
    }

    if (hit != null) {
      final result = findNearestExit(hit.pos, floor, _canvasH);
      setState(() { _tapped = hit; _exitPath = result; });
    } else {
      setState(() { _tapped = null; _exitPath = null; });
    }
  }

  void _showLegendSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _LegendSheet(),
    );
  }
}

// ─── A* Path Banner ───────────────────────────────────────────────────────────
class _PathBanner extends StatelessWidget {
  const _PathBanner({required this.exit});
  final Equipment exit;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.pathColor.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        const Icon(Icons.route_outlined, color: _C.pathColor, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('Nearest exit: ${exit.label} — ${exit.location}',
            style: const TextStyle(color: _C.pathColor, fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ─── Tooltip card ─────────────────────────────────────────────────────────────
class _TooltipCard extends StatelessWidget {
  const _TooltipCard({required this.equipment, required this.onClose});
  final Equipment equipment;
  final VoidCallback onClose;

  Color _col(EquipType t) => switch (t) {
    EquipType.exit         => _C.exitGreen,
    EquipType.extinguisher => _C.extRed,
    EquipType.hoseReel     => _C.hoseOrg,
    EquipType.callPoint    => _C.mcpYellow,
    EquipType.assembly     => _C.apTeal,
  };

  IconData _icon(EquipType t) => switch (t) {
    EquipType.exit         => Icons.exit_to_app,
    EquipType.extinguisher => Icons.fire_extinguisher,
    EquipType.hoseReel     => Icons.water_damage,
    EquipType.callPoint    => Icons.warning_amber_rounded,
    EquipType.assembly     => Icons.people_alt,
  };

  @override
  Widget build(BuildContext context) {
    final col = _col(equipment.type);
    return Container(
      color: _C.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: col.withValues(alpha: 0.4)),
          ),
          child: Icon(_icon(equipment.type), color: col, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(equipment.label, style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(equipment.location,
                style: const TextStyle(color: _C.peach, fontSize: 11),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        )),
        GestureDetector(onTap: onClose,
            child: const Icon(Icons.close, color: _C.deepBrown, size: 18)),
      ]),
    );
  }
}

// ─── Legend strip ─────────────────────────────────────────────────────────────
class _LegendStrip extends StatelessWidget {
  const _LegendStrip();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _LegItem(color: _C.exitGreen,  label: 'Exit',         shape: _Shape.circle),
          _LegItem(color: _C.extRed,     label: 'Extinguisher', shape: _Shape.circle),
          _LegItem(color: _C.hoseOrg,    label: 'Hose Reel',    shape: _Shape.square),
          _LegItem(color: _C.mcpYellow,  label: 'Call Point',   shape: _Shape.triangle),
          _LegItem(color: _C.apTeal,     label: 'Assembly',     shape: _Shape.circle),
          _LegItem(color: _C.pathColor,  label: 'A* Path',      shape: _Shape.circle),
          const SizedBox(width: 8),
          CustomPaint(size: const Size(24, 8), painter: _DashPainter()),
          const SizedBox(width: 4),
          const Text('Evac route', style: TextStyle(color: _C.evac, fontSize: 9)),
        ]),
      ),
    );
  }
}

enum _Shape { circle, square, triangle }

class _LegItem extends StatelessWidget {
  const _LegItem({required this.color, required this.label, required this.shape});
  final Color color; final String label; final _Shape shape;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Row(children: [
      CustomPaint(size: const Size(10, 10), painter: _ShapePainter(color: color, shape: shape)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Color(0xFF9A7060), fontSize: 9)),
    ]),
  );
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter({required this.color, required this.shape});
  final Color color; final _Shape shape;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final c = Offset(size.width / 2, size.height / 2);
    switch (shape) {
      case _Shape.circle:   canvas.drawCircle(c, size.width / 2, p);
      case _Shape.square:   canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0,0,size.width,size.height), const Radius.circular(2)), p);
      case _Shape.triangle: canvas.drawPath(Path()..moveTo(c.dx,0)..lineTo(size.width,size.height)..lineTo(0,size.height)..close(), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = _C.evac..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height/2), Offset(math.min(x+5, size.width), size.height/2), p);
      x += 8;
    }
  }
  @override bool shouldRepaint(_) => false;
}

// ─── Legend bottom sheet ──────────────────────────────────────────────────────
class _LegendSheet extends StatelessWidget {
  const _LegendSheet();
  @override
  Widget build(BuildContext context) {
    final items = [
      (_C.exitGreen,  Icons.exit_to_app,           'Exit',               'Green marked exits on all floors'),
      (_C.extRed,     Icons.local_fire_department,  'Emergency Exit',     'Fire staircase — use during evacuation'),
      (_C.extRed,     Icons.fire_extinguisher,      'Fire Extinguisher',  'Located along hallways every ~15 m'),
      (_C.hoseOrg,    Icons.water_damage,           'Fire Hose Reel',     'Fixed at corridor ends and junctions'),
      (_C.mcpYellow,  Icons.warning_amber,          'Manual Call Point',  'Break glass to trigger fire alarm'),
      (_C.apTeal,     Icons.people_alt,             'Assembly Point',     'Gather here during evacuation'),
      (_C.evac,       Icons.route,                  'Evacuation Route',   'Green dashed path — follow to nearest exit'),
      (_C.pathColor,  Icons.route_outlined,         'A* Nearest Exit',    'Orange path — tap any equipment to see shortest route'),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('LEGEND', style: TextStyle(color: _C.peach, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2))),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => ListTile(
            dense: true,
            leading: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: item.$1.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(item.$2, color: item.$1, size: 18)),
            title: Text(item.$3, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(item.$4, style: const TextStyle(color: Color(0xFF9A7060), fontSize: 11)),
          )),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

// ─── Floor painter ────────────────────────────────────────────────────────────
class _FloorPainter extends CustomPainter {
  _FloorPainter({required this.floor, this.tapped, required this.pulseValue, this.exitPath, required this.canvasH});
  final _FloorData floor;
  final Equipment? tapped;
  final double pulseValue;
  final _NearestExitResult? exitPath;
  final double canvasH;

  @override
  void paint(Canvas canvas, Size size) {
    const canvasW = 1000.0;
    final scaleX = size.width / canvasW;
    final scaleY = size.height / canvasH;
    Offset s(Offset o) => Offset(o.dx * scaleX, o.dy * scaleY);
    Rect r(Rect rc) => Rect.fromLTWH(rc.left*scaleX, rc.top*scaleY, rc.width*scaleX, rc.height*scaleY);

    // Background
    final isGround = floor == _groundFloor;
    if (isGround) {
      canvas.drawRect(Rect.fromLTWH(0,0,size.width, 340*scaleY), Paint()..color = _C.card);
      canvas.drawRect(Rect.fromLTWH(0, 340*scaleY, size.width, size.height-340*scaleY), Paint()..color = const Color(0xFF0A0604));
      _text(canvas,'— STREET —', Offset(size.width/2,(340*scaleY+(size.height-340*scaleY)/2)), const Color(0xFF2E1A14), 9*scaleX, center:true);
    } else {
      canvas.drawRect(Rect.fromLTWH(0,0,size.width,size.height), Paint()..color = _C.card);
    }
    canvas.drawRect(Rect.fromLTWH(0,0,size.width,size.height).deflate(1),
        Paint()..color=_C.border..style=PaintingStyle.stroke..strokeWidth=1.5);

    // Hallways
    canvas.drawRect(r(floor.hallwayA), Paint()..color=_C.hallway);
    canvas.drawRect(r(floor.hallwayB), Paint()..color=_C.hallway);
    _text(canvas,'HALLWAY A', Offset(size.width*.35, floor.hallwayA.center.dy*scaleY), const Color(0xFF3A1F16), 7*scaleX);
    _text(canvas,'HALLWAY B', Offset(size.width*.35, floor.hallwayB.center.dy*scaleY), const Color(0xFF3A1F16), 7*scaleX);

    // Rooms
    for (final room in floor.rooms) {
      final rr = r(room.rect);
      canvas.drawRect(rr, Paint()..color=_C.roomFill);
      canvas.drawRect(rr, Paint()..color=_C.wall..style=PaintingStyle.stroke..strokeWidth=.8);
      final lines = room.label.split('\n');
      final lineH = 9.0*scaleY;
      var yOff = rr.center.dy - lines.length*lineH/2 + lineH/2;
      for (final line in lines) {
        _text(canvas, line, Offset(rr.center.dx, yOff), _C.roomText, 6.5*scaleX, center:true);
        yOff += lineH;
      }
      if (room.subLabel != null) {
        _text(canvas, room.subLabel!, Offset(rr.center.dx, yOff), _C.roomText.withValues(alpha:.7), 5.5*scaleX, center:true);
      }
    }

    // Floor label
    canvas.drawRect(Rect.fromLTWH(0,0,90*scaleX,18*scaleY), Paint()..color=const Color(0xFF2A1209));
    _text(canvas, floor.label, Offset(45*scaleX, 9*scaleY), _C.peach, 6*scaleX, bold:true, center:true);

    // Evac lines
    final evacPaint = Paint()..color=_C.evac.withValues(alpha:.65)..strokeWidth=1.4*scaleX..style=PaintingStyle.stroke;
    for (final line in floor.evacLines) {
      _dashedLine(canvas, s(line.a), s(line.b), evacPaint, 7*scaleX, 4*scaleX);
    }
    _arrow(canvas, s(const Offset(30,168)), s(const Offset(5,168)), evacPaint);

    // A* path
    if (exitPath != null && exitPath!.path.length > 1) {
      _drawPath(canvas, exitPath!.path, scaleX, scaleY, s);
    }

    // Equipment markers
    for (final eq in floor.equipment) {
      final sp = s(eq.pos);
      final isTapped = tapped == eq;
      final isTarget = exitPath != null && eq == exitPath!.exit;
      if (isTapped || isTarget) {
        final col = isTarget ? _C.pathColor : _colFor(eq.type);
        canvas.drawCircle(sp, (16+10*pulseValue)*scaleX,
            Paint()..color=col.withValues(alpha:.3*(1-pulseValue))..style=PaintingStyle.stroke..strokeWidth=2);
      }
      _drawEquip(canvas, eq.type, sp, scaleX, isTapped || isTarget);
    }
  }

  void _drawPath(Canvas canvas, List<Offset> path, double sx, double sy, Offset Function(Offset) s) {
    final scaled = path.map(s).toList();
    final glow = Paint()..color=_C.pathColor.withValues(alpha:.18)..strokeWidth=10*sx..strokeCap=StrokeCap.round..style=PaintingStyle.stroke;
    final obj = Path()..moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) { obj.lineTo(p.dx, p.dy); }
    canvas.drawPath(obj, glow);
    final main = Paint()..color=_C.pathColor..strokeWidth=3*sx..strokeCap=StrokeCap.round..style=PaintingStyle.stroke;
    const dash=12.0, gap=6.0, period=18.0;
    final shift = pulseValue * period;
    for (int i=0; i<scaled.length-1; i++) {
      _animDash(canvas, scaled[i], scaled[i+1], main, dash, gap, shift*sx);
    }
    if (scaled.length >= 2) _arrow(canvas, scaled[scaled.length-2], scaled.last, main);
    canvas.drawCircle(scaled.first, 5*sx, Paint()..color=_C.pathColor);
  }

  void _animDash(Canvas canvas, Offset a, Offset b, Paint paint, double dl, double gl, double shift) {
    final d = b-a; final total = d.distance;
    if (total==0) return;
    final dir = d/total;
    double dist = -shift % (dl+gl);
    bool drawing = dist >= 0;
    if (dist < 0) { dist += dl+gl; drawing=false; }
    while (dist < total) {
      final seg = math.min(drawing ? dl : gl, total-dist);
      if (drawing && dist+seg > 0) {
        canvas.drawLine(a+dir*math.max(0.0,dist), a+dir*(dist+seg), paint);
      }
      dist += seg; drawing = !drawing;
    }
  }

  void _drawEquip(Canvas canvas, EquipType type, Offset pos, double scale, bool hi) {
    final col = _colFor(type);
    final sz = hi ? 9.0*scale : 7.5*scale;
    switch (type) {
      case EquipType.exit:
        final rr = RRect.fromRectAndRadius(Rect.fromCenter(center:pos,width:32*scale,height:13*scale), Radius.circular(3*scale));
        canvas.drawRRect(rr, Paint()..color=col);
        _text(canvas,'★ EXIT',pos,const Color(0xFF052E0F),5.5*scale,bold:true,center:true);
      case EquipType.extinguisher:
        canvas.drawCircle(pos,sz,Paint()..color=col);
        _text(canvas,'E',pos,Colors.white,sz*.95,bold:true,center:true);
      case EquipType.hoseReel:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center:pos,width:sz*2,height:sz*2),Radius.circular(2*scale)),Paint()..color=col);
        _text(canvas,'H',pos,Colors.white,sz*.9,bold:true,center:true);
      case EquipType.callPoint:
        canvas.drawPath(Path()..moveTo(pos.dx,pos.dy-sz*1.2)..lineTo(pos.dx+sz,pos.dy+sz*.7)..lineTo(pos.dx-sz,pos.dy+sz*.7)..close(),Paint()..color=col);
        _text(canvas,'!',Offset(pos.dx,pos.dy+sz*.2),const Color(0xFF1A0800),sz*.95,bold:true,center:true);
      case EquipType.assembly:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center:pos,width:26*scale,height:16*scale),Radius.circular(3*scale)),Paint()..color=col);
        _text(canvas,'AP',pos,const Color(0xFF012E2A),5.5*scale,bold:true,center:true);
    }
  }

  Color _colFor(EquipType t) => switch(t) {
    EquipType.exit         => _C.exitGreen,
    EquipType.extinguisher => _C.extRed,
    EquipType.hoseReel     => _C.hoseOrg,
    EquipType.callPoint    => _C.mcpYellow,
    EquipType.assembly     => _C.apTeal,
  };

  void _text(Canvas canvas, String text, Offset pos, Color color, double fontSize,
      {bool bold=true, bool center=true}) {
    final tp = TextPainter(
      text: TextSpan(text:text, style:TextStyle(color:color, fontSize:fontSize.clamp(6,30),
          fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontFamily:'monospace')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? pos-Offset(tp.width/2,tp.height/2) : pos);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double dl, double gl) {
    final d=b-a; final total=d.distance; final dir=d/total;
    double dist=0; bool drawing=true;
    while (dist<total) {
      final seg=math.min(drawing?dl:gl,total-dist);
      if (drawing) canvas.drawLine(a+dir*dist,a+dir*(dist+seg),paint);
      dist+=seg; drawing=!drawing;
    }
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from,to,paint);
    final d=to-from; if(d.distance<1) return;
    final dir=d/d.distance; final left=Offset(-dir.dy,dir.dx);
    const sz=5.0;
    canvas.drawLine(to, to-dir*sz+left*sz*.5, paint);
    canvas.drawLine(to, to-dir*sz-left*sz*.5, paint);
  }

  @override
  bool shouldRepaint(_FloorPainter old) =>
      old.floor!=floor||old.tapped!=tapped||old.pulseValue!=pulseValue||old.exitPath!=exitPath;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API for external consumers (e.g. RiskHeatmapWidget)
// ─────────────────────────────────────────────────────────────────────────────

/// Canvas height for upper floors (1st / 2nd).
const double kUpperFloorCanvasH = 360.0;

/// Canvas height for ground floor.
const double kGroundFloorCanvasH = 420.0;

/// Canvas width (all floors).
const double kFloorCanvasW = 1000.0;

/// Returns the [CustomPainter] that draws the full hotel floor plan for
/// [floorIndex] (0 = Ground, 1 = 1st Floor, 2 = 2nd Floor).
///
/// [pulseValue] drives equipment pulse animations (0.0–1.0).
/// Pass 0.0 if you don't need animations.
CustomPainter hotelFloorPainter({
  required int floorIndex,
  double pulseValue = 0.0,
}) {
  final floors = [_groundFloor, _firstFloor, _secondFloor];
  final floor  = floors[floorIndex.clamp(0, 2)];
  final canvasH = floorIndex == 0 ? kGroundFloorCanvasH : kUpperFloorCanvasH;
  return _FloorPainter(
    floor: floor,
    pulseValue: pulseValue,
    canvasH: canvasH,
  );
}

/// Canvas height for [floorIndex] (0 = Ground → 420, else → 360).
double hotelFloorCanvasH(int floorIndex) =>
    floorIndex == 0 ? kGroundFloorCanvasH : kUpperFloorCanvasH;
