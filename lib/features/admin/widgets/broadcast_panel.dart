import 'dart:async';

import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colors
// ─────────────────────────────────────────────────────────────────────────────
const _kEmergency = Color(0xFFEF4444);
const _kWarning   = Color(0xFFFFB74D);
const _kInfo      = Color(0xFF64B5F6);
const _kSuccess   = Color(0xFF81C784);
const _kOverride  = Color(0xFFEF4444);

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum _MsgType { emergency, warning, info }
enum _DeliveryStatus { sent, delivered, failed }

class _BroadcastRecord {
  const _BroadcastRecord({
    required this.id,
    required this.message,
    required this.type,
    required this.audience,
    required this.channels,
    required this.status,
    required this.sentAt,
    this.deliveredCount = 0,
    this.failedCount = 0,
  });
  final String id;
  final String message;
  final _MsgType type;
  final String audience;
  final List<String> channels;
  final _DeliveryStatus status;
  final DateTime sentAt;
  final int deliveredCount;
  final int failedCount;
}

class _ScheduledBroadcast {
  const _ScheduledBroadcast({
    required this.message,
    required this.type,
    required this.scheduledAt,
    required this.audience,
    required this.channels,
  });
  final String message;
  final _MsgType type;
  final DateTime scheduledAt;
  final String audience;
  final List<String> channels;
}

class _DeliveryRow {
  const _DeliveryRow({
    required this.name,
    required this.role,
    required this.channel,
    required this.status,
    this.lastSeen,
  });
  final String name;
  final String role;
  final String channel;
  final bool status; // true = seen
  final String? lastSeen;
}

// ─────────────────────────────────────────────────────────────────────────────
// Supabase service
// ─────────────────────────────────────────────────────────────────────────────

class _BroadcastService {
  static SupabaseClient? get _db {
    try { return Supabase.instance.client; } catch (_) { return null; }
  }

  static Future<List<_BroadcastRecord>> fetchHistory() async {
    try {
      final db = _db;
      if (db == null) return _mockHistory();
      final rows = await db
          .from('broadcasts')
          .select('id,message,channel,sent_at,status')
          .order('sent_at', ascending: false)
          .limit(20);
      return rows.map<_BroadcastRecord>((r) => _BroadcastRecord(
        id:       r['id'].toString(),
        message:  (r['message'] ?? '').toString(),
        type:     _MsgType.emergency,
        audience: (r['channel'] ?? 'All Staff').toString(),
        channels: ['In-App'],
        status:   _DeliveryStatus.delivered,
        sentAt:   DateTime.tryParse(r['sent_at']?.toString() ?? '') ?? DateTime.now(),
        deliveredCount: 1,
      )).toList();
    } catch (_) {
      return _mockHistory();
    }
  }

  static Future<void> sendBroadcast({
    required String message,
    required String audience,
    required List<String> channels,
    required _MsgType type,
  }) async {
    try {
      final db = _db;
      if (db == null) return;
      await db.from('broadcasts').insert({
        'message':  message,
        'channel':  audience,
        'sent_at':  DateTime.now().toIso8601String(),
        'status':   'sent',
      });
    } catch (_) {}
  }

