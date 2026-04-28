import 'package:flutter/material.dart';
import 'package:frontend/dashboard_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.emergencyCategory,   // null = normal map view, non-null = emergency mode
    this.roomNumber = '302',
    this.floorLabel = 'Floor 3',
    this.incidentId,          // used to cancel the incident on false alarm
  });

  final EmergencyCategory? emergencyCategory;
  final String roomNumber;
  final String floorLabel;
  final String? incidentId;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool _isCancellingAlarm = false;
  bool _alarmCancelled = false;

  bool get _isEmergencyMode => widget.emergencyCategory != null;

  String get _emergencyLabel {
    switch (widget.emergencyCategory) {
      case EmergencyCategory.fire:
        return 'FIRE REPORTED';
      case EmergencyCategory.medical:
        return 'MEDICAL SOS REPORTED';
      case EmergencyCategory.trapped:
        return 'TRAPPED — HELP REQUESTED';
      case EmergencyCategory.other:
        return 'EMERGENCY REPORTED';
      case null:
        return '';
    }
  }

  IconData get _emergencyIcon {
    switch (widget.emergencyCategory) {
      case EmergencyCategory.fire:
        return Icons.local_fire_department;
      case EmergencyCategory.medical:
        return Icons.medical_services;
      case EmergencyCategory.trapped:
        return Icons.door_front_door;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  // Cancels the incident in Supabase and updates the UI
  Future<void> _onFalseAlarm() async {
    if (_isCancellingAlarm) return;
    setState(() => _isCancellingAlarm = true);

    try {
      if (widget.incidentId != null) {
        // Update the incident row status to 'cancelled'
        // Admin sees this change instantly via their realtime subscription
        await Supabase.instance.client
            .from('incidents')
            .update({'status': 'cancelled'})
            .eq('id', widget.incidentId!);
      }

      if (!mounted) return;
      setState(() {
        _alarmCancelled = true;
        _isCancellingAlarm = false;
      });

      // Show confirmation then pop back to dashboard after 2 seconds
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('False alarm reported. Alert has been cancelled.'),
          backgroundColor: Color(0xFF2E7D32),
          duration: Duration(seconds: 2),
        ),
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCancellingAlarm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not cancel alert. Please inform hotel staff directly.',
          ),
          backgroundColor: Color(0xFFD63A23),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121110),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 20,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Emergency banner — only shown in emergency mode ──
                        if (_isEmergencyMode) ...[
                          const SizedBox(height: 8),
                          _EmergencyBanner(
                            label: _emergencyLabel,
                            icon: _emergencyIcon,
                            isCancelled: _alarmCancelled,
                          ),
                          const SizedBox(height: 8),
                        ],

                        const Spacer(flex: 1),
                        const _MapDisplayCard(),
                        const SizedBox(height: 8),
                        const _TopHudPill(),
                        const SizedBox(height: 10),
                        const _CurrentStepCard(),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            'EVACUATION STEPS',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const _StepsChecklistCard(),
                        const SizedBox(height: 20),

                        // ── Action buttons ──────────────────────────────────
                        _ActionButtonsRow(
                          isEmergencyMode: _isEmergencyMode,
                          isCancelled: _alarmCancelled,
                          isCancelling: _isCancellingAlarm,
                          onFalseAlarm: _onFalseAlarm,
                          onNeedHelp: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('SOS escalation triggered'),
                                backgroundColor: Color(0xFFD63A23),
                              ),
                            );
                          },
                        ),
                        const Spacer(flex: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Emergency banner shown at top when navigated from an emergency report ──
class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({
    required this.label,
    required this.icon,
    required this.isCancelled,
  });

  final String label;
  final IconData icon;
  final bool isCancelled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isCancelled
            ? const Color(0xFF1B5E20)   // green when cancelled
            : const Color(0xFFD63A23),  // red when active
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isCancelled ? Icons.check_circle : icon,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCancelled ? 'ALERT CANCELLED' : label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCancelled
                      ? 'You marked this as a false alarm.'
                      : 'Help is on the way — follow the route below.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopHudPill extends StatelessWidget {
  const _TopHudPill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1918),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFFFE45A).withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_circle_outlined,
              color: Color(0xFFFFE45A),
              size: 14,
            ),
            SizedBox(width: 8),
            Text(
              'PROCEED TO EXIT B  •  45s',
              style: TextStyle(
                color: Color(0xFFFFE45A),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapDisplayCard extends StatelessWidget {
  const _MapDisplayCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF1C1918),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 2.5,
          child: const SizedBox.expand(
            child: CustomPaint(painter: EvacuationMapPainter()),
          ),
        ),
      ),
    );
  }
}

