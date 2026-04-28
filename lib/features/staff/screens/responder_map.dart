import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';

class ResponderMapPage extends StatelessWidget {
  const ResponderMapPage({
    super.key,
    this.room = 'Room 302',
    this.floor = 'Floor 3',
    // FIX #5: equipmentMode flag — delegates to full EquipmentMapPage
    this.equipmentMode = false,
  });

  final String room;
  final String floor;
  final bool equipmentMode; // FIX #5

  @override
  Widget build(BuildContext context) {
    // equipmentMode now delegates to the rich EquipmentMapPage
    if (equipmentMode) {
      return const EquipmentMapPage();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('NAVIGATING TO ${room.toUpperCase()}'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: _NavigationView(room: room, floor: floor),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Equipment Map — full interactive floor-plan with 3-floor selector,
// zoomable canvas, tap-to-identify markers, evac routes, and legend.
// ─────────────────────────────────────────────────────────────────────────────

// ─── App colours ─────────────────────────────────────────────────────────────
class _C {
  static const bg        = Color(0xFF0F0A09);
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
  static const white     = Colors.white;
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
  final Offset pos;
}

class EvacLine {
  const EvacLine(this.a, this.b);
  final Offset a, b;
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

// ─── Page ──────────────────────────────────────────────────────────────────────

class EquipmentMapPage extends StatefulWidget {
  const EquipmentMapPage({super.key});

  @override
  State<EquipmentMapPage> createState() => _EquipmentMapPageState();
}

class _EquipmentMapPageState extends State<EquipmentMapPage>
    with SingleTickerProviderStateMixin {
  int _selectedFloor = 1;
  Equipment? _tapped;
  late final AnimationController _pulse;

  final _floors = [_groundFloor, _firstFloor, _secondFloor];
  final _floorLabels = ['Ground', '1st Floor', '2nd Floor'];

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

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        backgroundColor: _C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _C.peach, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'EQUIPMENT MAP',
          style: TextStyle(
            color: _C.peach,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: _C.peach, size: 20),
            onPressed: () => _showLegendSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Floor selector ──────────────────────────────────────────────────
          Container(
            color: _C.surface,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: List.generate(3, (i) {
                final active = i == _selectedFloor;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedFloor = i;
                      _tapped = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: active ? _C.peach : _C.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? _C.peach : _C.border,
                          width: active ? 0 : 1,
                        ),
                      ),
                      child: Text(
                        _floorLabels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF1A0A06)
                              : _C.peach.withOpacity(0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Map ─────────────────────────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onTapDown: (d) => _handleTap(d.localPosition, floor, context),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(
                    aspectRatio: _selectedFloor == 0 ? 1000 / 420 : 1000 / 360,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => CustomPaint(
                        painter: _FloorPainter(
                          floor: floor,
                          tapped: _tapped,
                          pulseValue: _pulse.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Tooltip bottom card ─────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: _tapped != null ? 90 : 0,
            child: _tapped != null
                ? _TooltipCard(
                    equipment: _tapped!,
                    onClose: () => setState(() => _tapped = null),
                  )
                : const SizedBox.shrink(),
          ),

          // ── Mini legend strip ───────────────────────────────────────────────
          _LegendStrip(),
        ],
      ),
    );
  }

  void _handleTap(Offset local, _FloorData floor, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final size = box.size;
    final mapH = size.height - 42 -
        (MediaQuery.of(context).padding.top + kToolbarHeight) -
        90 -
        48;
    final mapW = size.width - 24;
    final canvasH = _selectedFloor == 0 ? 420.0 : 360.0;
    const canvasW = 1000.0;

    final scaleX = mapW / canvasW;
    final scaleY = mapH / canvasH;

    final tabsH = 42.0;
    final appBarH = kToolbarHeight + MediaQuery.of(context).padding.top;
    final tapOnMap = Offset(local.dx - 12, local.dy - appBarH - tabsH - 12);

    final normX = tapOnMap.dx / scaleX;
    final normY = tapOnMap.dy / scaleY;

    Equipment? hit;
    double bestDist = 40;
    for (final eq in floor.equipment) {
      final d = (eq.pos - Offset(normX, normY)).distance;
      if (d < bestDist) {
        bestDist = d;
        hit = eq;
      }
    }
    setState(() => _tapped = hit);
  }

  void _showLegendSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _LegendSheet(),
    );
  }
}

// ─── CustomPainter ────────────────────────────────────────────────────────────

class _FloorPainter extends CustomPainter {
  _FloorPainter({required this.floor, this.tapped, required this.pulseValue});

  final _FloorData floor;
  final Equipment? tapped;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasH = floor == _groundFloor ? 420.0 : 360.0;
    const canvasW = 1000.0;

    final scaleX = size.width / canvasW;
    final scaleY = size.height / canvasH;

    Offset s(Offset o) => Offset(o.dx * scaleX, o.dy * scaleY);
    Rect r(Rect rc) => Rect.fromLTWH(
          rc.left * scaleX, rc.top * scaleY,
          rc.width * scaleX, rc.height * scaleY);

    final outerRect = Rect.fromLTWH(0, 0, size.width, size.height);
    if (floor == _groundFloor) {
      final buildH = 340 * scaleY;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, buildH),
        Paint()..color = _C.card,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, buildH, size.width, size.height - buildH),
        Paint()..color = const Color(0xFF0A0604),
      );
      _drawText(
        canvas,
        '— STREET —',
        Offset(size.width / 2, buildH + (size.height - buildH) / 2),
        const Color(0xFF2E1A14),
        9 * scaleX,
        bold: false,
        center: true,
      );
    } else {
      canvas.drawRect(outerRect, Paint()..color = _C.card);
    }
    canvas.drawRect(
      outerRect.deflate(1),
      Paint()
        ..color = _C.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final hallPaint = Paint()..color = _C.hallway;
    canvas.drawRect(r(floor.hallwayA), hallPaint);
    canvas.drawRect(r(floor.hallwayB), hallPaint);

    _drawText(canvas, 'HALLWAY A',
        Offset(size.width * .35, floor.hallwayA.center.dy * scaleY),
        const Color(0xFF3A1F16), 7 * scaleX, bold: false);
    _drawText(canvas, 'HALLWAY B',
        Offset(size.width * .35, floor.hallwayB.center.dy * scaleY),
        const Color(0xFF3A1F16), 7 * scaleX, bold: false);

    final roomPaint = Paint()..color = _C.roomFill;
    final roomBorder = Paint()
      ..color = _C.wall
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;

    for (final room in floor.rooms) {
      final rr = r(room.rect);
      canvas.drawRect(rr, roomPaint);
      canvas.drawRect(rr, roomBorder);
      final lines = room.label.split('\n');
      final lineH = 9.0 * scaleY;
      final totalH =
          lines.length * lineH + (room.subLabel != null ? lineH * .9 : 0);
      var yOff = rr.center.dy - totalH / 2 + lineH / 2;
      for (final line in lines) {
        _drawText(canvas, line, Offset(rr.center.dx, yOff), _C.roomText,
            6.5 * scaleX, bold: false, center: true);
        yOff += lineH;
      }
      if (room.subLabel != null) {
        _drawText(canvas, room.subLabel!, Offset(rr.center.dx, yOff),
            _C.roomText.withOpacity(.7), 5.5 * scaleX,
            bold: false, center: true);
      }
    }

    if (floor == _groundFloor) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 90 * scaleX, 18 * scaleY),
        Paint()..color = const Color(0xFF2A1209),
      );
      _drawText(canvas, 'GROUND FLOOR', Offset(45 * scaleX, 9 * scaleY),
          _C.peach, 6 * scaleX, bold: true, center: true);
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 78 * scaleX, 16 * scaleY),
        Paint()..color = const Color(0xFF2A1209),
      );
      _drawText(canvas, floor.label, Offset(39 * scaleX, 8 * scaleY),
          _C.peach, 6 * scaleX, bold: true, center: true);
    }

    final evacPaint = Paint()
      ..color = _C.evac.withOpacity(.65)
      ..strokeWidth = 1.4 * scaleX
      ..style = PaintingStyle.stroke;

    for (final line in floor.evacLines) {
      _drawDashedLine(
          canvas, s(line.a), s(line.b), evacPaint, 7 * scaleX, 4 * scaleX);
    }

    _drawArrow(canvas, s(const Offset(30, 168)), s(const Offset(5, 168)), evacPaint);
    if (floor != _groundFloor) {
      _drawArrow(
          canvas, s(const Offset(970, 168)), s(const Offset(995, 168)), evacPaint);
    }

    for (final eq in floor.equipment) {
      final sp = s(eq.pos);
      final isTapped = tapped == eq;
      if (isTapped) {
        final radius = (16 + 10 * pulseValue) * scaleX;
        canvas.drawCircle(
          sp,
          radius,
          Paint()
            ..color =
                _colorForType(eq.type).withOpacity(.3 * (1 - pulseValue))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      _drawEquipment(canvas, eq.type, sp, scaleX, isTapped);
    }
  }

  void _drawEquipment(
      Canvas canvas, EquipType type, Offset pos, double scale, bool highlighted) {
    final col = _colorForType(type);
    final sz = highlighted ? 9.0 * scale : 7.5 * scale;

    switch (type) {
      case EquipType.exit:
        final w = 32 * scale, h = 13 * scale;
        final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: w, height: h),
          Radius.circular(3 * scale),
        );
        canvas.drawRRect(rr, Paint()..color = col);
        _drawText(canvas, '★ EXIT', pos, const Color(0xFF052E0F), 5.5 * scale,
            bold: true, center: true);
        break;

      case EquipType.extinguisher:
        canvas.drawCircle(pos, sz, Paint()..color = col);
        _drawText(canvas, 'E', pos, Colors.white, sz * .95,
            bold: true, center: true);
        break;

      case EquipType.hoseReel:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pos, width: sz * 2, height: sz * 2),
            Radius.circular(2 * scale),
          ),
          Paint()..color = col,
        );
        _drawText(canvas, 'H', pos, Colors.white, sz * .9,
            bold: true, center: true);
        break;

      case EquipType.callPoint:
        final path = Path()
          ..moveTo(pos.dx, pos.dy - sz * 1.2)
          ..lineTo(pos.dx + sz, pos.dy + sz * .7)
          ..lineTo(pos.dx - sz, pos.dy + sz * .7)
          ..close();
        canvas.drawPath(path, Paint()..color = col);
        _drawText(canvas, '!', Offset(pos.dx, pos.dy + sz * .2),
            const Color(0xFF1A0800), sz * .95, bold: true, center: true);
        break;

      case EquipType.assembly:
        final w = 26 * scale, h = 16 * scale;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pos, width: w, height: h),
            Radius.circular(3 * scale),
          ),
          Paint()..color = col,
        );
        _drawText(canvas, 'AP', pos, const Color(0xFF012E2A), 5.5 * scale,
            bold: true, center: true);
        break;
    }
  }

  Color _colorForType(EquipType t) => switch (t) {
        EquipType.exit => _C.exitGreen,
        EquipType.extinguisher => _C.extRed,
        EquipType.hoseReel => _C.hoseOrg,
        EquipType.callPoint => _C.mcpYellow,
        EquipType.assembly => _C.apTeal,
      };

  void _drawText(
    Canvas canvas,
    String text,
    Offset pos,
    Color color,
    double fontSize, {
    bool bold = true,
    bool center = true,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize.clamp(6, 30),
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      center ? pos - Offset(tp.width / 2, tp.height / 2) : pos,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      double dashLen, double gapLen) {
    final d = b - a;
    final total = d.distance;
    final dir = d / total;
    double dist = 0;
    bool drawing = true;
    while (dist < total) {
      final segLen = math.min(drawing ? dashLen : gapLen, total - dist);
      if (drawing) {
        canvas.drawLine(a + dir * dist, a + dir * (dist + segLen), paint);
      }
      dist += segLen;
      drawing = !drawing;
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from, to, paint);
    final dir = (to - from) / (to - from).distance;
    final left = Offset(-dir.dy, dir.dx);
    const arrowSize = 5.0;
    final tip = to;
    canvas.drawLine(tip, tip - dir * arrowSize + left * arrowSize * .5, paint);
    canvas.drawLine(tip, tip - dir * arrowSize - left * arrowSize * .5, paint);
  }

  @override
  bool shouldRepaint(_FloorPainter old) =>
      old.floor != floor || old.tapped != tapped || old.pulseValue != pulseValue;
}