  static Stream<void> get changes {
    final ctrl = StreamController<void>.broadcast();
    final suffix = DateTime.now().millisecondsSinceEpoch;
    RealtimeChannel? ch;
    try {
      ch = _db!.channel('bc_broadcasts_$suffix')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'broadcasts',
            callback: (_) { if (!ctrl.isClosed) ctrl.add(null); },
          ).subscribe();
    } catch (_) {}
    ctrl.onCancel = () {
      try { if (ch != null) _db?.removeChannel(ch); } catch (_) {}
      ctrl.close();
    };
    return ctrl.stream;
  }

  static List<_BroadcastRecord> _mockHistory() {
    final now = DateTime.now();
    return [
      _BroadcastRecord(id: 'b1', message: 'Fire detected on 2nd floor. Evacuate immediately.', type: _MsgType.emergency, audience: 'All Occupants', channels: ['Push', 'SMS', 'In-App'], status: _DeliveryStatus.delivered, sentAt: now.subtract(const Duration(minutes: 2)), deliveredCount: 112, failedCount: 9),
      _BroadcastRecord(id: 'b2', message: 'Smoke reported in Library 205. Avoid the area.', type: _MsgType.warning, audience: '2nd Floor', channels: ['Push', 'SMS', 'In-App'], status: _DeliveryStatus.delivered, sentAt: now.subtract(const Duration(minutes: 8)), deliveredCount: 48, failedCount: 2),
      _BroadcastRecord(id: 'b3', message: 'Scheduled maintenance tonight 11 PM.', type: _MsgType.info, audience: 'Staff Only', channels: ['In-App'], status: _DeliveryStatus.sent, sentAt: now.subtract(const Duration(minutes: 25)), deliveredCount: 22, failedCount: 0),
      _BroadcastRecord(id: 'b4', message: 'Evacuate immediately. Emergency in Computer Lab 204.', type: _MsgType.emergency, audience: 'All Occupants', channels: ['Push', 'SMS', 'PA', 'In-App'], status: _DeliveryStatus.delivered, sentAt: now.subtract(const Duration(minutes: 35)), deliveredCount: 98, failedCount: 4),
      _BroadcastRecord(id: 'b5', message: 'Water leak detected in Lab 203.', type: _MsgType.warning, audience: 'Lab 203', channels: ['Push', 'In-App'], status: _DeliveryStatus.failed, sentAt: now.subtract(const Duration(hours: 1)), deliveredCount: 0, failedCount: 5),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Root widget
// ─────────────────────────────────────────────────────────────────────────────

class BroadcastPanel extends StatefulWidget {
  const BroadcastPanel({super.key});

  @override
  State<BroadcastPanel> createState() => _BroadcastPanelState();
}

class _BroadcastPanelState extends State<BroadcastPanel> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<_BroadcastRecord> _history = [];
  StreamSubscription<void>? _sub;
  Timer? _debounce;

  // ── Compose form state ────────────────────────────────────────────────────
  _MsgType _msgType = _MsgType.emergency;
  String _audience = 'All Occupants';
  final Set<String> _channels = {'Push', 'SMS', 'PA System', 'In-App'};
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  // ── Emergency override ────────────────────────────────────────────────────
  bool _overrideEnabled = false;

  // ── Scheduled broadcasts (mock) ───────────────────────────────────────────
  final List<_ScheduledBroadcast> _scheduled = [
    _ScheduledBroadcast(message: 'Fire drill scheduled', type: _MsgType.info, scheduledAt: DateTime(2025, 5, 20, 10, 0), audience: 'All Occupants', channels: ['Push', 'PA']),
    _ScheduledBroadcast(message: 'Weather alert', type: _MsgType.warning, scheduledAt: DateTime(2025, 5, 21, 8, 0), audience: 'All Occupants', channels: ['Push', 'SMS']),
    _ScheduledBroadcast(message: 'Monthly safety briefing', type: _MsgType.info, scheduledAt: DateTime(2025, 5, 22, 14, 0), audience: 'Staff Only', channels: ['In-App', 'PA']),
  ];

  // ── Templates ─────────────────────────────────────────────────────────────
  final List<String> _templates = [
    'Evacuate immediately.',
    'Fire detected on Floor [floor].',
    'Use nearest exit.',
    'Remain calm.',
  ];

  // ── Analytics (derived from history) ─────────────────────────────────────
  int get _totalSent => _history.length;
  int get _delivered => _history.where((b) => b.status == _DeliveryStatus.delivered).length;
  int get _failed    => _history.where((b) => b.status == _DeliveryStatus.failed).length;
  int get _active    => _history.where((b) => b.status == _DeliveryStatus.sent).length;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = _BroadcastService.changes.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _load);
    });
  }

  Future<void> _load() async {
    final data = await _BroadcastService.fetchHistory();
    if (mounted) setState(() { _history = data; });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    await _BroadcastService.sendBroadcast(
      message:  _msgCtrl.text.trim(),
      audience: _audience,
      channels: _channels.toList(),
      type:     _msgType,
    );
    // Optimistic insert
    final newRecord = _BroadcastRecord(
      id:             DateTime.now().millisecondsSinceEpoch.toString(),
      message:        _msgCtrl.text.trim(),
      type:           _msgType,
      audience:       _audience,
      channels:       _channels.toList(),
      status:         _DeliveryStatus.sent,
      sentAt:         DateTime.now(),
      deliveredCount: 0,
    );
    setState(() {
      _history = [newRecord, ..._history];
      _msgCtrl.clear();
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(),
        const SizedBox(height: 20),
        // Top section: compose + analytics
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: _ComposeCard(
                msgType: _msgType, onMsgType: (t) => setState(() => _msgType = t),
                audience: _audience, onAudience: (a) => setState(() => _audience = a),
                channels: _channels, onChannelToggle: (c) => setState(() => _channels.contains(c) ? _channels.remove(c) : _channels.add(c)),
                msgCtrl: _msgCtrl,
                templates: _templates, onTemplate: (t) => setState(() => _msgCtrl.text = t),
                sending: _sending, onSend: _send,
              )),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: _AnalyticsCard(
                totalSent: _totalSent, delivered: _delivered,
                failed: _failed, active: _active,
              )),
            ]);
          }
          return Column(children: [
            _ComposeCard(
              msgType: _msgType, onMsgType: (t) => setState(() => _msgType = t),
              audience: _audience, onAudience: (a) => setState(() => _audience = a),
              channels: _channels, onChannelToggle: (c) => setState(() => _channels.contains(c) ? _channels.remove(c) : _channels.add(c)),
              msgCtrl: _msgCtrl,
              templates: _templates, onTemplate: (t) => setState(() => _msgCtrl.text = t),
              sending: _sending, onSend: _send,
            ),
            const SizedBox(height: 14),
            _AnalyticsCard(totalSent: _totalSent, delivered: _delivered, failed: _failed, active: _active),
          ]);
        }),
        const SizedBox(height: 20),
        // Middle section: live feed + delivery tracking + scheduled
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: _LiveFeedCard(history: _history)),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: _DeliveryTrackingCard(history: _history)),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: _ScheduledCard(scheduled: _scheduled)),
            ]);
          }
          return Column(children: [
            _LiveFeedCard(history: _history),
            const SizedBox(height: 14),
            _DeliveryTrackingCard(history: _history),
            const SizedBox(height: 14),
            _ScheduledCard(scheduled: _scheduled),
          ]);
        }),
        const SizedBox(height: 20),
        // Bottom section: priority override + templates
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _PriorityOverrideCard(
                enabled: _overrideEnabled,
                onToggle: (v) => setState(() => _overrideEnabled = v),
              )),
              const SizedBox(width: 14),
              Expanded(child: _TemplatesCard(
                templates: _templates,
                onUse: (t) => setState(() => _msgCtrl.text = t),
                onAdd: () => _showAddTemplateDialog(),
              )),
            ]);
          }
          return Column(children: [
            _PriorityOverrideCard(enabled: _overrideEnabled, onToggle: (v) => setState(() => _overrideEnabled = v)),
            const SizedBox(height: 14),
            _TemplatesCard(templates: _templates, onUse: (t) => setState(() => _msgCtrl.text = t), onAdd: () => _showAddTemplateDialog()),
          ]);
        }),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildHeader() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Broadcast Control Center',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        const Text('Send alerts and emergency instructions in real-time',
            style: TextStyle(fontSize: 12, color: Colors.white38)),
      ])),
      // Emergency override chip
      GestureDetector(
        onTap: () => setState(() => _overrideEnabled = !_overrideEnabled),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _overrideEnabled
                ? _kOverride.withValues(alpha: 0.2)
                : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: _overrideEnabled
                    ? _kOverride
                    : Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_rounded,
                size: 14,
                color: _overrideEnabled ? _kOverride : Colors.white38),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('EMERGENCY OVERRIDE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _overrideEnabled ? _kOverride : Colors.white54,
                      letterSpacing: 0.5)),
              Text('Priority Override: ${_overrideEnabled ? "ON" : "OFF"}',
                  style: TextStyle(
                      fontSize: 10,
                      color: _overrideEnabled
                          ? _kOverride.withValues(alpha: 0.8)
                          : Colors.white38)),
            ]),
          ]),
        ),
      ),
    ]);
  }

  void _showAddTemplateDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Add Template', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Enter template message…',
          hintStyle: TextStyle(color: Colors.white38),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.button, foregroundColor: AppColors.accent),
          onPressed: () {
            if (ctrl.text.trim().isNotEmpty) {
              setState(() => _templates.add(ctrl.text.trim()));
            }
            Navigator.pop(ctx);
          },
          child: const Text('Add'),
        ),
      ],
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compose Card
// ─────────────────────────────────────────────────────────────────────────────

