import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProfilScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  final Future<Map<String, dynamic>>? userFuture;

  const ProfilScreen({
    super.key,
    required this.onLogout,
    this.userFuture,
  });

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  late Future<Map<String, dynamic>> _userFuture;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _userFuture = widget.userFuture ?? ApiService.getCurrentUser();
  }

  void _retryLoadUser() {
    setState(() {
      _userFuture = ApiService.getCurrentUser();
    });
  }

  void _showMessage(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? const Color(0xFFB04242) : const Color(0xFF1E6B52),
          content: Text(message),
        ),
      );
  }

  Future<void> _openEditProfile() async {
    final currentUser = await _userFuture.catchError((_) => <String, dynamic>{});
    if (!mounted) return;

    final nameController = TextEditingController(
      text: currentUser['name']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: currentUser['email']?.toString() ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool saving = false;
            return AlertDialog(
              title: const Text('Hesap Bilgilerini Düzenle'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-posta',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final email = emailController.text.trim();

                          if (name.isEmpty || email.isEmpty) {
                            _showMessage('Ad soyad ve e-posta zorunludur');
                            return;
                          }

                          setState(() => saving = true);
                          try {
                            final updatedUser = await ApiService.updateCurrentUser(
                              name: name,
                              email: email,
                            );
                            if (!mounted) return;
                            setState(() {
                              _userFuture = Future.value(updatedUser);
                            });
                            if (ctx.mounted) {
                              Navigator.pop(ctx, true);
                            }
                            _showMessage('Profil bilgileri güncellendi', isError: false);
                          } catch (e) {
                            _showMessage(e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            if (ctx.mounted) {
                              setState(() => saving = false);
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
  }

  Future<void> _openChangePassword() async {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool saving = false;
            return AlertDialog(
              title: const Text('Şifre Değiştir'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mevcut Şifre',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre Tekrar',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final currentPassword = currentPasswordController.text.trim();
                          final newPassword = newPasswordController.text.trim();
                          final confirmPassword = confirmPasswordController.text.trim();

                          if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                            _showMessage('Tüm şifre alanları zorunludur');
                            return;
                          }

                          if (newPassword.length < 8) {
                            _showMessage('Yeni şifre en az 8 karakter olmalıdır');
                            return;
                          }

                          if (newPassword != confirmPassword) {
                            _showMessage('Yeni şifreler eşleşmiyor');
                            return;
                          }

                          setState(() => saving = true);
                          try {
                            await ApiService.changePassword(
                              currentPassword: currentPassword,
                              newPassword: newPassword,
                            );
                            if (!mounted) return;
                            if (ctx.mounted) {
                              Navigator.pop(ctx, true);
                            }
                            _showMessage('Şifre başarıyla güncellendi', isError: false);
                          } catch (e) {
                            _showMessage(e.toString().replaceFirst('Exception: ', ''));
                          } finally {
                            if (ctx.mounted) {
                              setState(() => saving = false);
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Çıkış Yap"),
        content: const Text("Hesabından çıkış yapmak istediğine emin misin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB04242)),
            child: const Text("Çıkış Yap"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loggingOut = true);
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Profil bilgisi alınamadı',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error?.toString() ?? 'Lütfen daha sonra tekrar deneyin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _retryLoadUser,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            );
          }

          final name = snapshot.data?['name']?.toString() ?? 'Kullanıcı';
          final email = snapshot.data?['email']?.toString() ?? '';

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Center(
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[300],
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 30),
                _buildProfileOption(
                  icon: Icons.account_circle,
                  title: 'Hesap Bilgileri',
                  onTap: _openEditProfile,
                ),
                _buildProfileOption(
                  icon: Icons.lock,
                  title: 'Şifre Değiştir',
                  onTap: _openChangePassword,
                ),
                _buildProfileOption(
                  icon: Icons.notifications,
                  title: 'Bildirimler',
                  onTap: () {},
                ),
                _buildProfileOption(
                  icon: Icons.settings,
                  title: 'Ayarlar',
                  onTap: () {},
                ),
                _buildProfileOption(
                  icon: Icons.help,
                  title: 'Yardım',
                  onTap: () {},
                ),
                _buildProfileOption(
                  icon: Icons.logout,
                  title: 'Çıkış Yap',
                  onTap: _loggingOut ? () {} : _confirmLogout,
                  isLast: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: onTap,
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}