// ─── Tooltip card ─────────────────────────────────────────────────────────────

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({required this.equipment, required this.onClose});

  final Equipment equipment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final col = _colorForType(equipment.type);
    return Container(
      color: _C.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: col.withOpacity(.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: col.withOpacity(.4)),
            ),
            child: Icon(_iconForType(equipment.type), color: col, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(equipment.label,
                    style: TextStyle(
                        color: col,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(equipment.location,
                    style: const TextStyle(
                        color: _C.peach,
                        fontSize: 11,
                        fontWeight: FontWeight.w400),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, color: _C.deepBrown, size: 18),
          ),
        ],
      ),
    );
  }

  Color _colorForType(EquipType t) => switch (t) {
        EquipType.exit => _C.exitGreen,
        EquipType.extinguisher => _C.extRed,
        EquipType.hoseReel => _C.hoseOrg,
        EquipType.callPoint => _C.mcpYellow,
        EquipType.assembly => _C.apTeal,
      };

  IconData _iconForType(EquipType t) => switch (t) {
        EquipType.exit => Icons.exit_to_app,
        EquipType.extinguisher => Icons.fire_extinguisher,
        EquipType.hoseReel => Icons.water_damage,
        EquipType.callPoint => Icons.warning_amber_rounded,
        EquipType.assembly => Icons.people_alt,
      };
}

