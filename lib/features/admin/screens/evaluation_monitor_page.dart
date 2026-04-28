import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/features/admin/providers/evaluation_provider.dart';
import 'package:frontend/features/admin/widgets/equipment_map.dart';
import 'package:provider/provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Evaluation Monitor — root widget
// ─────────────────────────────────────────────────────────────────────────────

/// Drop-in replacement for the evacuationMonitor placeholder panel.
/// Wrap with ChangeNotifierProvider<EvaluationProvider> at the call site,
/// or provide it higher up in the tree.
class EvaluationMonitorPage extends StatelessWidget {
  const EvaluationMonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EvaluationProvider>(
      create: (_) => EvaluationProvider(),
      child: const _EvaluationMonitorBody(),
    );
  }
}

class _EvaluationMonitorBody extends StatelessWidget {
  const _EvaluationMonitorBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<EvaluationProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              _HeaderRow(provider: provider),
              const SizedBox(height: 20),

              // ── Top metrics ─────────────────────────────────────────────
              _MetricsRow(provider: provider),
              const SizedBox(height: 20),

              // ── Middle: heatmap + risk summary ───────────────────────────
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 800;
                if (wide) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 2, child: RiskHeatmapWidget(provider: provider)),
                        const SizedBox(width: 14),
                        Expanded(flex: 1, child: RiskSummaryCard(provider: provider)),
                      ],
                    ),
                  );
                }
                return Column(children: [
                  RiskHeatmapWidget(provider: provider),
                  const SizedBox(height: 14),
                  RiskSummaryCard(provider: provider),
                ]);
              }),
              const SizedBox(height: 20),

              // ── Bottom: evaluations, trends, actions ─────────────────────
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: EvaluationList(provider: provider)),
                      const SizedBox(width: 14),
                      Expanded(child: TrendChartWidget(provider: provider)),
                      const SizedBox(width: 14),
                      Expanded(child: ActionListCard(provider: provider)),
                    ],
                  );
                }
                return Column(children: [
                  EvaluationList(provider: provider),
                  const SizedBox(height: 14),
                  TrendChartWidget(provider: provider),
                  const SizedBox(height: 14),
                  ActionListCard(provider: provider),
                ]);
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header row
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.provider});
  final EvaluationProvider provider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Evaluation Monitor',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('Real-time safety evaluation and risk assessment',
                  style: TextStyle(fontSize: 12, color: Colors.white38)),
            ],
          ),
        ),
        // Live chip
        GestureDetector(
          onTap: provider.toggleLive,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: provider.isLive
                  ? const Color(0xFF81C784).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: provider.isLive
                      ? const Color(0xFF81C784).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: provider.isLive ? const Color(0xFF81C784) : Colors.white38,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(provider.isLive ? 'Live' : 'Paused',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: provider.isLive ? const Color(0xFF81C784) : Colors.white38)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // Filter button
        _IconBtn(icon: Icons.filter_list_rounded, tooltip: 'Filter', onTap: () {}),
        // Refresh button
        _IconBtn(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: provider.refresh),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon; final String tooltip; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, size: 17, color: Colors.white54),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics row — 5 cards