class _ComposeCard extends StatelessWidget {
  const _ComposeCard({
    required this.msgType, required this.onMsgType,
    required this.audience, required this.onAudience,
    required this.channels, required this.onChannelToggle,
    required this.msgCtrl,
    required this.templates, required this.onTemplate,
    required this.sending, required this.onSend,
  });

  final _MsgType msgType;
  final ValueChanged<_MsgType> onMsgType;
  final String audience;
  final ValueChanged<String> onAudience;
  final Set<String> channels;
  final ValueChanged<String> onChannelToggle;
  final TextEditingController msgCtrl;
  final List<String> templates;
  final ValueChanged<String> onTemplate;
  final bool sending;
  final VoidCallback onSend;

  static const _audiences = ['All Occupants', 'Staff Only', 'Floor Wardens', 'Security', '2nd Floor', '1st Floor', 'Ground Floor'];
  static const _allChannels = ['Push', 'SMS', 'PA System', 'In-App'];

  @override
  Widget build(BuildContext context) {
    return _BCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Send Broadcast',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 16),

        // Row 1: Message type + Audience + Channels
        Wrap(spacing: 12, runSpacing: 12, children: [
          // 1. Message type
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('1. Message Type',
                style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _TypeBtn(label: 'Emergency', icon: Icons.warning_rounded, color: _kEmergency,
                  active: msgType == _MsgType.emergency, onTap: () => onMsgType(_MsgType.emergency)),
              const SizedBox(width: 6),
              _TypeBtn(label: 'Warning', icon: Icons.warning_amber_rounded, color: _kWarning,
                  active: msgType == _MsgType.warning, onTap: () => onMsgType(_MsgType.warning)),
              const SizedBox(width: 6),
              _TypeBtn(label: 'Info', icon: Icons.info_outline_rounded, color: _kInfo,
                  active: msgType == _MsgType.info, onTap: () => onMsgType(_MsgType.info)),
            ]),
          ]),

