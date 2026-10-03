import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.45),
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
        await ApiService.getMe(
          token: savedToken,
        ).timeout(const Duration(seconds: 5));
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
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
    final password = _passwordController.text;
    final passwordConfirmation = _passwordConfirmationController.text;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (email.isEmpty || password.trim().isEmpty) {
      _showMessage("E-posta ve şifre zorunludur");
      return;
    }

    if (!_isLogin) {
      if (firstName.isEmpty || lastName.isEmpty) {
        _showMessage("Ad ve soyad alanları zorunludur");
        return;
      }
      if (_isReservedExampleEmail(email)) {
        _showMessage("Örnek e-posta alan adlarıyla kayıt yapılamaz");
        return;
      }
      if (password != passwordConfirmation) {
        _showMessage("Şifreler eşleşmiyor");
        return;
      }
      if (!_hasStrongPassword(password)) {
        _showMessage(
          "Şifre 8 karakter; büyük harf, küçük harf, rakam ve sembol içermeli",
        );
        return;
      }
    }

    setState(() {
      _loading = true;
    });

    try {
      late final Map<String, dynamic> response;

      if (_isLogin) {
        response = await ApiService.login(
          email: email,
          password: password.trim(),
        );
      } else {
        response = await ApiService.register(
          firstName: firstName,
          lastName: lastName,
          email: email,
          password: password,
          passwordConfirmation: passwordConfirmation,
        );
      }

      final token = (response["access_token"] ?? "").toString();
      if (token.isEmpty) {
        throw Exception("Token alınamadı");
      }

      await widget.onAuthenticated(token);
      _showMessage(
        _isLogin ? "Giriş başarılı" : "Hesabın oluşturuldu",
        error: false,
      );
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

  bool _hasStrongPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9\s]').hasMatch(password);
  }

  bool _isReservedExampleEmail(String email) {
    final atIndex = email.lastIndexOf('@');
    if (atIndex < 1) return false;

    final domain = email.substring(atIndex + 1).toLowerCase();
    const reservedDomains = {'example.com', 'example.net', 'example.org'};
    const reservedSuffixes = ['.example', '.invalid', '.localhost', '.test'];

    return reservedDomains.any(
          (reserved) => domain == reserved || domain.endsWith('.$reserved'),
        ) ||
        reservedSuffixes.any(domain.endsWith);
  }

  Widget _passwordRequirement(String label, bool satisfied) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          satisfied ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 15,
          color: satisfied ? const Color(0xFF1E6B52) : const Color(0xFF9AA39D),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: satisfied
                ? const Color(0xFF1E6B52)
                : const Color(0xFF68716B),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final password = _passwordController.text;
    final passwordConfirmation = _passwordConfirmationController.text;

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
                        _isLogin
                            ? "Finansal paneline devam etmek için giriş yap."
                            : "Hesabını oluşturmak için bilgilerini gir.",
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      if (!_isLogin) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _firstNameController,
                                inputFormatters: [
                                  FilteringTextInputFormatter.deny(
                                    RegExp(r'[0-9]'),
                                  ),
                                ],
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Ad",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _lastNameController,
                                inputFormatters: [
                                  FilteringTextInputFormatter.deny(
                                    RegExp(r'[0-9]'),
                                  ),
                                ],
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: "Soyad",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
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
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (!_isLogin) setState(() {});
                        },
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: "Şifre",
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? "Şifreyi gizle"
                                : "Şifreyi göster",
                            onPressed: () {
                              setState(() => _showPassword = !_showPassword);
                            },
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordConfirmationController,
                          obscureText: !_showPassword,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: "Şifreyi tekrar gir",
                            border: const OutlineInputBorder(),
                            errorText:
                                passwordConfirmation.isEmpty ||
                                    passwordConfirmation == password
                                ? null
                                : "Şifreler eşleşmiyor",
                          ),
                        ),
                      ],
                      if (!_isLogin) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: [
                            _passwordRequirement(
                              '8+ karakter',
                              password.length >= 8,
                            ),
                            _passwordRequirement(
                              'Büyük harf',
                              RegExp(r'[A-Z]').hasMatch(password),
                            ),
                            _passwordRequirement(
                              'Küçük harf',
                              RegExp(r'[a-z]').hasMatch(password),
                            ),
                            _passwordRequirement(
                              'Rakam',
                              RegExp(r'[0-9]').hasMatch(password),
                            ),
                            _passwordRequirement(
                              'Sembol',
                              RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
                            ),
                          ],
                        ),
                      ],
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
