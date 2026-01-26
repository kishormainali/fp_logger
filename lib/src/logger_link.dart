import 'dart:convert';
import 'dart:io';

import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';

import 'logger.dart';

/// Cached encoder instance - reused across all requests.
const _encoder = JsonEncoder.withIndent('  ');

/// {@template logger_link}
/// A [Link] which logs the request and response for graphql requests.
/// {@endtemplate}
class LoggerLink extends Link {
  /// {@macro logger_link}
  const LoggerLink({
    this.authHeader = false,
    this.requestHeader = true,
    this.requestBody = false,
    this.responseHeader = false,
    this.responseBody = true,
    this.error = true,
    this.redact = true,
  });

  /// Whether to log the authorization header.
  final bool authHeader;

  /// Whether to log request headers.
  final bool requestHeader;

  /// Whether to log the request body.
  final bool requestBody;

  /// Whether to log response headers.
  final bool responseHeader;

  /// Whether to log the response body.
  final bool responseBody;

  /// Whether to log errors.
  final bool error;

  /// Whether to redact sensitive information from logs.
  /// This is to override the global redact flag in Logger
  final bool redact;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    assert(forward != null, 'LoggerLink must be followed by another link.');

    final operationName = request.operation.operationName ?? 'Unknown';
    final start = DateTime.now();

    // Log request
    _logRequest(request, operationName, start);

    try {
      await for (final response in forward!(request)) {
        final duration = DateTime.now().difference(start);

        // Handle GraphQL errors
        if (response.errors != null && response.errors!.isNotEmpty) {
          _logGraphQLError(response, operationName, duration);
          yield response;
          continue;
        }

        // Log success response
        _logResponse(response, operationName, duration);
        yield response;
      }
    } on LinkException catch (e, stackTrace) {
      final duration = DateTime.now().difference(start);
      _logLinkException(e, operationName, duration, stackTrace);
      rethrow;
    } on FormatException catch (e, stackTrace) {
      final duration = DateTime.now().difference(start);
      _logException('FormatException', e, operationName, duration, stackTrace);
      rethrow;
    } on JsonUnsupportedObjectError catch (e, stackTrace) {
      final duration = DateTime.now().difference(start);
      _logException('JsonError', e, operationName, duration, stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      final duration = DateTime.now().difference(start);
      _logException('Exception', e, operationName, duration, stackTrace);
      rethrow;
    }
  }