          // 2. Audience
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('2. Audience',
                style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            PopupMenuButton<String>(
              color: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: onAudience,
              itemBuilder: (_) => _audiences.map((a) => PopupMenuItem(
                value: a,
                child: Text(a, style: TextStyle(
                    color: a == audience ? AppColors.accent : Colors.white70,
                    fontWeight: a == audience ? FontWeight.w700 : FontWeight.normal)),
              )).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_alt_outlined, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(audience, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white38),
                ]),
              ),
            ),
          ]),

          // 3. Channels
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('3. Channels (Select one or more)',
                style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: _allChannels.map((ch) {
              final active = channels.contains(ch);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onChannelToggle(ch),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _kSuccess.withValues(alpha: 0.15) : AppColors.background,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: active ? _kSuccess : Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_channelIcon(ch), size: 12,
                          color: active ? _kSuccess : Colors.white38),
                      const SizedBox(width: 5),
                      Text(ch, style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? _kSuccess : Colors.white38)),
                      if (active) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_circle_rounded, size: 11, color: _kSuccess),
                      ],
                    ]),
                  ),
                ),
              );
            }).toList()),
          ]),
        ]),

        const SizedBox(height: 16),

        // Row 2: Message + Attachments + Actions
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 4. Message
              Expanded(flex: 3, child: _MessageField(ctrl: msgCtrl)),
              const SizedBox(width: 12),
              // 5. Attachments
              Expanded(flex: 2, child: _AttachmentsSection(templates: templates, onTemplate: onTemplate)),
              const SizedBox(width: 12),
              // 6. Actions
              SizedBox(width: 160, child: _ActionsSection(sending: sending, onSend: onSend)),
            ]);
          }
          return Column(children: [
            _MessageField(ctrl: msgCtrl),
            const SizedBox(height: 10),
            _AttachmentsSection(templates: templates, onTemplate: onTemplate),
            const SizedBox(height: 10),
            _ActionsSection(sending: sending, onSend: onSend),
          ]);
        }),
      ]),
    );
  }

  IconData _channelIcon(String ch) {
    switch (ch) {
      case 'Push':      return Icons.notifications_outlined;
      case 'SMS':       return Icons.sms_outlined;
      case 'PA System': return Icons.volume_up_outlined;
      default:          return Icons.app_registration_rounded;
    }
  }
}