// ─── Legend strip ─────────────────────────────────────────────────────────────

class _LegendStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _LegItem(color: _C.exitGreen, label: 'Exit', shape: _Shape.circle),
            _LegItem(
                color: _C.extRed, label: 'Extinguisher', shape: _Shape.circle),
            _LegItem(
                color: _C.hoseOrg, label: 'Hose Reel', shape: _Shape.square),
            _LegItem(
                color: _C.mcpYellow,
                label: 'Call Point',
                shape: _Shape.triangle),
            _LegItem(
                color: _C.apTeal, label: 'Assembly', shape: _Shape.circle),
            const SizedBox(width: 8),
            CustomPaint(
                size: const Size(24, 8), painter: _DashPainter()),
            const SizedBox(width: 4),
            const Text('Evac route',
                style: TextStyle(color: _C.evac, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

enum _Shape { circle, square, triangle }

class _LegItem extends StatelessWidget {
  const _LegItem(
      {required this.color, required this.label, required this.shape});
  final Color color;
  final String label;
  final _Shape shape;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          CustomPaint(
            size: const Size(10, 10),
            painter: _ShapePainter(color: color, shape: shape),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF9A7060), fontSize: 9)),
        ],
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter({required this.color, required this.shape});
  final Color color;
  final _Shape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final c = Offset(size.width / 2, size.height / 2);
    switch (shape) {
      case _Shape.circle:
        canvas.drawCircle(c, size.width / 2, p);
        break;
      case _Shape.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height),
            const Radius.circular(2),
          ),
          p,
        );
        break;
      case _Shape.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, 0)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close(),
          p,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _C.evac
      ..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2),
          Offset(math.min(x + 5, size.width), size.height / 2), p);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Legend bottom sheet ──────────────────────────────────────────────────────

