import 'package:flutter/material.dart';
import 'package:frontend/core/app_theme.dart';
import 'package:frontend/dashboard_page.dart';
import 'package:frontend/features/admin/providers/dashboard_provider.dart';
import 'package:frontend/features/admin/screens/admin_dashboard_page.dart';
import 'package:frontend/features/staff/screens/staff_dashboard.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UserRole { guest, staff, admin }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final Set<UserRole> _selectedRole = {UserRole.guest};
  static const List<String> _staffCategories = [
    'Fire Marshals',
    'Medical Staff',
    'Security',
    'Floor Staff',
    'Other',
  ];

  final TextEditingController _guestRoomNumberController =
      TextEditingController();
  final TextEditingController _guestLastNameController =
      TextEditingController();
  final TextEditingController _staffNameController = TextEditingController();
  final TextEditingController _staffPasswordController =
      TextEditingController();
  final TextEditingController _staffOtherRoleController =
      TextEditingController();
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _adminPasswordController =
      TextEditingController();

  bool _isStaffPasswordObscured = true;
  bool _isAdminPasswordObscured = true;
  bool _isAuthenticatingStaff = false;
  bool _isAuthenticatingAdmin = false;

  // ── NEW: loading state for guest login ─────────────────────────────────────
  bool _isAuthenticatingGuest = false;

  String? _selectedStaffCategory;

  UserRole get _currentRole => _selectedRole.first;

  bool get _isLoading =>
      _isAuthenticatingStaff ||
      _isAuthenticatingAdmin ||
      _isAuthenticatingGuest;

  @override
  void dispose() {
    _guestRoomNumberController.dispose();
    _guestLastNameController.dispose();
    _staffNameController.dispose();
    _staffPasswordController.dispose();
    _staffOtherRoleController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Icon(Icons.shield, size: 72, color: AppColors.accent),
                  const SizedBox(height: 16),
                  Text(
                    'AegisStay',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hotel Safety & Crisis Management',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<UserRole>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: UserRole.guest,
                        label: Text('Guest'),
                      ),
                      ButtonSegment(
                        value: UserRole.staff,
                        label: Text('Staff'),
                      ),
                      ButtonSegment(
                        value: UserRole.admin,
                        label: Text('Admin'),
                      ),
                    ],
                    selected: _selectedRole,
                    onSelectionChanged: (newSelection) => setState(
                      () => _selectedRole
                        ..clear()
                        ..addAll(newSelection),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildRoleForm(context, _currentRole),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _onLogin,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.accent,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Login to AegisStay'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleForm(BuildContext context, UserRole role) {
    switch (role) {
      case UserRole.guest:
        return _buildGuestForm(context);
      case UserRole.staff:
        return _buildStaffForm(context);
      case UserRole.admin:
        return _buildAdminForm(context);
    }
  }

  Widget _buildGuestForm(BuildContext context) => Column(
        children: [
          StandardInput(
            controller: _guestRoomNumberController,
            keyboardType: TextInputType.number,
            label: 'Room Number',
            icon: Icons.meeting_room_outlined,
          ),
          const SizedBox(height: 16),
          // ── Label updated from "Last Name" to "Name" since the guests
          //    table stores full names like "John Doe" or just "Sarah"
          StandardInput(
            controller: _guestLastNameController,
            label: 'Name',
            hintText: 'Enter your name or last name',
            icon: Icons.badge_outlined,
          ),
        ],
      );

  Widget _buildStaffForm(BuildContext context) => Column(
        children: [
          StandardInput(
            controller: _staffNameController,
            label: 'Staff Name',
            hintText: 'Enter your name',
            icon: Icons.work_outline,
          ),
          const SizedBox(height: 16),
          StandardInput(
            controller: _staffPasswordController,
            obscureText: _isStaffPasswordObscured,
            label: 'Password',
            icon: Icons.lock_outline,
            suffixIcon: IconButton(
              onPressed: () => setState(
                () => _isStaffPasswordObscured = !_isStaffPasswordObscured,
              ),
              icon: Icon(
                _isStaffPasswordObscured
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedStaffCategory,
            decoration: const InputDecoration(
              labelText: 'Staff Category',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
            iconEnabledColor: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(24),
            dropdownColor: AppColors.card,
            items: _staffCategories
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedStaffCategory = value;
                if (value != 'Other') {
                  _staffOtherRoleController.clear();
                }
              });
            },
          ),
          if (_selectedStaffCategory == 'Other') ...[
            const SizedBox(height: 16),
            StandardInput(
              controller: _staffOtherRoleController,
              label: 'Specify Role',
              icon: Icons.edit_note_outlined,
            ),
          ],
        ],
      );

  Widget _buildAdminForm(BuildContext context) => Column(
        children: [
          StandardInput(
            controller: _adminEmailController,
            keyboardType: TextInputType.emailAddress,
            label: 'Email',
            icon: Icons.email_outlined,
          ),
          const SizedBox(height: 16),
          StandardInput(
            controller: _adminPasswordController,
            obscureText: _isAdminPasswordObscured,
            label: 'Password',
            icon: Icons.admin_panel_settings_outlined,
            suffixIcon: IconButton(
              onPressed: () => setState(
                () => _isAdminPasswordObscured = !_isAdminPasswordObscured,
              ),
              icon: Icon(
                _isAdminPasswordObscured
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
            ),
          ),
        ],
      );

  Future<void> _onLogin() async {
    // ── GUEST ─────────────────────────────────────────────────────────────────
    if (_currentRole == UserRole.guest) {
      final roomNumber = _guestRoomNumberController.text.trim();
      final nameInput = _guestLastNameController.text.trim();

      // Basic empty field check before making any network call
      if (roomNumber.isEmpty || nameInput.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your room number and name.'),
          ),
        );
        return;
      }

      setState(() => _isAuthenticatingGuest = true);
      final result = await _authenticateGuest(
        roomNumber: roomNumber,
        nameInput: nameInput,
      );
      if (!mounted) return;
      setState(() => _isAuthenticatingGuest = false);

      if (!result.isFound) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      // Use real data from Supabase — name and floor come from the database
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DashboardPage(
            guestName: result.guestName,
            roomNumber: result.roomNumber,
            floorLabel: result.floorLabel,
          ),
        ),
      );
      return;
    }

    // ── STAFF ─────────────────────────────────────────────────────────────────
    if (_currentRole == UserRole.staff) {
      if (_staffNameController.text.trim().isEmpty ||
          _staffPasswordController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter staff name and password.')),
        );
        return;
      }

      setState(() => _isAuthenticatingStaff = true);
      final authResult = await _authenticateStaff();
      if (!mounted) return;
      setState(() => _isAuthenticatingStaff = false);

      if (!authResult.isAuthenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authResult.message)),
        );
        return;
      }

      final category = _selectedStaffCategory ?? 'Fire Marshals';
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StaffDashboardPage(
            staffName: _staffNameController.text.isEmpty
                ? 'Responder'
                : _staffNameController.text.trim(),
            staffCategory: category,
          ),
        ),
      );
      return;
    }

    // ── ADMIN ─────────────────────────────────────────────────────────────────
    if (_currentRole == UserRole.admin) {
      if (_adminEmailController.text.trim().isEmpty ||
          _adminPasswordController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter your email and password.')),
        );
        return;
      }

      setState(() => _isAuthenticatingAdmin = true);

      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _adminEmailController.text.trim(),
          password: _adminPasswordController.text.trim(),
        );

        if (!mounted) return;

        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider<DashboardProvider>(
              create: (_) => DashboardProvider(),
              child: const AdminDashboardPage(),
            ),
          ),
        );
      } on AuthException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login failed. Check your connection and try again.'),
          ),
        );
      } finally {
        if (mounted) setState(() => _isAuthenticatingAdmin = false);
      }

      return;
    }
  }

  // ── NEW: Guest verification against Supabase guests table ─────────────────
  Future<({
    bool isFound,
    String message,
    String guestName,
    String roomNumber,
    String floorLabel,
  })> _authenticateGuest({
    required String roomNumber,
    required String nameInput,
  }) async {
    // Default empty result for error cases
    const empty = (
      isFound: false,
      message: '',
      guestName: '',
      roomNumber: '',
      floorLabel: '',
    );

    try {
      final client = Supabase.instance.client;

      // Query: room_number must match exactly
      //        guest_name must CONTAIN the typed name (case insensitive)
      //        so "Doe" matches "John Doe", "john" matches "John Doe"
      final rows = await client
          .from('guests')
          .select('id, guest_name, room_number, floor')
          .eq('room_number', roomNumber)
          .ilike('guest_name', '%$nameInput%')
          .limit(1);

      if (rows.isEmpty) {
        // Room + name combo doesn't exist in the guests table
        return (
          isFound: false,
          message:
              'Room $roomNumber not found for that name. Please check with reception.',
          guestName: '',
          roomNumber: '',
          floorLabel: '',
        );
      }

      final row = rows.first;

      // Use the real guest_name from DB (properly capitalized)
      final guestName = (row['guest_name'] ?? 'Guest').toString();

      // Use the real room_number from DB
      final realRoomNumber = (row['room_number'] ?? roomNumber).toString();

      // Use the real floor from DB — no more guessing from first digit
      final floor = row['floor'];
      final floorLabel = floor != null ? 'Floor $floor' : 'Floor 1';

      return (
        isFound: true,
        message: 'Welcome, $guestName',
        guestName: guestName,
        roomNumber: realRoomNumber,
        floorLabel: floorLabel,
      );
    } catch (_) {
      // Supabase is unreachable — block login, same as staff fix
      return (
        isFound: false,
        message:
            'Unable to verify your booking. Please check your connection and try again.',
        guestName: '',
        roomNumber: '',
        floorLabel: '',
      );
    }
  }

  Future<({bool isAuthenticated, String message})> _authenticateStaff() async {
    final staffName = _staffNameController.text.trim();
    final password = _staffPasswordController.text.trim();

    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('staff')
          .select('id,category')
          .eq('staff_name', staffName)
          .eq('password', password)
          .limit(1);

      if (rows.isEmpty) {
        return (
          isAuthenticated: false,
          message: 'Invalid staff name or password.',
        );
      }

      final row = rows.first;
      final category = row['category']?.toString();
      if (category != null && category.isNotEmpty) {
        _selectedStaffCategory = category;
      }

      return (isAuthenticated: true, message: 'Authenticated');
    } catch (_) {
      return (
        isAuthenticated: false,
        message:
            'Unable to verify credentials. Please check your connection and try again.',
      );
    }
  }
}