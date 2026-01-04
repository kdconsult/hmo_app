import 'package:flutter/material.dart';
import 'package:flutter_application_1/guards/auth.guard.dart';
import 'package:flutter_application_1/services/auth.service.dart';

/// Shared authenticated layout with static AppBar and dynamic body.
///
/// Similar to Angular's router-outlet pattern, this layout provides
/// a consistent structure for all authenticated pages.
///
/// Example usage:
/// ```dart
/// AuthenticatedLayout(
///   body: YourPageContent(),
/// )
/// ```
class AuthenticatedLayout extends StatefulWidget {
  const AuthenticatedLayout({
    super.key,
    required this.body,
    this.title,
    this.actions,
  });

  /// The dynamic body content (equivalent to router-outlet content).
  final Widget body;

  /// Optional title for the AppBar. If not provided, uses default.
  final String? title;

  /// Optional additional actions for the AppBar.
  final List<Widget>? actions;

  @override
  State<AuthenticatedLayout> createState() => _AuthenticatedLayoutState();
}

class _AuthenticatedLayoutState extends State<AuthenticatedLayout> {
  final AuthService _authService = AuthService();
  bool _isLoggingOut = false;

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await _authService.logout();
      if (!mounted) return;

      // Navigate back to AuthGuard, which will re-check auth state
      // and automatically show the login page
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthGuard(clientId: '')),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoggingOut = false;
      });

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to logout: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build default actions
    final defaultActions = <Widget>[
      IconButton(
        onPressed: () {},
        icon: const Icon(Icons.home),
        tooltip: 'Home',
      ),
      IconButton(
        onPressed: _isLoggingOut ? null : _handleLogout,
        icon: _isLoggingOut
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout),
        tooltip: 'Logout',
      ),
    ];

    // Merge with custom actions if provided
    final actions = widget.actions != null
        ? [...defaultActions, ...widget.actions!]
        : defaultActions;

    return Scaffold(
      appBar: AppBar(
        title: widget.title != null ? Text(widget.title!) : null,
        actions: actions,
        automaticallyImplyLeading: false,
      ),
      body: widget.body,
    );
  }
}
