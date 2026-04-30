import 'package:flutter/material.dart';
import 'package:VoiceAndroid/screens/class_requests_screen.dart';
import 'package:VoiceAndroid/services/voice_enroll_service.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/student_dashboard.dart';
import 'screens/teacher_dashboard.dart';
import 'screens/class_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/voice_enroll_screen.dart';
import 'services/auth_service.dart';

void main() => runApp(const VoiceAndroidApp());

class VoiceAndroidApp extends StatelessWidget {
  const VoiceAndroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceAttend AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F6E56),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1B2A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1D9E75),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const _SplashRouter(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeScreen(),
        // '/logs':     (_) => const LogsScreen(),
        '/requests': (context) => const ClassRequestsScreen(),
        '/admin': (_) => const AdminScreen(),
        '/sboard': (_) => const StudentDashboard(),
        '/tboard': (_) => const TeacherDashboard(),
        '/profile': (_) => const ProfileScreen(),
        '/enroll': (_) => const VoiceEnrollScreen(isFirstTime: false),
        '/class': (_) => const ClassDetailScreen(
            classId: 0, className: '', isTeacher: false),
      },
    );
  }
}

class _SplashRouter extends StatefulWidget {
  const _SplashRouter();

  @override
  State<_SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<_SplashRouter> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    await Future.delayed(const Duration(milliseconds: 300));
    final user = await AuthService.getStoredUser();
    if (!mounted) return;

    if (user == null) {
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      switch (user['role']) {
        case 'admin':
          Navigator.pushReplacementNamed(context, '/admin');
          break;
        case 'teacher':
          Navigator.pushReplacementNamed(context, '/tboard');
          break;
        default: // student
          Navigator.pushReplacementNamed(context, '/sboard');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D1B2A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spatial_audio_off, size: 72, color: Colors.teal),
            SizedBox(height: 16),
            Text(
              'VoiceAttend AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