class _TypeBtn extends StatelessWidget {
  const _TypeBtn({required this.label, required this.icon, required this.color,
      required this.active, required this.onTap});
  final String label; final IconData icon; final Color color;
  final bool active; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.2) : AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? color : Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: active ? color : Colors.white38),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? color : Colors.white38)),
      ]),
    ),
  );
}

class _MessageField extends StatelessWidget {
  const _MessageField({required this.ctrl});
  final TextEditingController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('4. Message',
          style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl,
        maxLines: 5,
        maxLength: 500,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Type your broadcast message here…',
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          filled: true, fillColor: AppColors.background,
          counterStyle: const TextStyle(color: Colors.white24, fontSize: 10),
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.accent)),
        ),
      ),
    ]);
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({required this.templates, required this.onTemplate});
  final List<String> templates;
  final ValueChanged<String> onTemplate;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('5. Attachments (Optional)',
          style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(children: [
        _AttachBtn(icon: Icons.map_outlined,   label: 'Map Route'),
        const SizedBox(width: 8),
        _AttachBtn(icon: Icons.image_outlined, label: 'Image'),
        const SizedBox(width: 8),
        _AttachBtn(icon: Icons.description_outlined, label: 'Template'),
      ]),
    ]);
  }
}

class _AttachBtn extends StatelessWidget {
  const _AttachBtn({required this.icon, required this.label});
  final IconData icon; final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 20, color: Colors.white38),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
    ]),
  );
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({required this.sending, required this.onSend});
  final bool sending; final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('6. Actions',
          style: TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      // Send Now
      GestureDetector(
        onTap: sending ? null : onSend,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sending ? _kEmergency.withValues(alpha: 0.3) : _kEmergency,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (sending)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else
              const Icon(Icons.send_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 8),
            Text(sending ? 'Sending…' : 'Send Now',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      // Schedule
      _ActionOutlineBtn(icon: Icons.schedule_rounded, label: 'Schedule',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Scheduling coming soon.')))),
      const SizedBox(height: 8),
      // Save Template
      _ActionOutlineBtn(icon: Icons.bookmark_outline_rounded, label: 'Save Template',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Template saved.')))),
    ]);
  }
}

class _ActionOutlineBtn extends StatelessWidget {
  const _ActionOutlineBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Analytics Card
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.totalSent, required this.delivered,
      required this.failed, required this.active});
  final int totalSent, delivered, failed, active;

  @override
  Widget build(BuildContext context) {
    final deliveryRate = totalSent > 0 ? (delivered / totalSent * 100).round() : 0;
    final failRate     = totalSent > 0 ? (failed    / totalSent * 100).round() : 0;

    return _BCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Broadcast Analytics',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(width: 8),
        const Text('(Today)', style: TextStyle(fontSize: 11, color: Colors.white38)),
      ]),
      const SizedBox(height: 16),
      // Stat row
      Row(children: [
        Expanded(child: _AnalyticStat(label: 'Total Sent', value: '$totalSent',
            icon: Icons.send_rounded, color: AppColors.accent)),
        Expanded(child: _AnalyticStat(label: 'Delivered', value: '$delivered\n$deliveryRate%',
            icon: Icons.check_circle_outline_rounded, color: _kSuccess)),
        Expanded(child: _AnalyticStat(label: 'Failed', value: '$failed\n$failRate%',
            icon: Icons.cancel_outlined, color: _kEmergency)),
        Expanded(child: _AnalyticStat(label: 'Active', value: '$active',
            icon: Icons.broadcast_on_personal_rounded, color: _kInfo)),
      ]),
      const SizedBox(height: 16),
      const Text('Delivery Status by Channel',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
      const SizedBox(height: 10),
      _ChannelBar(label: 'Push Notification', value: 0.90, color: _kSuccess),
      const SizedBox(height: 6),
      _ChannelBar(label: 'SMS',               value: 0.75, color: _kWarning),
      const SizedBox(height: 6),
      _ChannelBar(label: 'PA System',         value: 1.0,  color: _kInfo, isActive: true),
      const SizedBox(height: 6),
      _ChannelBar(label: 'In-App Alert',      value: 1.0,  color: _kSuccess),
    ]));
  }
}

