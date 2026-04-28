import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/map_page.dart';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

enum EmergencyCategory { fire, medical, trapped, other }

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.guestName = 'Guest',
    this.roomNumber = '302',
    this.floorLabel = 'Floor 3',
  });

  final String guestName;
  final String roomNumber;
  final String floorLabel;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isEmergencyActive = false;
  Offset? _pressStartPosition;
  EmergencyCategory? _activeEmergencyCategory;
  bool _isReporting = false;

  static const Map<EmergencyCategory, String> _categoryLabels = {
    EmergencyCategory.fire: 'FIRE',
    EmergencyCategory.medical: 'MEDICAL',
    EmergencyCategory.trapped: 'TRAPPED',
    EmergencyCategory.other: 'OTHER',
  };

  void _onEmergencyLongPressStart(LongPressStartDetails details) {
    setState(() {
      _isEmergencyActive = true;
      _pressStartPosition = details.globalPosition;
      _activeEmergencyCategory = null;
    });
    HapticFeedback.mediumImpact();
  }

  void _onEmergencyLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isEmergencyActive || _pressStartPosition == null) return;

    final drag = details.globalPosition - _pressStartPosition!;
    const threshold = 26.0;
    EmergencyCategory? nextCategory;

    if (drag.distance >= threshold) {
      if (drag.dx.abs() > drag.dy.abs()) {
        nextCategory = drag.dx > 0
            ? EmergencyCategory.medical
            : EmergencyCategory.trapped;
      } else {
        nextCategory =
            drag.dy < 0 ? EmergencyCategory.fire : EmergencyCategory.other;
      }
    }

    if (nextCategory != _activeEmergencyCategory) {
      setState(() => _activeEmergencyCategory = nextCategory);
    }
  }

  void _onEmergencyLongPressEnd(LongPressEndDetails _) {
    final selectedCategory = _activeEmergencyCategory;
    _resetEmergencySelectionState();
    if (selectedCategory != null) {
      _reportEmergencyAndNavigate(selectedCategory);
    }
  }

  void _onEmergencyLongPressCancel() {
    if (_isEmergencyActive || _activeEmergencyCategory != null) {
      _resetEmergencySelectionState();
    }
  }

  void _resetEmergencySelectionState() {
    setState(() {
      _isEmergencyActive = false;
      _pressStartPosition = null;
      _activeEmergencyCategory = null;
    });
  }

  Future<void> _reportEmergencyAndNavigate(EmergencyCategory category) async {
    if (_isReporting) return;
    setState(() => _isReporting = true);
    HapticFeedback.heavyImpact();

    String? incidentId;

    try {
      final response = await Supabase.instance.client
          .from('incidents')
          .insert({
            'incident_type': _categoryLabels[category],
            'location': 'Room ${widget.roomNumber} - ${widget.floorLabel}',
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      incidentId = response['id']?.toString();
    } catch (_) {
      // Navigate anyway — guest needs the map even if Supabase is unreachable
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPage(
          emergencyCategory: category,
          roomNumber: widget.roomNumber,
          floorLabel: widget.floorLabel,
          incidentId: incidentId,
        ),
      ),
    );
  }

  void _openMapPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapPage(
          roomNumber: widget.roomNumber,
          floorLabel: widget.floorLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboardTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepOrange,
        brightness: Brightness.dark,
      ),
    );

    return Theme(
      data: dashboardTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AegisStay'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: _ConnectivityStatus(),
            ),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _UserProfileCard(
                        guestName: widget.guestName,
                        roomNumber: widget.roomNumber,
                        floorLabel: widget.floorLabel,
                      ),
                      const SizedBox(height: 32),
                      _FloorMapCard(onViewFullMap: _openMapPage),
                      const SizedBox(height: 32),
                      const _QuickLinksSection(),
                      const SizedBox(height: 132),
                    ],
                  ),
                ),
              ),
            ),
            if (_isEmergencyActive)
              _EmergencyOverlay(activeCategory: _activeEmergencyCategory),

            if (_isReporting)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: Colors.deepOrange),
                        const SizedBox(height: 20),
                        Text(
                          'Sending alert...',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _EmergencyHoldButton(
          onLongPressStart: _onEmergencyLongPressStart,
          onLongPressMoveUpdate: _onEmergencyLongPressMoveUpdate,
          onLongPressEnd: _onEmergencyLongPressEnd,
          onLongPressCancel: _onEmergencyLongPressCancel,
        ),
      ),
    );
  }
}