// ─────────────────────────────────────────────────────────────────────────────

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.provider});
  final EvaluationProvider provider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      final cards = [
        MetricCard.circular(
          label: 'Overall Safety Score',
          value: provider.safetyScore,
          sublabel: _scoreLabel(provider.safetyScore),
          color: _scoreColor(provider.safetyScore),
        ),
        MetricCard.count(
          label: 'Active Incidents',
          value: provider.activeIncidentCount,
          sublabel: provider.incidentSubtext,
          color: const Color(0xFFEF4444),
          icon: Icons.warning_amber_rounded,
        ),
        MetricCard.count(
          label: 'Affected Areas',
          value: provider.affectedAreas,
          sublabel: 'Floors / Zones',
          color: const Color(0xFFFFB74D),
          icon: Icons.location_on_outlined,
        ),
        MetricCard.count(
          label: 'Evacuated',
          value: provider.evacuatedCount,
          sublabel: 'People',
          color: const Color(0xFF64B5F6),
          icon: Icons.directions_run_rounded,
        ),
        MetricCard.status(
          label: 'System Status',
          operational: provider.systemOperational,
        ),
      ];

      if (wide) {
        return Row(
          children: cards.map((c) => Expanded(child: Padding(
            padding: EdgeInsets.only(right: cards.indexOf(c) < cards.length - 1 ? 10 : 0),
            child: c,
          ))).toList(),
        );
      }
      return GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 1.4,
        children: cards,
      );
    });
  }

  String _scoreLabel(int score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 60) return 'Fair';
    return 'Poor';
  }

  Color _scoreColor(int score) {
    if (score >= 90) return const Color(0xFF81C784);
    if (score >= 75) return AppColors.accent;
    if (score >= 60) return const Color(0xFFFFB74D);
    return const Color(0xFFEF4444);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MetricCard — reusable widget with 3 variants
// ─────────────────────────────────────────────────────────────────────────────

class MetricCard extends StatelessWidget {
  const MetricCard._({
    required this.label,
    required this.color,
    required this.child,
  });

  factory MetricCard.circular({
    required String label,
    required int value,
    required String sublabel,
    required Color color,
  }) => MetricCard._(
    label: label, color: color,
    child: _CircularMetric(value: value, sublabel: sublabel, color: color),
  );

  factory MetricCard.count({
    required String label,
    required int value,
    required String sublabel,
    required Color color,
    required IconData icon,
  }) => MetricCard._(
    label: label, color: color,
    child: _CountMetric(value: value, sublabel: sublabel, color: color, icon: icon),
  );

  factory MetricCard.status({
    required String label,
    required bool operational,
  }) => MetricCard._(
    label: label,
    color: operational ? const Color(0xFF81C784) : const Color(0xFFEF4444),
    child: _StatusMetric(operational: operational),
  );

  final String label;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CircularMetric extends StatelessWidget {
  const _CircularMetric({required this.value, required this.sublabel, required this.color});
  final int value; final String sublabel; final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
        width: 52, height: 52,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: value / 100,
            strokeWidth: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(sublabel,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color))),
    ]);
  }
}

