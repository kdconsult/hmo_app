import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart'
    as dio_cookie_manager;
import 'package:flutter_application_1/models/user.model.dart';
import 'package:flutter_application_1/utils/hmac.util.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Service for handling authentication operations.
class AuthService {
  final FlutterSecureStorage _storage;
  final http.Client _client;
  late final Dio _dio;

  static const String _accessTokenKey = 'access_token';
  static const String _userRoleKey = 'user_role';
  static const String _userDataKey = 'user_data';

  String get _baseUrl => dotenv.env['API_BASE_URL'] ?? '';
  String get _authEndpoint => dotenv.env['API_AUTH_ENDPOINT'] ?? '/auth';

  AuthService({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _client = client ?? http.Client() {
    // Initialize Dio with cookie support (equivalent to withCredentials: true)
    _dio = Dio();
    _dio.options.baseUrl = _baseUrl;
    _dio.options.headers['Content-Type'] = 'application/json';
    // Add cookie manager to handle cookies automatically
    _dio.interceptors.add(dio_cookie_manager.CookieManager(CookieJar()));
  }

  /// Safely parses JSON from response body, returns null if not valid JSON.
  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  /// Extracts error message from response, handling both JSON and plain text.
  String _extractErrorMessage(http.Response response, String defaultMessage) {
    final errorData = _tryParseJson(response.body);
    if (errorData != null) {
      return errorData['message'] as String? ?? defaultMessage;
    }
    // If not JSON, return the body as plain text (trimmed)
    final bodyText = response.body.trim();
    return bodyText.isNotEmpty ? bodyText : defaultMessage;
  }

  /// Extracts error message from Dio response.
  String _extractDioErrorMessage(Response response, String defaultMessage) {
    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      return data['message'] as String? ?? defaultMessage;
    }
    if (response.data is String) {
      final bodyText = (response.data as String).trim();
      return bodyText.isNotEmpty ? bodyText : defaultMessage;
    }
    return defaultMessage;
  }

  /// Extracts error message from DioException.
  String _extractDioExceptionMessage(DioException e, String defaultMessage) {
    if (e.response?.data is Map<String, dynamic>) {
      final data = e.response!.data as Map<String, dynamic>;
      return data['message'] as String? ?? defaultMessage;
    }
    if (e.response?.data is String) {
      final bodyText = (e.response!.data as String).trim();
      return bodyText.isNotEmpty ? bodyText : defaultMessage;
    }
    return e.message ?? defaultMessage;
  }

  /// Gets CSRF token from the backend.
  Future<String> getCsrfToken() async {
    try {
      // Use dio to get CSRF cookie (cookies are automatically handled)
      final response = await _dio.get('$_authEndpoint/csrf-cookie');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>?;
        return data?['token'] as String? ?? '';
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
      // Step 1: Get CSRF token (cookies are automatically sent/received)
      final csrfToken = await getCsrfToken();

      // Step 2: Login with credentials (cookies are automatically sent)
      final response = await _dio.post(
        '$_authEndpoint/login',
        data: {'username': username, 'password': password},
        options: Options(headers: {'X-XSRF-Token': csrfToken}),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
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

      final errorMessage = _extractDioErrorMessage(response, 'Login failed');
      throw Exception(errorMessage);
    } on DioException catch (e) {
      final errorMessage = _extractDioExceptionMessage(e, 'Login failed');
      developer.log('Error during login', name: 'AuthService', error: e);
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
        Uri.parse('$_baseUrl/api$_authEndpoint/user'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Referer': '$_baseUrl/login',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final userResponse = AuthenticatedUserResponse.fromJson(data);

        // Validate HMAC if present to ensure data integrity
        if (userResponse.hmac != null) {
          final isValid = HmacUtil.validateHmacFromResponse(
            data,
            userResponse.user.id,
          );

          if (!isValid) {
            throw Exception(
              'HMAC validation failed - response data may have been tampered',
            );
          }
        }

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

      final errorMessage = _extractErrorMessage(
        response,
        'Failed to get user data',
      );
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
      // Use dio to send cookies automatically (withCredentials: true equivalent)
      final response = await _dio.post('$_authEndpoint/refresh');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
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
    } on DioException catch (e) {
      final errorMessage = _extractDioExceptionMessage(
        e,
        'Token refresh failed',
      );
      await logout();
      developer.log('Error refreshing token', name: 'AuthService', error: e);
      throw Exception(errorMessage);
    } catch (e, stackTrace) {
      await logout();
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