class _LegendSheet extends StatelessWidget {
  const _LegendSheet();

  @override
  Widget build(BuildContext context) {
    final items = [
      (_C.exitGreen, Icons.exit_to_app, 'Exit (Evacuation Exit)',
          'Green marked exits on all floors'),
      (_C.exitGreen, Icons.stairs, 'Staircase (Normal)',
          'Standard staircases for daily use'),
      (_C.extRed, Icons.local_fire_department, 'Emergency Exit',
          'Fire staircase — use during evacuation'),
      (_C.extRed, Icons.fire_extinguisher, 'Fire Extinguisher',
          'Located along hallways every ~15 m'),
      (_C.hoseOrg, Icons.water_damage, 'Fire Hose Reel',
          'Fixed at corridor ends and junctions'),
      (_C.mcpYellow, Icons.warning_amber, 'Manual Call Point',
          'Break glass to trigger fire alarm'),
      (_C.apTeal, Icons.people_alt, 'Assembly Point',
          'Gather here during evacuation'),
      (_C.evac, Icons.route, 'Evacuation Route',
          'Green dashed path — follow to nearest exit'),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: _C.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('LEGEND',
                  style: TextStyle(
                      color: _C.peach,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2)),
            ]),
          ),
          const SizedBox(height: 12),
          ...items.map((item) => ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.$1.withOpacity(.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.$2, color: item.$1, size: 18),
                ),
                title: Text(item.$3,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(item.$4,
                    style: const TextStyle(
                        color: Color(0xFF9A7060), fontSize: 11)),
              )),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NOTES',
                      style: TextStyle(
                          color: _C.peach,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 8),
                  for (final note in [
                    'Each floor has Hallway A & B as alternative evacuation paths.',
                    'If one hallway is blocked, use the other.',
                    'In case of fire, use nearest exit following the green path.',
                    'Do not use the lift during evacuation.',
                    'Assemble at the designated assembly point.',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  color: _C.peach, fontSize: 11)),
                          Expanded(
                            child: Text(note,
                                style: const TextStyle(
                                    color: Color(0xFF9A7060),
                                    fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Equipment location view — shows floor schematic + equipment list
// ─────────────────────────────────────────────────────────────────────────────

class _EquipmentLocationView extends StatelessWidget {
  const _EquipmentLocationView({
    required this.floor,
    required this.items,
  });

  final String floor;
  final List<_EquipmentItem> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Floor schematic header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EQUIPMENT LOCATIONS',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    floor,
                    style: const TextStyle(
                      color: Color(0xFF7CF29D),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Schematic map grid (placeholder — replace with Image.asset or
          // an interactive FlutterMap widget when floor-plan assets exist)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'FLOOR SCHEMATIC',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: CustomPaint(
                        painter: _FloorPlanPainter(items: items),
                        child: const Center(
                          child: Text(
                            'Floor Plan',
                            style: TextStyle(
                              color: Colors.white12,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Equipment list
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ALL EQUIPMENT',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...items.map((e) => _EquipmentRow(item: e)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentItem {
  const _EquipmentItem({
    required this.label,
    required this.icon,
    required this.location,
  });

  final String label;
  final IconData icon;
  final String location;
}

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({required this.item});

  final _EquipmentItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(item.location,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24),
        ],
      ),
    );
  }
}

/// Simple painter that draws coloured dots for each equipment item
/// at pseudo-random positions across the floor plan canvas.
class _FloorPlanPainter extends CustomPainter {
  const _FloorPlanPainter({required this.items});

  final List<_EquipmentItem> items;

  static const _positions = [
    Offset(0.12, 0.25),
    Offset(0.30, 0.60),
    Offset(0.48, 0.20),
    Offset(0.55, 0.70),
    Offset(0.68, 0.35),
    Offset(0.78, 0.65),
    Offset(0.88, 0.20),
    Offset(0.20, 0.78),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Room outline
    final wallPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.05, size.height * 0.08,
            size.width * 0.9, size.height * 0.84),
        wallPaint);

    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < items.length && i < _positions.length; i++) {
      final p = _positions[i];
      final center = Offset(p.dx * size.width, p.dy * size.height);
      dotPaint.color = const Color(0xFFE8F5A3).withValues(alpha: 0.85);
      canvas.drawCircle(center, 7, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Original nav UI — unchanged, extracted into its own widget
// ─────────────────────────────────────────────────────────────────────────────

class _NavigationView extends StatelessWidget {
  const _NavigationView({required this.room, required this.floor});

  final String room;
  final String floor;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TURN LEFT',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '10 meters ahead',
                    style: TextStyle(
                      color: Color(0xFF7CF29D),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TASK LIST • $floor',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TaskRow(
                    text: 'Arrive at $room',
                    completed: true,
                  ),
                  const _TaskRow(text: 'Assist Guest', completed: false),
                  const _TaskRow(text: 'Clear Room', completed: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StandardButton(
                  label: 'NEED BACKUP',
                  isOutlined: true,
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StandardButton(
                  label: 'ROOM CLEARED',
                  onPressed: () {},
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.text, required this.completed});

  final String text;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.pending,
            color: completed ? const Color(0xFF7CF29D) : Colors.white54,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(color: completed ? Colors.white : Colors.white70),
          ),
        ],
      ),
    );
  }
}