class _AnalyticStat extends StatelessWidget {
  const _AnalyticStat({required this.label, required this.value,
      required this.icon, required this.color});
  final String label, value; final IconData icon; final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: color)),
    const SizedBox(height: 6),
    Text(value, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color, height: 1.2)),
    const SizedBox(height: 3),
    Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, color: Colors.white38)),
  ]);
}

class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.label, required this.value,
      required this.color, this.isActive = false});
  final String label; final double value; final Color color; final bool isActive;

  @override
  Widget build(BuildContext context) => Row(children: [
    SizedBox(width: 120,
        child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54),
            overflow: TextOverflow.ellipsis)),
    Expanded(child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 7,
      ),
    )),
    const SizedBox(width: 8),
    isActive
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: _kInfo.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4)),
            child: const Text('Active', style: TextStyle(fontSize: 10, color: _kInfo, fontWeight: FontWeight.w700)))
        : Text('${(value * 100).round()}%',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Feed Card
// ─────────────────────────────────────────────────────────────────────────────

class _LiveFeedCard extends StatelessWidget {
  const _LiveFeedCard({required this.history});
  final List<_BroadcastRecord> history;

  @override
  Widget build(BuildContext context) {
    return _BCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Live Broadcast Feed',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
        const Spacer(),
        Container(width: 7, height: 7,
            decoration: const BoxDecoration(color: _kSuccess, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        const Text('Live', style: TextStyle(fontSize: 11, color: _kSuccess, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 12),
      if (history.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No broadcasts yet.', style: TextStyle(color: Colors.white38))))
      else
        ...history.take(5).map((b) => _FeedItem(record: b)),
      const SizedBox(height: 8),
      // Legend
      Wrap(spacing: 12, children: [
        _FeedLegend(color: _kEmergency, label: 'Emergency'),
        _FeedLegend(color: _kWarning,   label: 'Warning'),
        _FeedLegend(color: _kInfo,      label: 'Info'),
        _FeedLegend(color: _kSuccess,   label: 'Delivered', isLine: true),
        _FeedLegend(color: Colors.white38, label: 'Sent', isLine: true),
        _FeedLegend(color: _kEmergency, label: 'Failed', isLine: true),
      ]),
    ]));
  }
}

class _FeedItem extends StatelessWidget {
  const _FeedItem({required this.record});
  final _BroadcastRecord record;

  Color get _typeColor {
    switch (record.type) {
      case _MsgType.emergency: return _kEmergency;
      case _MsgType.warning:   return _kWarning;
      case _MsgType.info:      return _kInfo;
    }
  }

  IconData get _typeIcon {
    switch (record.type) {
      case _MsgType.emergency: return Icons.warning_rounded;
      case _MsgType.warning:   return Icons.warning_amber_rounded;
      case _MsgType.info:      return Icons.info_outline_rounded;
    }
  }

  Color get _statusColor {
    switch (record.status) {
      case _DeliveryStatus.delivered: return _kSuccess;
      case _DeliveryStatus.failed:    return _kEmergency;
      case _DeliveryStatus.sent:      return Colors.white38;
    }
  }

  String get _statusLabel {
    switch (record.status) {
      case _DeliveryStatus.delivered: return 'Delivered';
      case _DeliveryStatus.failed:    return 'Failed';
      case _DeliveryStatus.sent:      return 'Sent';
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 28, height: 28,
            decoration: BoxDecoration(color: _typeColor.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(_typeIcon, size: 13, color: _typeColor)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(record.message,
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            Text(record.audience, style: const TextStyle(fontSize: 10, color: Colors.white38)),
            const Text(' · ', style: TextStyle(color: Colors.white24, fontSize: 10)),
            Text(record.channels.join(', '), style: const TextStyle(fontSize: 10, color: Colors.white38)),
          ]),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_timeAgo(record.sentAt), style: const TextStyle(fontSize: 10, color: Colors.white38)),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(_statusLabel,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _statusColor)),
          ),
        ]),
      ]),
    );
  }
}

