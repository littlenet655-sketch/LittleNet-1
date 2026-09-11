import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';

class UserAdminScreen extends StatefulWidget {
  const UserAdminScreen({
    super.key,
    required this.authState,
  });

  final AuthState authState;

  @override
  State<UserAdminScreen> createState() => _UserAdminScreenState();
}

class _UserAdminScreenState extends State<UserAdminScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  String _selectedRoleFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = _searchCtrl.text.trim();
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/admin/users',
        query: query.isNotEmpty ? {'q': query} : null,
      );

      if (res['ok'] == true && mounted) {
        final list = res['users'] as List? ?? [];
        setState(() {
          _users = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to fetch users directory.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateUserStatus(
      int targetUserId, String newStatus, String username) async {
    final currentUserId = widget.authState.currentUser?.userId;
    final isCurrentAdmin =
        currentUserId != null && targetUserId == currentUserId;
    if (isCurrentAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot modify your own administrator account status.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final res = await widget.authState.apiClient.postJson(
        '/api/mobile/v1/admin/users/$targetUserId/status',
        {'status': newStatus},
      );

      if (res['ok'] == true && mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'SUSPENDED'
                  ? 'Account @$username has been suspended.'
                  : 'Account @$username is now active.',
            ),
            backgroundColor: newStatus == 'SUSPENDED'
                ? const Color(0xFFDC2626)
                : const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchUsers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update account status.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showUserAccountModal(Map<String, dynamic> user) {
    final userId = user['user_id'] as int? ?? 0;
    final username = user['username'] as String? ?? 'user';
    final fullName = user['full_name'] as String? ?? username;
    final email = user['email'] as String? ?? 'No email on record';
    final role = user['role'] as String? ?? 'UNKNOWN';
    final accountStatus = user['account_status'] as String? ?? 'ACTIVE';
    final age = user['age'];
    final createdAt = user['created_at'] as String? ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF0F172A),
                    child: Text(
                      fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '@$username · ID #$userId',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),

              _buildDetailRow('Role', role, isBadge: true),
              _buildDetailRow('Status', accountStatus, isBadge: true),
              _buildDetailRow('Email', email),
              if (age != null) _buildDetailRow('Age', '$age years old'),
              _buildDetailRow('Created', createdAt),

              const SizedBox(height: 24),

              if (role != 'ADMIN') ...[
                if (accountStatus == 'ACTIVE')
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _updateUserStatus(userId, 'SUSPENDED', username);
                      },
                      icon: const Icon(Icons.block_rounded),
                      label: const Text(
                        'Suspend User Account',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _updateUserStatus(userId, 'ACTIVE', username);
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text(
                        'Reactivate User Account',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBadge = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          if (isBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: value == 'ACTIVE'
                    ? const Color(0xFFDCFCE7)
                    : value == 'SUSPENDED'
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: value == 'ACTIVE'
                      ? const Color(0xFF166534)
                      : value == 'SUSPENDED'
                          ? const Color(0xFF991B1B)
                          : const Color(0xFF334155),
                ),
              ),
            )
          else
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredUsers() {
    if (_selectedRoleFilter == 'ALL') return _users;
    return _users.where((u) => u['role'] == _selectedRoleFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Administration',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Accounts, Roles & Compliance Directory',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFCBD5E1)),
            tooltip: 'Refresh Users',
            onPressed: _fetchUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by name, @username, or email...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _fetchUsers();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _fetchUsers(),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ALL', 'All Users (${_users.length})'),
                      _buildFilterChip(
                          'CHILD',
                          'Children (${_users.where((u) => u['role'] == 'CHILD').length})'),
                      _buildFilterChip(
                          'PARENT',
                          'Parents (${_users.where((u) => u['role'] == 'PARENT').length})'),
                      _buildFilterChip(
                          'ADMIN',
                          'Admins (${_users.where((u) => u['role'] == 'ADMIN').length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // User list or state
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF0F172A),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFDC2626),
                              size: 40,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: const TextStyle(
                                  color: Color(0xFF64748B), fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _fetchUsers,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching users found.',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 14,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchUsers,
                            color: const Color(0xFF0F172A),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 12, 16, 100),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final u = filtered[index];
                                return _buildUserTile(u);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String roleKey, String label) {
    final isSelected = _selectedRoleFilter == roleKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF0F172A),
        backgroundColor: const Color(0xFFF1F5F9),
        showCheckmark: false,
        onSelected: (selected) {
          if (selected) {
            setState(() => _selectedRoleFilter = roleKey);
          }
        },
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['user_id'] as int? ?? 0;
    final username = user['username'] as String? ?? 'user';
    final fullName = user['full_name'] as String? ?? username;
    final role = user['role'] as String? ?? 'USER';
    final status = user['account_status'] as String? ?? 'ACTIVE';
    final isSuspended = status == 'SUSPENDED';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuspended
              ? const Color(0xFFFECACA)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: role == 'CHILD'
              ? const Color(0xFFEFF6FF)
              : role == 'PARENT'
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFF8FAFC),
          child: Icon(
            role == 'CHILD'
                ? Icons.child_care_rounded
                : role == 'PARENT'
                    ? Icons.supervised_user_circle_rounded
                    : Icons.admin_panel_settings_rounded,
            color: role == 'CHILD'
                ? const Color(0xFF2563EB)
                : role == 'PARENT'
                    ? const Color(0xFF059669)
                    : const Color(0xFF0F172A),
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                fullName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isSuspended
                      ? const Color(0xFF991B1B)
                      : const Color(0xFF0F172A),
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSuspended
                    ? const Color(0xFFFEE2E2)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSuspended
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF166534),
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '@$username · $role · ID #$userId',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
            if (user['email'] != null &&
                user['email'].toString().isNotEmpty)
              Text(
                '${user['email']}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                ),
              ),
          ],
        ),
        trailing: const Icon(
          Icons.more_vert_rounded,
          color: Color(0xFF94A3B8),
        ),
        onTap: () => _showUserAccountModal(user),
      ),
    );
  }
}
