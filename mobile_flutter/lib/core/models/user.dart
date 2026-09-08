class User {
  const User({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    this.email,
    this.age,
    this.profilePicture,
    this.accountStatus = 'ACTIVE',
  });

  final int userId;
  final String username;
  final String fullName;
  final String role; // 'CHILD', 'PARENT', 'ADMIN'
  final String? email;
  final int? age;
  final String? profilePicture;
  final String accountStatus;

  bool get isChild => role.toUpperCase() == 'CHILD';
  bool get isParent => role.toUpperCase() == 'PARENT';
  bool get isAdmin => role.toUpperCase() == 'ADMIN';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ??
          json['username']?.toString() ??
          'User',
      role: json['role']?.toString().toUpperCase() ?? 'CHILD',
      email: json['email']?.toString(),
      age: json['age'] is int
          ? json['age'] as int
          : int.tryParse(json['age']?.toString() ?? ''),
      profilePicture: json['profile']?['profile_picture']?.toString() ??
          json['profile_picture']?.toString(),
      accountStatus:
          json['account_status']?.toString().toUpperCase() ?? 'ACTIVE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'username': username,
      'full_name': fullName,
      'role': role,
      'email': email,
      'age': age,
      'profile_picture': profilePicture,
      'account_status': accountStatus,
    };
  }
}