// ── Connectivity status widget ─────────────────────────────────────────────
class _ConnectivityStatus extends StatefulWidget {
  const _ConnectivityStatus();

  @override
  State<_ConnectivityStatus> createState() => _ConnectivityStatusState();
}

class _ConnectivityStatusState extends State<_ConnectivityStatus>
    with SingleTickerProviderStateMixin {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool? _hasNetworkConnection;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectivityStatus);
  }

  Future<void> _initConnectivity() async {
    final currentResults = await _connectivity.checkConnectivity();
    if (!mounted) return;
    _updateConnectivityStatus(currentResults);
  }

  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final hasConnection =
        results.any((result) => result != ConnectivityResult.none);
    if (_hasNetworkConnection != hasConnection && mounted) {
      setState(() => _hasNetworkConnection = hasConnection);
    } else {
      _hasNetworkConnection = hasConnection;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _hasNetworkConnection ?? false;
    final Color statusColor = switch (_hasNetworkConnection) {
      true => Colors.green,
      false => Colors.redAccent,
      null => Colors.amber,
    };
    final String statusLabel = switch (_hasNetworkConnection) {
      true => 'Connected',
      false => 'Offline',
      null => 'Checking...',
    };

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = isConnected ? 0.4 + (_controller.value * 0.6) : 0.9;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: pulse),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.35 * pulse),
                    blurRadius: 8,
                    spreadRadius: 1.2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(statusLabel),
          ],
        );
      },
    );
  }
}

// ── Floor map card — now shows real EvacuationMapPainter as thumbnail ──────
class _FloorMapCard extends StatelessWidget {
  const _FloorMapCard({required this.onViewFullMap});

  final VoidCallback onViewFullMap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHigh,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      clipBehavior: Clip.antiAlias, // ensures the map stays inside rounded corners
      child: InkWell(
        onTap: onViewFullMap,
        child: SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 1: actual EvacuationMapPainter rendered as thumbnail ──
              // Uses the exact same painter from map_page.dart —
              // no duplication, no placeholder icon anymore.
              CustomPaint(
                painter: EvacuationMapPainter(),
              ),

              // ── Layer 2: dark gradient over the map ─────────────────────────
              // Fades the bottom half to black so the text and button
              // are readable on top of the map drawing.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),

              // ── Layer 3: title top-left, button bottom-center ────────────────
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Floor Map" label with a pill background so it's legible
                    // even on the bright parts of the map drawing
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Floor Map',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Bottom row: description + button
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Know your exit before you need it',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: onViewFullMap,
                          icon: const Icon(Icons.open_in_full, size: 14),
                          label: const Text('View Evacuation Map'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── User profile card ──────────────────────────────────────────────────────
class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard({
    required this.guestName,
    required this.roomNumber,
    required this.floorLabel,
  });

  final String guestName;
  final String roomNumber;
  final String floorLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $guestName',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Room $roomNumber, $floorLabel',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick links section ────────────────────────────────────────────────────
class _QuickLinksSection extends StatelessWidget {
  const _QuickLinksSection();

  @override
  Widget build(BuildContext context) {
    const links = <_QuickLinkItem>[
      _QuickLinkItem(icon: Icons.info_outline, label: 'Hotel Info'),
      _QuickLinkItem(icon: Icons.call_outlined, label: 'Call Reception'),
      _QuickLinkItem(icon: Icons.wifi, label: 'WiFi'),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: links
          .map((item) => _QuickLinkCard(item: item))
          .toList(growable: false),
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({required this.item});

  final _QuickLinkItem item;

  Future<void> _handleTap(BuildContext context) async {
    if (item.label == 'Call Reception') {
      final Uri phoneUri = Uri(scheme: 'tel', path: '+1234567890');
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open dialer')),
          );
        }
      }
    } else if (item.label == 'WiFi') {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => Container(
          padding: const EdgeInsets.all(20),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WiFi Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text('Network: AegisStay_Guest'),
              Text('Password: 12345678'),
            ],
          ),
        ),
      );
    } else if (item.label == 'Hotel Info') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Hotel Info')),
            body: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Check-out: 11:00 AM'),
                  SizedBox(height: 10),
                  Text('Emergency Exits: Near stairs on each floor'),
                  SizedBox(height: 10),
                  Text('Floors: 5'),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _handleTap(context),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Emergency hold button ──────────────────────────────────────────────────
class _EmergencyHoldButton extends StatelessWidget {
  const _EmergencyHoldButton({
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;
  final GestureLongPressEndCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd,
      onLongPressCancel: onLongPressCancel,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.sos,
          size: 36,
          color: colorScheme.onPrimary,
        ),
      ),
    );
  }
}