class _CountMetric extends StatelessWidget {
  const _CountMetric({required this.value, required this.sublabel, required this.color, required this.icon});
  final int value; final String sublabel; final Color color; final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color, height: 1)),
        Text(sublabel, style: const TextStyle(fontSize: 10, color: Colors.white38)),
      ]),
    ]);
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({required this.operational});
  final bool operational;

  @override
  Widget build(BuildContext context) {
    final color = operational ? const Color(0xFF81C784) : const Color(0xFFEF4444);
    return Row(children: [
      Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]),
      ),
      const SizedBox(width: 8),
      Text(operational ? 'Operational' : 'Degraded',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Risk Heatmap Widget
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Risk Heatmap Widget — uses the real hotel floor map painter
// ─────────────────────────────────────────────────────────────────────────────

class RiskHeatmapWidget extends StatefulWidget {
  const RiskHeatmapWidget({super.key, required this.provider});
  final EvaluationProvider provider;

  @override
  State<RiskHeatmapWidget> createState() => _RiskHeatmapWidgetState();
}

class _RiskHeatmapWidgetState extends State<RiskHeatmapWidget>
    with SingleTickerProviderStateMixin {
  RiskArea? _hovered;
  int _floorIndex = 2; // default: 2nd floor
  late final AnimationController _pulse;
  final TransformationController _transformCtrl = TransformationController();

  static const _floorLabels = ['Ground', '1st Floor', '2nd Floor'];

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
    _transformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Canvas dimensions for the selected floor
    final canvasH = hotelFloorCanvasH(_floorIndex);
    const canvasW = kFloorCanvasW;
    final aspectRatio = canvasW / canvasH;

    return _EvalCard(
      title: 'Risk Heatmap',
      subtitle: 'Live risk assessment by area',
      icon: Icons.map_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Controls row ────────────────────────────────────────────────
          Row(children: [
            // Floor selector
            ..._floorLabels.asMap().entries.map((e) {
              final active = e.key == _floorIndex;
              return GestureDetector(
                onTap: () => setState(() {
                  _floorIndex = e.key;
                  _hovered = null;
                  _transformCtrl.value = Matrix4.identity();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent.withValues(alpha: 0.2)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: active
                            ? AppColors.accent
                            : Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Text(e.value,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? AppColors.accent : Colors.white38)),
                ),
              );
            }),
            const Spacer(),
            // Zoom controls
            _ZoomBtn(icon: Icons.add,    onTap: () => _zoom(1.3)),
            const SizedBox(width: 4),
            _ZoomBtn(icon: Icons.remove, onTap: () => _zoom(1 / 1.3)),
            const SizedBox(width: 4),
            _ZoomBtn(
                icon: Icons.center_focus_strong_outlined,
                onTap: () => _transformCtrl.value = Matrix4.identity()),
          ]),
          const SizedBox(height: 10),

          // ── Map canvas ──────────────────────────────────────────────────
          // AspectRatio matches the floor canvas exactly so overlays align.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InteractiveViewer(
              transformationController: _transformCtrl,
              minScale: 0.8,
              maxScale: 4.0,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    return LayoutBuilder(builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      // Scale factors: canvas coords → screen coords
                      final sx = w / canvasW;
                      final sy = h / canvasH;

                      return Stack(children: [
                        // ── Real hotel floor plan ──────────────────────
                        CustomPaint(
                          size: Size(w, h),
                          painter: hotelFloorPainter(
                            floorIndex: _floorIndex,
                            pulseValue: _pulse.value,
                          ),
                        ),

                        // ── Risk overlays ──────────────────────────────
                        // provider.riskAreas use floor: 2 for 2nd floor,
                        // matching _floorIndex == 2 directly.
                        ...widget.provider.riskAreas
                            .where((a) => a.floor == _floorIndex)
                            .map((area) {                          // area.normalizedX/Y are 0–1 fractions of the
                          // canvas (1000 × canvasH).  Convert to screen px.
                          final left   = area.normalizedX * canvasW * sx;
                          final top    = area.normalizedY * canvasH * sy;
                          final rw     = area.width  * canvasW * sx;
                          final rh     = area.height * canvasH * sy;
                          final isHov  = _hovered?.id == area.id;
                          return Positioned(
                            left: left, top: top,
                            width: rw, height: rh,
                            child: GestureDetector(
                              onTap: () => setState(() =>
                                  _hovered = isHov ? null : area),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                decoration: BoxDecoration(
                                  color: area.color.withValues(
                                      alpha: isHov ? 0.50 : 0.28),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                      color: area.color.withValues(
                                          alpha: isHov ? 0.9 : 0.55),
                                      width: isHov ? 2 : 1),
                                ),
                                child: area.icon != null && rw > 18 && rh > 18
                                    ? Center(child: Icon(area.icon,
                                        size: math.min(rw, rh) * 0.38,
                                        color: area.color))
                                    : null,
                              ),
                            ),
                          );
                        }),

                        // ── Tooltip ────────────────────────────────────
                        if (_hovered != null)
                          Positioned(
                            bottom: 6, left: 6, right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C0908)
                                    .withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: _hovered!.color
                                        .withValues(alpha: 0.5)),
                              ),
                              child: Row(children: [
                                if (_hovered!.icon != null)
                                  Icon(_hovered!.icon,
                                      size: 14, color: _hovered!.color),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_hovered!.name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600))),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _hovered!.color
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                        color: _hovered!.color
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Text(_hovered!.levelLabel,
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _hovered!.color)),
                                ),
                              ]),
                            ),
                          ),

                        // ── No-data banner for floors without risk data ─
                        if (widget.provider.riskAreas
                            .where((a) => a.floor == _floorIndex)
                            .isEmpty)
                          Positioned(
                            bottom: 6, left: 6, right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C0908)
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.1)),
                              ),
                              child: const Row(children: [
                                Icon(Icons.info_outline,
                                    size: 14, color: Colors.white38),
                                SizedBox(width: 8),
                                Text('No risk data for this floor.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white38)),
                              ]),
                            ),
                          ),
                      ]);
                    });
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Legend ───────────────────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _HeatLegend(color: const Color(0xFFEF4444), label: 'High Risk'),
            const SizedBox(width: 16),
            _HeatLegend(color: const Color(0xFFFFB74D), label: 'Medium Risk'),
            const SizedBox(width: 16),
            _HeatLegend(color: const Color(0xFF81C784), label: 'Low Risk'),
          ]),
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

