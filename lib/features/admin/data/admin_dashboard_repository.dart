import 'dart:async';

import 'package:frontend/features/admin/models/admin_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboardRepository {
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<List<IncidentSummary>> fetchActiveIncidents() async {
    final client = _client;
    if (client == null) {
      return _mockIncidents();
    }

    try {
      final rows = await client
          .from('incidents')
          .select('id,incident_type,location,created_at,status')
          .inFilter('status', const ['active', 'assigned'])
          .order('created_at', ascending: false);

      return rows
          .map<IncidentSummary>(
            (row) => IncidentSummary(
              id: row['id'].toString(),
              type: (row['incident_type'] ?? 'Unknown').toString(),
              location: (row['location'] ?? 'Unknown Location').toString(),
              time:
                  DateTime.tryParse((row['created_at'] ?? '').toString()) ??
                  DateTime.now(),
              status: (row['status'] ?? 'active').toString(),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return _mockIncidents();
    }
  }

  Future<List<StaffProfile>> fetchStaffRoster() async {
    final client = _client;
    if (client == null) {
      return _mockStaff();
    }

    try {
      // Try staff_profiles first (admin table with richer schema)
      List<dynamic> rows = [];
      bool useStaffTable = false;
      try {
        rows = await client
            .from('staff_profiles')
            .select('id,full_name,current_role,current_location')
            .order('full_name');
      } catch (_) {}

      if (rows.isEmpty) {
        // Fallback to the staff table used by the staff-facing app
        rows = await client
            .from('staff')
            .select('id,staff_name,is_on_duty')
            .order('staff_name');
        useStaffTable = true;
      }

      return rows
          .map<StaffProfile>(
            (row) => StaffProfile(
              id: row['id'].toString(),
              name: useStaffTable
                  ? (row['staff_name'] ?? 'Unknown Staff').toString()
                  : (row['full_name'] ?? 'Unknown Staff').toString(),
              role: useStaffTable
                  ? (row['role'] ?? 'Responder').toString()
                  : (row['current_role'] ?? 'Responder').toString(),
              location: useStaffTable
                  ? (row['location'] ?? 'Unknown').toString()
                  : (row['current_location'] ?? 'Unknown').toString(),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return _mockStaff();
    }
  }

  Future<void> assignStaffToIncident({
    required String incidentId,
    required String staffId,
    required String assignedStaff,
    required String incidentType,
    required String location,
  }) async {
    final client = _client;
    if (client == null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return;
    }

    await client.from('staff_assignments').upsert({
      'incident_id': incidentId,
      'staff_id': staffId,
      'assigned_at': DateTime.now().toIso8601String(),
      'status': 'assigned',
    }, onConflict: 'incident_id,staff_id');

    await client.from('task_assignments').upsert({
      'id': incidentId,
      'incident_type': incidentType,
      'location': location,
      'role': _roleForIncidentType(incidentType),
      'route': _routeForIncidentType(incidentType),
      'assigned_staff': assignedStaff,
      'status': 'assigned',
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id');
  }

  String _roleForIncidentType(String incidentType) {
    final normalized = incidentType.toLowerCase();
    if (normalized.contains('fire')) {
      return 'Check corridor evacuation';
    }
    if (normalized.contains('medical')) {
      return 'Provide immediate medical triage';
    }
    if (normalized.contains('trapped')) {
      return 'Assist rescue and extraction';
    }
    return 'Support incident response operations';
  }

  String _routeForIncidentType(String incidentType) {
    final normalized = incidentType.toLowerCase();
    if (normalized.contains('fire')) {
      return 'Stairwell A';
    }
    if (normalized.contains('medical')) {
      return 'Elevator Core B (priority lane)';
    }
    if (normalized.contains('trapped')) {
      return 'Stairwell C';
    }
    return 'Nearest safe route';
  }

  List<IncidentSummary> _mockIncidents() {
    final now = DateTime.now();
    return <IncidentSummary>[
      IncidentSummary(
        id: 'incident-fire-1',
        type: 'Fire',
        location: 'Floor 6 - Room 612',
        time: now.subtract(const Duration(minutes: 4)),
        status: 'active',
      ),
      IncidentSummary(
        id: 'incident-medical-1',
        type: 'Medical SOS',
        location: 'Floor 2 - Lobby Wing',
        time: now.subtract(const Duration(minutes: 2)),
        status: 'active',
      ),
      IncidentSummary(
        id: 'incident-trapped-1',
        type: 'Trapped Guest',
        location: 'Floor 3 - Stairwell B',
        time: now.subtract(const Duration(minutes: 1)),
        status: 'assigned',
      ),
    ];
  }

  List<StaffProfile> _mockStaff() => const <StaffProfile>[
    StaffProfile(
      id: 'staff-01',
      name: 'Alex Moreno',
      role: 'Fire Marshal',
      location: 'Floor 6',
    ),
    StaffProfile(
      id: 'staff-02',
      name: 'Priya Sen',
      role: 'Medical Staff',
      location: 'Floor 2',
    ),
    StaffProfile(
      id: 'staff-03',
      name: 'Jordan Kim',
      role: 'Floor Staff',
      location: 'Floor 3',
    ),
    StaffProfile(
      id: 'staff-04',
      name: 'Riley Park',
      role: 'Security',
      location: 'Floor 1',
    ),
  ];
}
