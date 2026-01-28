import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fp_logger/src/options.dart';
import 'package:gql_link/gql_link.dart';

import 'logger.dart';
import 'utils/_utils.dart';

/// Cached encoder instance - reused across all requests.
const _encoder = JsonEncoder.withIndent('  ');

/// Cached response parser - reused across all requests.
const _responseParser = ResponseParser();

/// {@template graphql_dio_logger}
/// A Dio [Interceptor] which logs GraphQL requests and responses.
/// PCI DSS compliant with optional sensitive data redaction.
/// {@endtemplate}
class GraphqlDioLogger extends Interceptor {
  /// {@macro graphql_dio_logger}
  const GraphqlDioLogger({
    this.loggerOptions = const LoggerOptions(),
  });

  /// logger options
  final LoggerOptions loggerOptions;

  bool get redact => loggerOptions.redact;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final start = DateTime.now();
      final data = options.data;
      if (data is! Map<String, dynamic>) {
        return handler.next(options);
      }

      final operationName = parseOperationNameFromRequest(data);

      final messages = <String>[
        'GraphQL Request Started -  ${options.uri} ${operationName != null ? 'With OperationName: $operationName' : ''}  @ $start',
      ];

      if (loggerOptions.requestHeader) {
        _addRequestHeaders(options, messages);
      }

      if (loggerOptions.requestBody) {
        _addRequestBody(data, messages);
      }

      if (messages.isNotEmpty) {
        Logger.boxed(messages, tag: 'GraphQL | Request', redact: redact);
      }
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log request',
        error: e,
        stackTrace: stackTrace,
        tag: 'GraphQL | LogError',
      );
    }

    options.extra['startTime'] = DateTime.now();

    return handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    try {
      final messages = <String>[];
      Object? error;

      if (loggerOptions.responseHeader) {
        _addResponseHeaders(response, messages);
      }

      if (loggerOptions.responseBody) {
        error = _addResponseBody(response, messages);
      }

      DateTime? start = response.requestOptions.extra['startTime'];
      if (start != null) {
        messages.add(
          'GraphQL Request Ended: ${response.requestOptions.uri} in ${DateTime.now().difference(start).inMilliseconds}ms',
        );
      }

      if (messages.isNotEmpty) {
        Logger.boxed(
          messages,
          tag: 'GraphQL | Response',
          error: error,
          redact: redact,
        );
      }
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log response',
        error: e,
        stackTrace: stackTrace,
        tag: 'GraphQL | LogError',
      );
    }

    return handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (loggerOptions.error) {
      try {
        _logDioError(err);
      } catch (e, stackTrace) {
        Logger.e(
          'Failed to log error',
          error: e,
          stackTrace: stackTrace,
          tag: 'GraphQL | LogError',
        );
      }
    }
    return handler.next(err);
  }

  /// Adds request headers to messages.
  void _addRequestHeaders(RequestOptions options, List<String> messages) {
    try {
      final headers = Map<String, dynamic>.from(options.headers);

      if (!loggerOptions.authHeader) {
        headers.remove(HttpHeaders.authorizationHeader);
        headers.remove('authorization');
        headers.remove('Authorization');
      }

      if (headers.isEmpty) return;

      messages.add(_encoder.convert(headers));
    } catch (e) {
      messages.add('Headers::: [Failed to encode]');
    }
  }

  /// Adds request body (query + variables) to messages.
  void _addRequestBody(Map<String, dynamic> body, List<String> messages) {
    try {
      final query = body['query'];
      if (query is String && query.isNotEmpty) {
        messages.add(query);
      }

      final variables = body['variables'];
      if (variables is Map<String, dynamic> && variables.isNotEmpty) {
        messages.add(_encoder.convert(variables));
      }
    } catch (e) {
      messages.add('Body::: [Failed to encode]');
    }
  }

  /// Adds response headers to messages.
  void _addResponseHeaders(Response<dynamic> response, List<String> messages) {
    try {
      final headers = response.headers.map;
      if (headers.isEmpty) return;

      messages.add(_encoder.convert(headers));
    } catch (e) {
      messages.add('Headers::: [Failed to encode]');
    }
  }

  /// Adds response body to messages. Returns errors if any.
  Object? _addResponseBody(Response<dynamic> response, List<String> messages) {
    Object? error;

    try {
      final body = response.data;
      if (body is! Map<String, dynamic>) return null;

      final parsedResponse = _responseParser.parseResponse(body);

      if (parsedResponse.errors != null && parsedResponse.errors!.isNotEmpty) {
        error = parsedResponse.errors;
      }

      if (parsedResponse.data != null) {
        messages.add(_encoder.convert(parsedResponse.data));
      }
    } catch (e) {
      messages.add('Data::: [Failed to encode]');
    }

    return error;
  }

  /// Logs DioException with details.
  void _logDioError(DioException err) {
    const tag = 'GraphQL | Error';
    final uri = err.requestOptions.uri;

    switch (err.type) {
      case DioExceptionType.badResponse:
        _logBadResponse(err, tag);
      case DioExceptionType.connectionTimeout:
        Logger.e(
          'Connection timeout: $uri',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.sendTimeout:
        Logger.e(
          'Send timeout: $uri',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.receiveTimeout:
        Logger.e(
          'Receive timeout: $uri',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.connectionError:
        Logger.e(
          'Connection error: ${err.message}',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.cancel:
        Logger.w('Request cancelled: $uri', tag: tag, redact: redact);
      case DioExceptionType.badCertificate:
        Logger.e(
          'Bad certificate: $uri',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.unknown:
        Logger.e(
          'Unknown error: ${err.message}',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
    }
  }

  /// Logs bad response errors (status code errors).
  void _logBadResponse(DioException err, String tag) {
    final statusCode = err.response?.statusCode;
    final data = err.response?.data;

    if (data is Map<String, dynamic>) {
      try {
        final parsedResponse = _responseParser.parseResponse(data);
        if (parsedResponse.errors != null &&
            parsedResponse.errors!.isNotEmpty) {
          final errorMessages =
              parsedResponse.errors!.map((e) => e.message).join('\n');
          Logger.e(
            'GraphQL Error [$statusCode]:\n$errorMessages',
            error: parsedResponse.errors,
            stackTrace: err.stackTrace,
            tag: tag,
            redact: redact,
          );
          return;
        }
      } catch (_) {
        // Fall through to generic error
      }
    }

    Logger.e(
      'HTTP Error [$statusCode]: ${err.message}',
      error: err.error,
      stackTrace: err.stackTrace,
      tag: tag,
      redact: redact,
    );
  }
}
