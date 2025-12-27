import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth.service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;

/// Provider for GraphQL client with authentication and error handling.
class AppGraphQLProvider extends StatefulWidget {
  const AppGraphQLProvider({super.key, required this.child, this.authService});

  final Widget child;
  final AuthService? authService;

  @override
  State<AppGraphQLProvider> createState() => _AppGraphQLProviderState();

  /// Gets the GraphQL client from the widget tree.
  static GraphQLClient of(BuildContext context) {
    return GraphQLProvider.of(context).value;
  }
}

class _AppGraphQLProviderState extends State<AppGraphQLProvider> {
  late final AuthService _authService;
  late final ValueNotifier<GraphQLClient> _clientNotifier;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _clientNotifier = ValueNotifier(_createClient());
  }

  GraphQLClient _createClient() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    final graphqlEndpoint = dotenv.env['GRAPHQL_ENDPOINT'] ?? '/v1/graphql';

    // Create custom HTTP client that adds auth headers
    final httpClient = _AuthenticatedHttpClient(_authService);

    // Create HTTP link with custom client
    final httpLink = HttpLink(
      '$baseUrl$graphqlEndpoint',
      httpClient: httpClient,
    );

    return GraphQLClient(link: httpLink, cache: GraphQLCache());
  }

  @override
  void dispose() {
    _clientNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GraphQLProvider(client: _clientNotifier, child: widget.child);
  }
}

/// Custom HTTP client that adds authentication headers.
class _AuthenticatedHttpClient extends http.BaseClient {
  _AuthenticatedHttpClient(this._authService);

  final AuthService _authService;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Add auth headers
    final token = await _authService.getAccessToken();
    final role = await _authService.getUserRole();

    if (token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (role != null && role.isNotEmpty) {
      request.headers['x-hasura-role'] = role;
    }

    final response = await _inner.send(request);

    // Handle 401 errors
    if (response.statusCode == 401) {
      try {
        await _authService.refreshToken();
        // Retry request with new token
        final retryRequest = request as http.Request;
        final newToken = await _authService.getAccessToken();
        final newRole = await _authService.getUserRole();
        retryRequest.headers['Authorization'] = 'Bearer $newToken';
        if (newRole != null && newRole.isNotEmpty) {
          retryRequest.headers['x-hasura-role'] = newRole;
        }
        return await _inner.send(retryRequest);
      } catch (e) {
        await _authService.logout();
        rethrow;
      }
    }

    return response;
  }
}