class _ZoomBtn extends StatelessWidget {
  const _ZoomBtn({required this.icon, required this.onTap});
  final IconData icon; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: AppColors.background, borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Icon(icon, size: 14, color: Colors.white54),
    ),
  );
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.color, required this.label});
  final Color color; final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Risk Summary Card — donut + top risk areas list
// ─────────────────────────────────────────────────────────────────────────────

class RiskSummaryCard extends StatelessWidget {
  const RiskSummaryCard({super.key, required this.provider});
  final EvaluationProvider provider;

  @override
  Widget build(BuildContext context) {
    return _EvalCard(
      title: 'Risk Summary',
      icon: Icons.donut_large_rounded,
      child: Column(
        children: [
          // Donut chart
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _RiskDonutPainter(
                high:   provider.highRiskCount,
                medium: provider.mediumRiskCount,
                low:    provider.lowRiskCount,
              ),
              size: const Size(double.infinity, 140),
            ),
          ),
          const SizedBox(height: 10),
          // Legend
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _DonutLeg(color: const Color(0xFFEF4444), label: 'High',   value: provider.highRiskCount),
            _DonutLeg(color: const Color(0xFFFFB74D), label: 'Medium', value: provider.mediumRiskCount),
            _DonutLeg(color: const Color(0xFF81C784), label: 'Low',    value: provider.lowRiskCount),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2A1A14), height: 1),
          const SizedBox(height: 12),
          // Top risk areas
          const Align(alignment: Alignment.centerLeft,
              child: Text('Top Risk Areas',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70))),
          const SizedBox(height: 8),
          ...provider.topRiskAreas.map((area) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(area.name,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: area.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: area.color.withValues(alpha: 0.4)),
                ),
                child: Text(area.levelLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: area.color)),
              ),
            ]),
          )),
        ],
      ),
    );
  }
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

class _RiskDonutPainter extends CustomPainter {
  const _RiskDonutPainter({required this.high, required this.medium, required this.low});
  final int high, medium, low;