// ── Emergency overlay ──────────────────────────────────────────────────────
class _EmergencyOverlay extends StatelessWidget {
  const _EmergencyOverlay({required this.activeCategory});

  final EmergencyCategory? activeCategory;

  static const List<_EmergencyActionData> _actions = [
    _EmergencyActionData(
      category: EmergencyCategory.fire,
      label: 'FIRE',
      icon: Icons.local_fire_department,
      alignment: Alignment(0, -1),
    ),
    _EmergencyActionData(
      category: EmergencyCategory.medical,
      label: 'MEDICAL',
      icon: Icons.medical_services,
      alignment: Alignment(1, 0),
    ),
    _EmergencyActionData(
      category: EmergencyCategory.trapped,
      label: 'TRAPPED',
      icon: Icons.door_front_door,
      alignment: Alignment(-1, 0),
    ),
    _EmergencyActionData(
      category: EmergencyCategory.other,
      label: 'OTHER',
      icon: Icons.more_horiz,
      alignment: Alignment(0, 1),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(color: Colors.black54),
              ),
            ),
            const Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Text(
                'RELEASE TO REPORT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.78),
              child: SizedBox(
                width: 320,
                height: 320,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final action in _actions)
                      _EmergencyRadialAction(
                        data: action,
                        isActive: activeCategory == action.category,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyRadialAction extends StatelessWidget {
  const _EmergencyRadialAction({required this.data, required this.isActive});

  final _EmergencyActionData data;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const travelDistance = 134.0;
    final verticalOffset =
        data.category == EmergencyCategory.other ? -14.0 : 0.0;
    final dx = data.alignment.x * travelDistance;
    final dy = (data.alignment.y * travelDistance) + verticalOffset;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.2, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(dx * value, dy * value),
            child: child,
          ),
        );
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: isActive ? 1.3 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.category == EmergencyCategory.other) ...[
              Text(
                data.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
            ],
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.95),
                border: Border.all(
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                data.icon,
                size: 32,
                color: isActive ? colorScheme.onPrimary : Colors.white,
              ),
            ),
            if (data.category != EmergencyCategory.other) ...[
              const SizedBox(height: 6),
              Text(
                data.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmergencyActionData {
  const _EmergencyActionData({
    required this.category,
    required this.label,
    required this.icon,
    required this.alignment,
  });

  final EmergencyCategory category;
  final String label;
  final IconData icon;
  final Alignment alignment;
}

class _QuickLinkItem {
  const _QuickLinkItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}