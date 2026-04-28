import 'package:flutter/material.dart';
import 'package:frontend/features/admin/data/admin_dashboard_repository.dart';
import 'package:frontend/features/admin/models/admin_models.dart';

class DashboardProvider extends ChangeNotifier {
  DashboardProvider({AdminDashboardRepository? repository})
    : _repository = repository ?? AdminDashboardRepository();

  final AdminDashboardRepository _repository;

  AdminNavTab activeTab = AdminNavTab.dashboard;
  bool isLoading = false;
  String? errorMessage;
  List<IncidentSummary> incidents = const <IncidentSummary>[];
  List<StaffProfile> staff = const <StaffProfile>[];
  final Map<String, String> incidentAssignments = <String, String>{};

  int get totalIncidents => incidents.length;
  int get fireAlerts => incidents
      .where((incident) => incident.type.toLowerCase().contains('fire'))
      .length;
  int get medicalAlerts => incidents
      .where((incident) => incident.type.toLowerCase().contains('medical'))
      .length;
  int get trappedGuests => incidents
      .where((incident) => incident.type.toLowerCase().contains('trapped'))
      .length;
  double get evacuationProgress {
    if (incidents.isEmpty) {
      return 1;
    }
    final resolvedCount = incidents
        .where((incident) => incident.status.toLowerCase() == 'resolved')
        .length;
    return resolvedCount / incidents.length;
  }

  void setActiveTab(AdminNavTab tab) {
    if (tab == activeTab) {
      return;
    }
    activeTab = tab;
    notifyListeners();
  }

  Future<void> initialize() async {
    if (isLoading || incidents.isNotEmpty || staff.isNotEmpty) {
      return;
    }
    await refreshData();
  }

  Future<void> refreshData() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.fetchActiveIncidents(),
        _repository.fetchStaffRoster(),
      ]);
      incidents = results[0] as List<IncidentSummary>;
      staff = results[1] as List<StaffProfile>;
    } catch (_) {
      errorMessage = 'Unable to load live data right now.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> assignStaff({
    required String incidentId,
    required String staffId,
  }) async {
    final assignedStaffList = staff
        .where((member) => member.id == staffId)
        .map((member) => member.name)
        .toList(growable: false);
    final incidentList = incidents
        .where((item) => item.id == incidentId)
        .toList(growable: false);

    final assignedStaff = assignedStaffList.isEmpty
        ? null
        : assignedStaffList.first;
    final incident = incidentList.isEmpty ? null : incidentList.first;

    if (assignedStaff == null || incident == null) {
      errorMessage = 'Unable to create assignment at the moment.';
      notifyListeners();
      return;
    }

    await _repository.assignStaffToIncident(
      incidentId: incidentId,
      staffId: staffId,
      assignedStaff: assignedStaff,
      incidentType: incident.type,
      location: incident.location,
    );
    incidentAssignments[incidentId] = staffId;
    notifyListeners();
  }
}