  @override
  void paint(Canvas canvas, Size size) {
    final total = (high + medium + low).toDouble();
    final cx = size.width / 2, cy = size.height / 2;
    final radius = math.min(cx, cy) - 10;
    const sw = 18.0, gap = 0.04;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    canvas.drawCircle(Offset(cx, cy), radius,
        Paint()..style = PaintingStyle.stroke..strokeWidth = sw
            ..color = Colors.white.withValues(alpha: 0.06));

    if (total <= 0) return;

    final segs = [
      (high.toDouble(),   const Color(0xFFEF4444)),
      (medium.toDouble(), const Color(0xFFFFB74D)),
      (low.toDouble(),    const Color(0xFF81C784)),
    ];

    double start = -math.pi / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round;
    for (final seg in segs) {
      if (seg.$1 <= 0) continue;
      final sweep = (seg.$1 / total) * 2 * math.pi - gap;
      canvas.drawArc(rect, start + gap / 2, sweep, false, paint..color = seg.$2);
      start += sweep + gap;
    }

    // Center label
    final tp = TextPainter(
      text: TextSpan(text: '${total.toInt()}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 6));
    final tp2 = TextPainter(
      text: TextSpan(text: 'Areas',
          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(cx - tp2.width / 2, cy + tp.height / 2 - 4));
  }

  @override
  bool shouldRepaint(_RiskDonutPainter old) =>
      old.high != high || old.medium != medium || old.low != low;
}

// ─────────────────────────────────────────────────────────────────────────────
// Evaluation List
// ─────────────────────────────────────────────────────────────────────────────

class EvaluationList extends StatelessWidget {
  const EvaluationList({super.key, required this.provider});
  final EvaluationProvider provider;

  @override
  Widget build(BuildContext context) {
    return _EvalCard(
      title: 'Active Evaluations',
      icon: Icons.assignment_outlined,
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: const [
              Expanded(flex: 2, child: _TH(label: 'Type')),
              Expanded(flex: 3, child: _TH(label: 'Location')),
              Expanded(flex: 2, child: _TH(label: 'Risk')),
              Expanded(flex: 2, child: _TH(label: 'Status')),
              Expanded(flex: 2, child: _TH(label: 'Time')),
            ]),
          ),
          const Divider(color: Color(0xFF2A1A14), height: 1),
          const SizedBox(height: 6),
          ...provider.evaluations.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(flex: 2, child: Row(children: [
                Icon(_typeIcon(e.type), size: 13, color: _riskColor(e.riskLevel)),
                const SizedBox(width: 4),
                Flexible(child: Text(e.type,
                    style: TextStyle(fontSize: 11, color: _riskColor(e.riskLevel),
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
              ])),
              Expanded(flex: 3, child: Text(e.location,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                  overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: _RiskBadge(level: e.riskLevel)),
              Expanded(flex: 2, child: _StatusBadge(status: e.status)),
              Expanded(flex: 2, child: Text(_timeAgo(e.time),
                  style: const TextStyle(fontSize: 10, color: Colors.white38))),
            ]),
          )),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'fire':        return Icons.local_fire_department_rounded;
      case 'smoke':       return Icons.cloud_outlined;
      case 'temperature': return Icons.thermostat_rounded;
      case 'water leak':  return Icons.water_damage_rounded;
      default:            return Icons.people_alt_rounded;
    }
  }
}

class _TH extends StatelessWidget {
  const _TH({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white38));
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.level});
  final RiskLevel level;
  @override
  Widget build(BuildContext context) {
    final color = _riskColor(level);
    final label = level == RiskLevel.high ? 'High' : level == RiskLevel.medium ? 'Medium' : 'Low';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Active'        => const Color(0xFFEF4444),
      'Investigating' => const Color(0xFF64B5F6),
      'Monitoring'    => const Color(0xFFFFB74D),
      _               => const Color(0xFF81C784),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          overflow: TextOverflow.ellipsis),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trend Chart Widget — line chart (last 24 hours)
// ─────────────────────────────────────────────────────────────────────────────

class TrendChartWidget extends StatelessWidget {
  const TrendChartWidget({super.key, required this.provider});
  final EvaluationProvider provider;

  @override
  Widget build(BuildContext context) {
    return _EvalCard(
      title: 'Evaluation Trends',
      subtitle: 'Last 24 hours',
      icon: Icons.show_chart_rounded,
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: provider.trends.isEmpty
                ? const Center(child: Text('No trend data.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)))
                : CustomPaint(
                    painter: _TrendPainter(trends: provider.trends),
                    size: const Size(double.infinity, 160),
                  ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            _TrendLeg(color: Color(0xFFEF4444), label: 'High Risk'),
            SizedBox(width: 16),
            _TrendLeg(color: Color(0xFFFFB74D), label: 'Medium'),
            SizedBox(width: 16),
            _TrendLeg(color: Color(0xFF81C784), label: 'Low'),
          ]),
        ],
      ),
    );
  }
}