class _FeedLegend extends StatelessWidget {
  const _FeedLegend({required this.color, required this.label, this.isLine = false});
  final Color color; final String label; final bool isLine;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    isLine
        ? Container(width: 14, height: 3, color: color)
        : Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery Tracking Card
// ─────────────────────────────────────────────────────────────────────────────

class _DeliveryTrackingCard extends StatelessWidget {
  const _DeliveryTrackingCard({required this.history});
  final List<_BroadcastRecord> history;

  int get _totalRecipients => history.fold(0, (s, b) => s + b.deliveredCount + b.failedCount);
  int get _seen    => history.fold(0, (s, b) => s + b.deliveredCount);
  int get _notSeen => history.fold(0, (s, b) => s + b.failedCount);

  static const _mockRows = <_DeliveryRow>[
    _DeliveryRow(name: 'John Smith',     role: 'Staff',    channel: 'Push',  status: true,  lastSeen: '2 min ago'),
    _DeliveryRow(name: 'Mary Johnson',   role: 'Occupant', channel: 'In-App',status: true,  lastSeen: '2 min ago'),
    _DeliveryRow(name: 'David Brown',    role: 'Staff',    channel: 'SMS',   status: true,  lastSeen: '3 min ago'),
    _DeliveryRow(name: 'Emily Davis',    role: 'Occupant', channel: 'Push',  status: false, lastSeen: null),
    _DeliveryRow(name: 'Michael Wilson', role: 'Staff',    channel: 'PA',    status: true,  lastSeen: '1 min ago'),
    _DeliveryRow(name: 'Sophia Martinez',role: 'Occupant', channel: 'In-App',status: false, lastSeen: null),
    _DeliveryRow(name: 'Daniel Lee',     role: 'Occupant', channel: 'SMS',   status: true,  lastSeen: '4 min ago'),
  ];

  @override
  Widget build(BuildContext context) {
    final seenPct = _totalRecipients > 0 ? (_seen / _totalRecipients * 100).round() : 0;
    final notPct  = _totalRecipients > 0 ? (_notSeen / _totalRecipients * 100).round() : 0;

    return _BCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Delivery Tracking (Per User/Device)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 12),
      // Summary row
      Row(children: [
        _TrackStat(label: 'Total Recipients', value: '$_totalRecipients', color: Colors.white70),
        const SizedBox(width: 16),
        _TrackStat(label: 'Seen', value: '$_seen\n$seenPct%', color: _kSuccess),
        const SizedBox(width: 16),
        _TrackStat(label: 'Not Seen', value: '$_notSeen\n$notPct%', color: _kEmergency),
      ]),
      const SizedBox(height: 12),
      const Divider(color: Color(0xFF2A1A14), height: 1),
      const SizedBox(height: 8),
      // Table header
      Row(children: const [
        Expanded(flex: 3, child: _TH(label: 'Recipient')),
        Expanded(flex: 2, child: _TH(label: 'Role')),
        Expanded(flex: 2, child: _TH(label: 'Channel')),
        Expanded(flex: 2, child: _TH(label: 'Status')),
        Expanded(flex: 2, child: _TH(label: 'Last Seen')),
      ]),
      const SizedBox(height: 6),
      ..._mockRows.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Expanded(flex: 3, child: Text(r.name,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(r.role,
              style: const TextStyle(fontSize: 11, color: Colors.white38))),
          Expanded(flex: 2, child: Text(r.channel,
              style: const TextStyle(fontSize: 11, color: Colors.white38))),
          Expanded(flex: 2, child: Row(children: [
            Container(width: 7, height: 7,
                decoration: BoxDecoration(
                    color: r.status ? _kSuccess : _kEmergency,
                    shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(r.status ? 'Seen' : 'Not Seen',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: r.status ? _kSuccess : _kEmergency)),
          ])),
          Expanded(flex: 2, child: Text(r.lastSeen ?? '—',
              style: const TextStyle(fontSize: 10, color: Colors.white38))),
        ]),
      )),
      const SizedBox(height: 8),
      Row(children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: _kSuccess, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        const Text('Seen', style: TextStyle(fontSize: 10, color: Colors.white38)),
        const SizedBox(width: 12),
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: _kEmergency, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        const Text('Not Seen', style: TextStyle(fontSize: 10, color: Colors.white38)),
      ]),
    ]));
  }
}

class _TrackStat extends StatelessWidget {
  const _TrackStat({required this.label, required this.value, required this.color});
  final String label, value; final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color, height: 1.2)),
  ]);
}

