import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class IncidentTask {
  IncidentTask({
    required this.id,
    required this.incidentId,
    required this.title,
    required this.assignedTo,
    required this.priority,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String incidentId;
  final String title;
  final String assignedTo;
  final String priority; // HIGH | MEDIUM | LOW
  String status;         // Assigned | In Progress | Completed
  final DateTime createdAt;

  IncidentTask copyWith({String? status}) => IncidentTask(
        id: id,
        incidentId: incidentId,
        title: title,
        assignedTo: assignedTo,
        priority: priority,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

class TaskProvider extends ChangeNotifier {
  // tasks keyed by incidentId
  final Map<String, List<IncidentTask>> _tasks = {};
  final Map<String, bool> _loading = {};

  SupabaseClient? get _db {
    try { return Supabase.instance.client; } catch (_) { return null; }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  List<IncidentTask> getTasksByIncident(String incidentId) =>
      _tasks[incidentId] ?? [];

  bool isLoading(String incidentId) => _loading[incidentId] ?? false;

  /// Fetch tasks for a given incident from Supabase.
  Future<void> loadTasks(String incidentId) async {
    _loading[incidentId] = true;
    notifyListeners();

    try {
      final db = _db;
      if (db == null) throw Exception('offline');

      final rows = await db
          .from('incident_tasks')
          .select('id,incident_id,title,assigned_to,priority,status,created_at')
          .eq('incident_id', incidentId)
          .order('created_at', ascending: true);

      _tasks[incidentId] = rows.map<IncidentTask>(_fromRow).toList();
    } catch (_) {
      // Keep existing tasks (or empty list) on error
      _tasks.putIfAbsent(incidentId, () => []);
    } finally {
      _loading[incidentId] = false;
      notifyListeners();
    }
  }

  /// Add a new task — inserts into Supabase and updates local state immediately.
  Future<void> addTask({
    required String incidentId,
    required String title,
    required String assignedTo,
    required String priority,
  }) async {
    // Optimistic local insert
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final task = IncidentTask(
      id: tempId,
      incidentId: incidentId,
      title: title,
      assignedTo: assignedTo,
      priority: priority,
      status: 'Assigned',
      createdAt: DateTime.now(),
    );
    _tasks.putIfAbsent(incidentId, () => []).add(task);
    notifyListeners();

    try {
      final db = _db;
      if (db == null) return; // keep optimistic entry

      final row = await db.from('incident_tasks').insert({
        'incident_id': incidentId,
        'title': title,
        'assigned_to': assignedTo,
        'priority': priority,
        'status': 'Assigned',
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      // Replace temp entry with real one
      final real = _fromRow(row);
      final list = _tasks[incidentId]!;
      final idx = list.indexWhere((t) => t.id == tempId);
      if (idx != -1) list[idx] = real;
      notifyListeners();
    } catch (_) {
      // Keep optimistic entry — will sync on next loadTasks
    }
  }

  /// Update task status.
  Future<void> updateTaskStatus(String incidentId, String taskId, String newStatus) async {
    final list = _tasks[incidentId];
    if (list == null) return;
    final idx = list.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;

    // Optimistic update
    list[idx] = list[idx].copyWith(status: newStatus);
    notifyListeners();

    try {
      final db = _db;
      if (db == null) return;
      await db.from('incident_tasks')
          .update({'status': newStatus})
          .eq('id', taskId);
    } catch (_) {
      // Revert on failure
      list[idx] = list[idx].copyWith(status: list[idx].status);
      notifyListeners();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static IncidentTask _fromRow(Map<String, dynamic> r) => IncidentTask(
        id:         r['id'].toString(),
        incidentId: r['incident_id'].toString(),
        title:      (r['title'] ?? 'Untitled').toString(),
        assignedTo: (r['assigned_to'] ?? 'Unassigned').toString(),
        priority:   (r['priority'] ?? 'MEDIUM').toString(),
        status:     (r['status'] ?? 'Assigned').toString(),
        createdAt:  DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}
