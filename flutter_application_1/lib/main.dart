import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() {
  runApp(const FinanceCoachApp());
}

class FinanceCoachApp extends StatelessWidget {
  const FinanceCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF5F3EC);
    const surface = Color(0xFFFFFCF6);
    const ink = Color(0xFF1E2722);
    const accent = Color(0xFF1E6B52);
    const accentSoft = Color(0xFFDDEEE7);
    const warning = Color(0xFFC96B3B);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      primary: accent,
      secondary: warning,
      surface: surface,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Finance Coach',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: ink,
            height: 1.05,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: ink,
            height: 1.45,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: Color(0xFF53625B),
            height: 1.4,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: ink,
          titleTextStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: accentSoft,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
              );
            }
            return const TextStyle(
              color: Color(0xFF67756F),
              fontWeight: FontWeight.w500,
            );
          }),
        ),
      ),
      home: const _AppEntryPoint(),
    );
  }
}

class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  static const String onboardingKey = 'has_seen_onboarding';
  static const String tokenKey = 'auth_token';

  bool _loading = true;
  bool _hasSeenOnboarding = false;
  String? _token;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await InstallmentReminderService.initialize();

    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool(onboardingKey) ?? false;
    final savedToken = prefs.getString(tokenKey);

    String? validToken;
    if (savedToken != null && savedToken.isNotEmpty) {
      try {
        await ApiService.getMe(token: savedToken).timeout(
          const Duration(seconds: 5),
        );
        validToken = savedToken;
      } catch (_) {
        await prefs.remove(tokenKey);
      }
    }

    ApiService.setToken(validToken);

    if (!mounted) return;
    setState(() {
      _hasSeenOnboarding = hasSeenOnboarding;
      _token = validToken;
      _loading = false;
    });
  }

  Future<void> _onOnboardingFinished() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, true);

    if (!mounted) return;
    setState(() {
      _hasSeenOnboarding = true;
    });
  }

  Future<void> _onAuthenticated(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, token);
    ApiService.setToken(token);

    if (!mounted) return;
    setState(() {
      _token = token;
    });
  }

  Future<void> _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    ApiService.clearToken();

    if (!mounted) return;
    setState(() {
      _token = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasSeenOnboarding) {
      return OnboardingScreen(onFinished: _onOnboardingFinished);
    }

    if (_token == null) {
      return AuthScreen(onAuthenticated: _onAuthenticated);
    }

    return MainScreen(onLogout: _onLogout);
  }
}

class AuthScreen extends StatefulWidget {
  final Future<void> Function(String token) onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _loading = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String text, {bool error = true}) {
    if (!mounted) return;
    final accent = error ? const Color(0xFFB04242) : const Color(0xFF1E6B52);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: accent,
          elevation: 0,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage("E-posta ve şifre zorunludur");
      return;
    }

    if (!_isLogin && name.isEmpty) {
      _showMessage("Ad soyad zorunludur");
      return;
    }

    if (password.length < 8) {
      _showMessage("Şifre en az 8 karakter olmalı");
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      late final Map<String, dynamic> response;

      if (_isLogin) {
        response = await ApiService.login(
          email: email,
          password: password,
        );
      } else {
        response = await ApiService.register(
          name: name,
          email: email,
          password: password,
        );
      }

      final token = (response["access_token"] ?? "").toString();
      if (token.isEmpty) {
        throw Exception("Token alınamadı");
      }

      await widget.onAuthenticated(token);
      _showMessage("Giriş başarılı", error: false);
    } catch (e) {
      _showMessage(e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F3EC), Color(0xFFFDF9F1), Color(0xFFEAF3ED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF6),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFE8DFD3)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLogin ? "Giriş Yap" : "Kayıt Ol",
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Finansal paneline devam etmek için hesap oluştur veya giriş yap.",
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      if (!_isLogin) ...[
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: "Ad Soyad",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: "E-posta",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: "Şifre",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E6B52),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isLogin ? "Giriş Yap" : "Kayıt Ol"),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  setState(() {
                                    _isLogin = !_isLogin;
                                  });
                                },
                          child: Text(
                            _isLogin
                                ? "Hesabın yok mu? Kayıt ol"
                                : "Zaten hesabın var mı? Giriş yap",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}