class _CurrentStepCard extends StatelessWidget {
  const _CurrentStepCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1C1918),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCE3C),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'STEP 2',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 9,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'TURN LEFT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            children: [
              Icon(Icons.arrow_back, color: Color(0xFF8DF0A2), size: 18),
              SizedBox(width: 6),
              Text(
                '10 meters ahead',
                style: TextStyle(
                  color: Color(0xFF8DF0A2),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepsChecklistCard extends StatelessWidget {
  const _StepsChecklistCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1918),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          _StepRow(
            icon: Icons.check,
            iconColor: Color(0xFF8DF0A2),
            text: 'Exit Room 302',
            isDimmed: true,
          ),
          _StepRow(
            icon: Icons.circle,
            iconColor: Color(0xFFFFB020),
            text: 'Turn Left',
            isDimmed: false,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: Color(0x0AFFFFFF)),
          ),
          _StepRow(
            icon: Icons.circle,
            iconColor: Color(0xFF545861),
            text: 'Use Stairwell B',
            isDimmed: true,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.isDimmed,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final bool isDimmed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 14),
          Text(
            text,
            style: TextStyle(
              color: isDimmed ? Colors.white24 : Colors.white,
              fontSize: 15,
              fontWeight: isDimmed ? FontWeight.w400 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action buttons — change based on emergency mode ────────────────────────
class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.isEmergencyMode,
    required this.isCancelled,
    required this.isCancelling,
    required this.onFalseAlarm,
    required this.onNeedHelp,
  });

  final bool isEmergencyMode;
  final bool isCancelled;
  final bool isCancelling;
  final VoidCallback onFalseAlarm;
  final VoidCallback onNeedHelp;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton(
              // In emergency mode: left button = FALSE ALARM
              // In normal mode:   left button = I'M SAFE
              onPressed: isEmergencyMode
                  ? (isCancelled || isCancelling ? null : onFalseAlarm)
                  : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: isEmergencyMode
                    ? const Color(0xFF8DF0A2)
                    : Colors.white70,
                side: BorderSide(
                  color: isEmergencyMode
                      ? const Color(0xFF8DF0A2).withValues(alpha: 0.5)
                      : Colors.white10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isCancelling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF8DF0A2),
                      ),
                    )
                  : Text(
                      isEmergencyMode
                          ? (isCancelled ? 'CANCELLED' : 'FALSE ALARM')
                          : "I'M SAFE",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onNeedHelp,
              icon: const Icon(Icons.sensors, size: 18),
              label: const Text(
                'NEED HELP',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD63A23),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Map painter — unchanged from original ──────────────────────────────────
class EvacuationMapPainter extends CustomPainter {
  const EvacuationMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1C1918),
    );

    final gridPaint = Paint()
      ..color = const Color(0xFF5F6673).withValues(alpha: 0.1);

    for (
      double x = 0.18 * size.width;
      x < size.width * 0.95;
      x += size.width * 0.18
    ) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (
      double y = 0.15 * size.height;
      y < size.height * 0.95;
      y += size.height * 0.15
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final hallwayDark = Paint()
      ..color = const Color(0xFF322E2D)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;

    final hallwayPath = Path()
      ..moveTo(size.width * 0.17, size.height * 0.92)
      ..lineTo(size.width * 0.17, size.height * 0.12)
      ..lineTo(size.width * 0.84, size.height * 0.12)
      ..lineTo(size.width * 0.84, size.height * 0.94);
    canvas.drawPath(hallwayPath, hallwayDark);

    final pathNeon = Paint()
      ..color = const Color(0xFF7CF29D)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final p1 = Offset(size.width * 0.17, size.height * 0.62);
    final p2 = Offset(size.width * 0.50, size.height * 0.62);
    final p3 = Offset(size.width * 0.50, size.height * 0.44);
    final p4 = Offset(size.width * 0.84, size.height * 0.44);
    final p5 = Offset(size.width * 0.84, size.height * 0.16);

    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..lineTo(p5.dx, p5.dy),
      pathNeon,
    );

    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.62),
      6,
      Paint()..color = const Color(0xFFFF5A3E),
    );

    _paintText(
      canvas,
      'YOU ARE HERE',
      Offset(size.width * 0.25, size.height * 0.55),
      const TextStyle(
        color: Color(0xFFB5F5C6),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
    _paintText(
      canvas,
      'EXIT B',
      Offset(size.width * 0.81, size.height * 0.04),
      const TextStyle(
        color: Color(0xFFFFE26A),
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextStyle style) {
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}