class _TH extends StatelessWidget {
  const _TH({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white38));
}

// ─────────────────────────────────────────────────────────────────────────────
// Scheduled Broadcasts Card
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduledCard extends StatelessWidget {
  const _ScheduledCard({required this.scheduled});
  final List<_ScheduledBroadcast> scheduled;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  '
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';

  Color _typeColor(_MsgType t) {
    switch (t) {
      case _MsgType.emergency: return _kEmergency;
      case _MsgType.warning:   return _kWarning;
      case _MsgType.info:      return _kInfo;
    }
  }

  IconData _typeIcon(_MsgType t) {
    switch (t) {
      case _MsgType.emergency: return Icons.warning_rounded;
      case _MsgType.warning:   return Icons.warning_amber_rounded;
      case _MsgType.info:      return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _BCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Scheduled Broadcasts',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 12),
      if (scheduled.isEmpty)
        const Text('No scheduled broadcasts.', style: TextStyle(color: Colors.white38, fontSize: 12))
      else
        ...scheduled.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 28, height: 28,
                decoration: BoxDecoration(color: _typeColor(s.type).withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(_typeIcon(s.type), size: 13, color: _typeColor(s.type))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.message, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
              Text(_fmt(s.scheduledAt), style: const TextStyle(fontSize: 10, color: Colors.white38)),
              Text('${s.audience} · ${s.channels.join(', ')}',
                  style: const TextStyle(fontSize: 10, color: Colors.white38)),
            ])),
            Row(children: [
              GestureDetector(
                onTap: () {},
                child: const Icon(Icons.edit_outlined, size: 15, color: Colors.white38),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {},
                child: const Icon(Icons.delete_outline_rounded, size: 15, color: _kEmergency),
              ),
            ]),
          ]),
        )),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Priority Override Card
// ─────────────────────────────────────────────────────────────────────────────

class _PriorityOverrideCard extends StatelessWidget {
  const _PriorityOverrideCard({required this.enabled, required this.onToggle});
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enabled ? _kOverride.withValues(alpha: 0.08) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? _kOverride.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.lock_rounded, size: 16, color: enabled ? _kOverride : Colors.white38),
          const SizedBox(width: 8),
          Text('Priority Override (Emergency Lock)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: enabled ? _kOverride : Colors.white70)),
        ]),
        const SizedBox(height: 12),
        if (enabled) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kOverride.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kOverride.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('EMERGENCY OVERRIDE MODE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _kOverride, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              const Text('When enabled, all user screens will be locked\nand the emergency message will be displayed.',
                  style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        ...const [
          '🔒 Locks all user screens',
          '📢 Displays full-screen alert',
          '🔕 Overrides DND / Silent mode',
          '👤 Requires admin approval to disable',
        ].map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            Text(t.substring(0, 2), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Text(t.substring(2), style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        )),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => onToggle(!enabled),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: enabled ? _kOverride.withValues(alpha: 0.2) : _kOverride,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kOverride),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(enabled ? Icons.lock_open_rounded : Icons.lock_rounded,
                  size: 14, color: Colors.white),
              const SizedBox(width: 8),
              Text(enabled ? 'DISABLE OVERRIDE' : 'ENABLE OVERRIDE',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: 0.5)),
            ]),
          ),
        ),
        if (!enabled) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.info_outline, size: 12, color: _kWarning),
            const SizedBox(width: 5),
            const Text('Use only for critical life-safety emergencies.',
                style: TextStyle(fontSize: 10, color: _kWarning)),
          ]),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message Templates Card
// ─────────────────────────────────────────────────────────────────────────────

class _TemplatesCard extends StatelessWidget {
  const _TemplatesCard({required this.templates, required this.onUse, required this.onAdd});
  final List<String> templates;
  final ValueChanged<String> onUse;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _BCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Message Templates',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
        const Spacer(),
        GestureDetector(
          onTap: onAdd,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add, size: 14, color: AppColors.accent),
            const SizedBox(width: 4),
            const Text('Add New Template',
                style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: templates.map((t) => GestureDetector(
        onTap: () => onUse(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(t, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
      )).toList()),
    ]));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _BCard extends StatelessWidget {
  const _BCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: child,
  );
}