  /// Logs request details.
  void _logRequest(Request request, String operationName, DateTime start) {
    try {
      final messages = <String>[
        'GraphQL Request: $operationName @ ${start.toIso8601String()}',
      ];

      _addHeadersToMessages(request, messages);
      _addVariablesToMessages(request, messages);

      Logger.boxed(messages, tag: 'LoggerLink | Request', redact: redact);
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log request: $operationName',
        error: e,
        stackTrace: stackTrace,
        tag: 'LoggerLink | LogError',
      );
    }
  }

  /// Adds headers to log messages if available.
  void _addHeadersToMessages(Request request, List<String> messages) {
    try {
      final headers = request.context.entry<HttpLinkHeaders>()?.headers;
      if (headers != null && headers.isNotEmpty) {
        if (!authHeader) {
          headers.remove(HttpHeaders.authorizationHeader);
          headers.remove('Authorization');
          headers.remove('authorization');
        }
        messages.add(_encoder.convert(headers));
      }
    } catch (e) {
      messages.add('Headers::: [Failed to encode]');
    }
  }

  /// Adds variables to log messages if available.
  void _addVariablesToMessages(Request request, List<String> messages) {
    try {
      final variables = request.variables;
      if (variables.isNotEmpty && requestBody) {
        messages.add(_encoder.convert(variables));
      }
    } catch (e) {
      messages.add('Variables::: [Failed to encode]');
    }
  }

  /// Logs response details.
  void _logResponse(
      Response response, String operationName, Duration duration) {
    try {
      final messages = <String>[
        'GraphQL Response: $operationName in ${duration.inMilliseconds}ms',
      ];
      if (responseHeader) {
        _addResponseHeaders(response, messages);
      }

      if (responseBody && response.data != null) {
        try {
          messages.add(_encoder.convert(response.data));
        } catch (e) {
          messages.add('Data::: [Failed to encode]');
        }
      }
      Logger.boxed(messages, tag: 'LoggerLink | Response', redact: redact);
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log response: $operationName',
        error: e,
        stackTrace: stackTrace,
        tag: 'LoggerLink | LogError',
      );
    }
  }

  /// Adds response headers to log messages if available.
  void _addResponseHeaders(Response response, List<String> messages) {
    try {
      final headers =
          response.context.entry<HttpLinkResponseContext>()?.headers;
      if (headers != null && headers.isNotEmpty) {
        messages.add(_encoder.convert(headers));
      }
    } catch (e) {
      messages.add('Response Headers::: [Failed to encode]');
    }
  }

  /// Logs GraphQL errors from response.
  void _logGraphQLError(
      Response response, String operationName, Duration duration) {
    try {
      final errors = response.errors!;

      final messages = <String>[
        'GraphQL Response: $operationName in ${duration.inMilliseconds}ms with errors'
      ];

      if (error) {
        try {
          final errorData = errors
              .map((e) => {
                    'message': e.message,
                    'locations': e.locations
                        ?.map((l) => {'line': l.line, 'column': l.column})
                        .toList(),
                    'path': e.path,
                    'extensions': e.extensions,
                  })
              .toList();
          messages.add(_encoder.convert(errorData));
        } catch (e) {
          messages.add('Error Details::: [Failed to encode]');
        }

        // Include partial data if available
        if (response.data != null) {
          try {
            messages.add(_encoder.convert(response.data));
          } catch (e) {
            messages.add('Partial Data::: [Failed to encode]');
          }
        }
      }

      Logger.e(
        messages.join('\n'),
        error: errors.first,
        stackTrace: StackTrace.current,
        tag: 'LoggerLink | GraphQL Error',
        redact: redact,
      );
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log GraphQL error: $operationName',
        error: e,
        stackTrace: stackTrace,
        tag: 'LoggerLink | LogError',
      );
    }
  }

  /// Logs LinkException with details.
  void _logLinkException(
    LinkException exception,
    String operationName,
    Duration duration,
    StackTrace stackTrace,
  ) {
    try {
      final messages = <String>[
        'GraphQL Link Error: $operationName in ${duration.inMilliseconds}ms with exception ${exception.runtimeType}',
      ];

      if (exception is ServerException) {
        if (error && exception.parsedResponse != null) {
          try {
            messages.add(_encoder.convert(exception.parsedResponse!.data));
          } catch (e) {
            messages.add('Parsed Response::: [Failed to encode]');
          }
        }
      }

      Logger.e(
        messages.join('\n'),
        error: exception,
        stackTrace: stackTrace,
        tag: 'LoggerLink | Link Error',
        redact: redact,
      );
    } catch (e, st) {
      Logger.e(
        'Failed to log link exception: $operationName',
        error: e,
        stackTrace: st,
        tag: 'LoggerLink | LogError',
      );
    }
  }

  /// Logs generic exceptions.
  void _logException(
    String type,
    Object exception,
    String operationName,
    Duration duration,
    StackTrace stackTrace,
  ) {
    try {
      Logger.e(
        'GraphQL $type: $operationName in ${duration.inMilliseconds}ms with exception: ${exception.runtimeType}',
        error: exception,
        stackTrace: stackTrace,
        tag: 'LoggerLink | $type',
        redact: redact,
      );
    } catch (e, st) {
      Logger.e(
        'Failed to log exception: $operationName',
        error: e,
        stackTrace: st,
        tag: 'LoggerLink | LogError',
      );
    }
  }
}
