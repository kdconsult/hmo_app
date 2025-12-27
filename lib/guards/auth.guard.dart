import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/home.page.dart';
import 'package:flutter_application_1/pages/login.page.dart';
import 'package:flutter_application_1/services/auth.service.dart';
import 'dart:async';

class AuthGuard extends StatefulWidget {
  const AuthGuard({super.key, required this.clientId});

  final String clientId;

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  final AuthService _authService = AuthService();
  StreamSubscription<bool>? _authSubscription;
  bool _isAuthenticated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      final isAuth = await _authService.isAuthenticated();
      if (isAuth) {
        // Verify by getting user data
        await _authService.getAuthenticatedUser();
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // Authentication failed, show login
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _isAuthenticated ? const HomePage() : const LoginPage();
  }
}
