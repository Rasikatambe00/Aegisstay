enum AdminNavTab {
  dashboard,
  digitalTwinMap,
  incidentControl,
  staffManagement,
  evacuationMonitor,
  broadcast,
  equipment,
  history,
  configuration,
}

class IncidentSummary {
  const IncidentSummary({
    required this.id,
    required this.type,
    required this.location,
    required this.time,
    required this.status,
  });

  final String id;
  final String type;
  final String location;
  final DateTime time;
  final String status;
}

class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.location,
  });

  final String id;
  final String name;
  final String role;
  final String location;
}
