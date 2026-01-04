import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/layouts/authenticated.layout.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthenticatedLayout(
      body: Center(
        child: Column(
          children: [
            SizedBox(width: 250, child: Image.asset('assets/home.png')),
            Text(
              'Welcome home!',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 24),
            const Expanded(child: _GraphQLQueryWidget()),
          ],
        ),
      ),
    );
  }
}

/// Widget that makes a GraphQL query and displays the result as JSON.
///
/// This is a POC widget for testing GraphQL queries.
/// Update the query and variables as needed for your use case.
class _GraphQLQueryWidget extends StatelessWidget {
  const _GraphQLQueryWidget();

  // Example query - update this with your actual GraphQL query
  static const String _query = '''
    query {
      invoices (limit: 10, order_by: {createdAt: desc}) {
        id
        num
        createdAt
        grandTotal
        partner {
          id
          company_name_i18n(args: {field: "company_name"})
        }
      }
    }
  ''';

  @override
  Widget build(BuildContext context) {
    return Query(
      options: QueryOptions(
        document: gql(_query),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
      builder:
          (QueryResult result, {VoidCallback? refetch, FetchMore? fetchMore}) {
            if (result.isLoading) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading GraphQL query...'),
                  ],
                ),
              );
            }

            if (result.hasException) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.exception.toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => refetch?.call(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Format the data as JSON
            final jsonString = const JsonEncoder.withIndent(
              '  ',
            ).convert(result.data ?? {'message': 'No data returned'});

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'GraphQL Response',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        onPressed: () => refetch?.call(),
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          jsonString,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}
