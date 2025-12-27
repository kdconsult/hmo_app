import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_application_1/models/user.model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Service for handling authentication operations.
class AuthService {
  AuthService({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _client = client ?? http.Client();

  final FlutterSecureStorage _storage;
  final http.Client _client;

  static const String _accessTokenKey = 'access_token';
  static const String _userRoleKey = 'user_role';
  static const String _userDataKey = 'user_data';

  String get _baseUrl => dotenv.env['API_BASE_URL'] ?? '';
  String get _authEndpoint => dotenv.env['API_AUTH_ENDPOINT'] ?? '/auth';

  /// Gets CSRF token from the backend.
  Future<String> getCsrfToken() async {
    try {
      final response = await _client.get(
        Uri.parse('$_baseUrl$_authEndpoint/csrf-cookie'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['token'] as String? ?? '';
      }

      throw Exception('Failed to get CSRF token: ${response.statusCode}');
    } catch (e, stackTrace) {
      developer.log(
        'Error getting CSRF token',
        name: 'AuthService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Logs in with username and password.
  ///
  /// Returns the access token on success.
  Future<String> login(String username, String password) async {
    try {
      // Step 1: Get CSRF token
      final csrfToken = await getCsrfToken();

      // Step 2: Login with credentials
      final response = await _client.post(
        Uri.parse('$_baseUrl$_authEndpoint/login'),
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
        },
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = data['accessToken'] as String?;

        if (accessToken == null || accessToken.isEmpty) {
          throw Exception('Access token not found in response');
        }

        // Store access token
        await _storage.write(key: _accessTokenKey, value: accessToken);

        // Step 3: Get authenticated user data
        await getAuthenticatedUser();

        return accessToken;
      }

      final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
      final errorMessage = errorData?['message'] as String? ?? 'Login failed';
      throw Exception(errorMessage);
    } catch (e, stackTrace) {
      developer.log(
        'Error during login',
        name: 'AuthService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Gets authenticated user data from the backend.
  ///
  /// Stores user role and user data for later use.
  Future<AuthenticatedUserResponse> getAuthenticatedUser() async {
    try {
      final accessToken = await getAccessToken();
      if (accessToken.isEmpty) {
        throw Exception('No access token available');
      }

      final response = await _client.get(
        Uri.parse('$_baseUrl$_authEndpoint/user'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final userResponse = AuthenticatedUserResponse.fromJson(data);

        // Store user role for Hasura
        await _storage.write(key: _userRoleKey, value: userResponse.user.role);

        // Store user data as JSON
        await _storage.write(
          key: _userDataKey,
          value: jsonEncode(userResponse.user.toJson()),
        );

        return userResponse;
      }

      if (response.statusCode == 401) {
        // Token expired, try to refresh
        await refreshToken();
        // Retry the request
        return getAuthenticatedUser();
      }

      final errorData = jsonDecode(response.body) as Map<String, dynamic>?;
      final errorMessage =
          errorData?['message'] as String? ?? 'Failed to get user data';
      throw Exception(errorMessage);
    } catch (e, stackTrace) {
      developer.log(
        'Error getting authenticated user',
        name: 'AuthService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Refreshes the access token using the refresh token from HTTP-only cookie.
  Future<String> refreshToken() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl$_authEndpoint/refresh'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = data['accessToken'] as String?;

        if (accessToken == null || accessToken.isEmpty) {
          throw Exception('Access token not found in refresh response');
        }

        await _storage.write(key: _accessTokenKey, value: accessToken);
        return accessToken;
      }

      // If refresh fails, clear tokens and throw
      await logout();
      throw Exception('Token refresh failed: ${response.statusCode}');
    } catch (e, stackTrace) {
      developer.log(
        'Error refreshing token',
        name: 'AuthService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Gets the current access token.
  Future<String> getAccessToken() async {
    return await _storage.read(key: _accessTokenKey) ?? '';
  }

  /// Gets the current user role.
  Future<String?> getUserRole() async {
    return await _storage.read(key: _userRoleKey);
  }

  /// Gets the stored user data.
  Future<User?> getUserData() async {
    try {
      final userDataJson = await _storage.read(key: _userDataKey);
      if (userDataJson == null) {
        return null;
      }
      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
      return User.fromJson(userData);
    } catch (e) {
      developer.log('Error parsing user data', name: 'AuthService', error: e);
      return null;
    }
  }

  /// Checks if user is authenticated.
  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    final role = await getUserRole();
    return token.isNotEmpty && role != null && role.isNotEmpty;
  }

  /// Logs out the user by clearing all stored data.
  Future<void> logout() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _userRoleKey);
    await _storage.delete(key: _userDataKey);
  }
}