class _TrendLeg extends StatelessWidget {
  const _TrendLeg({required this.color, required this.label});
  final Color color; final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 16, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
  ]);
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.trends});
  final List<TrendPoint> trends;

  @override
  void paint(Canvas canvas, Size size) {
    if (trends.isEmpty) return;

    const leftMargin = 24.0;
    final chartW = size.width - leftMargin;
    final chartH = size.height - 16;

    final maxVal = trends.fold<int>(1, (prev, t) =>
        math.max(prev, math.max(t.high, math.max(t.medium, t.low)))).toDouble();

    // Grid lines
    for (int i = 0; i <= 3; i++) {
      final y = chartH * (1 - i / 3);
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width, y),
          Paint()..color = Colors.white.withValues(alpha: 0.05)..strokeWidth = 1);
    }

    void drawSeries(List<int> values, Color color) {
      final n = values.length;
      final pts = List.generate(n, (i) {
        final x = leftMargin + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
        final y = maxVal == 0 ? chartH : chartH * (1 - values[i] / maxVal);
        return Offset(x, y);
      });

      // Area fill
      final area = Path()..moveTo(pts.first.dx, chartH);
      for (final p in pts) { area.lineTo(p.dx, p.dy); }
      area..lineTo(pts.last.dx, chartH)..close();
      canvas.drawPath(area, Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)])
            .createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill);

      // Line
      final line = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        final cp = (pts[i-1].dx + pts[i].dx) / 2;
        line.cubicTo(cp, pts[i-1].dy, cp, pts[i].dy, pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(line, Paint()
        ..color = color..style = PaintingStyle.stroke..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
    }

    drawSeries(trends.map((t) => t.high).toList(),   const Color(0xFFEF4444));
    drawSeries(trends.map((t) => t.medium).toList(), const Color(0xFFFFB74D));
    drawSeries(trends.map((t) => t.low).toList(),    const Color(0xFF81C784));

    // X-axis labels (every 6 hours)
    final n = trends.length;
    for (int i = 0; i < n; i += 6) {
      final x = leftMargin + (n == 1 ? chartW / 2 : i / (n - 1) * chartW);
      final tp = TextPainter(
        text: TextSpan(text: '${trends[i].hour.toString().padLeft(2,'0')}h',
            style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.3))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartH + 4));
    }

    // Y-axis labels
    for (int i = 0; i <= 3; i++) {
      final val = (maxVal * i / 3).round();
      final y = chartH * (1 - i / 3);
      final tp = TextPainter(
        text: TextSpan(text: '$val',
            style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.3))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 3, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.trends != trends;
}

// ─────────────────────────────────────────────────────────────────────────────
// Action List Card
// ─────────────────────────────────────────────────────────────────────────────

class ActionListCard extends StatelessWidget {
  const ActionListCard({super.key, required this.provider});
  final EvaluationProvider provider;

  @override
  Widget build(BuildContext context) {
    return _EvalCard(
      title: 'Recommended Actions',
      icon: Icons.bolt_rounded,
      child: Column(
        children: provider.actions.map((action) {
          final color = _riskColor(action.riskLevel);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(action.icon, size: 14, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                    Text(action.location,
                        style: const TextStyle(fontSize: 10, color: Colors.white38)),
                  ],
                )),
                _RiskBadge(level: action.riskLevel),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _EvalCard extends StatelessWidget {
  const _EvalCard({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.accent, size: 15),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Text(subtitle!, style: const TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _riskColor(RiskLevel level) {
  switch (level) {
    case RiskLevel.high:   return const Color(0xFFEF4444);
    case RiskLevel.medium: return const Color(0xFFFFB74D);
    case RiskLevel.low:    return const Color(0xFF81C784);
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1)  return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}
