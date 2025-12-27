import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/services/auth.service.dart';
import 'dart:developer' as developer;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: [], title: const Text('Login Zone')),
      body: Center(
        child: Card(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.album),
                title: Text('The Enchanted Nightingale'),
                subtitle: Text('Music by Julie Gable. Lyrics by Sidney Stein.'),
              ),
              SizedBox(
                width: 350,
                child: TextField(
                  controller: _usernameController,
                  obscureText: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9@._-]'),
                    ),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      return TextEditingValue(
                        text: newValue.text.toLowerCase(),
                        selection: newValue.selection,
                      );
                    }),
                  ],
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Username',
                  ),
                ),
              ),
              SizedBox(height: 15),
              SizedBox(
                width: 350,
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Password',
                  ),
                ),
              ),
              SizedBox(height: 15),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_errorMessage != null) SizedBox(height: 15),
              SizedBox(
                width: 350,
                child: FilledButton.tonal(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Colors.amber),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_usernameController.text.isEmpty ||
                              _passwordController.text.isEmpty) {
                            setState(() {
                              _errorMessage =
                                  'Please enter username and password';
                            });
                            return;
                          }

                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });

                          final navigator = Navigator.of(context);
                          try {
                            await _authService.login(
                              _usernameController.text,
                              _passwordController.text,
                            );
                            // Login successful - AuthGuard will detect auth state
                            // and navigate to HomePage automatically
                            if (!mounted) return;
                            navigator.pushReplacementNamed('/');
                          } catch (e) {
                            developer.log(
                              'Login failed',
                              name: 'LoginPage',
                              error: e,
                            );
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                                _errorMessage = e.toString().replaceAll(
                                  'Exception: ',
                                  '',
                                );
                              });
                            }
                          }
                        },
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('LOGIN'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
