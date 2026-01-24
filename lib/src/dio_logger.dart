import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'logger.dart';

/// Cached encoder instance - reused across all requests.
const _encoder = JsonEncoder.withIndent('  ');

/// {@template dio_logger}
/// A Dio [Interceptor] which logs HTTP requests and responses.
/// PCI DSS compliant with optional sensitive data redaction.
/// {@endtemplate}
class DioLogger extends Interceptor {
  /// {@macro dio_logger}
  const DioLogger({
    this.logAuthHeader = false,
    this.logRequestHeader = true,
    this.logRequestBody = false,
    this.logResponseHeader = false,
    this.logResponseBody = true,
    this.logError = true,
    this.redact = true,
  });

  /// Whether to log the authorization header.
  final bool logAuthHeader;

  /// Whether to log request headers.
  final bool logRequestHeader;

  /// Whether to log the request body.
  final bool logRequestBody;

  /// Whether to log response headers.
  final bool logResponseHeader;

  /// Whether to log the response body.
  final bool logResponseBody;

  /// Whether to log errors.
  final bool logError;

  /// Whether to redact sensitive information from logs (PCI DSS compliant).
  /// this is to override the global redact flag in Logger
  final bool redact;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      final messages = <String>[
        '${options.method} ${options.uri}',
      ];

      if (logRequestHeader) {
        _addRequestHeaders(options, messages);
      }

      if (logRequestBody && _canLogRequestBody(options)) {
        _addRequestBody(options, messages);
      }

      if (messages.length > 1) {
        Logger.boxed(messages, tag: 'Dio | Request', redact: redact);
      }
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log request',
        error: e,
        stackTrace: stackTrace,
        tag: 'Dio | LogError',
      );
    }

    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    try {
      final messages = <String>[];

      if (logResponseHeader) {
        messages.add(
          '${response.requestOptions.method} ${response.statusCode} ${response.realUri}',
        );
        _addResponseHeaders(response, messages);
      }

      if (logResponseBody) {
        _addResponseBody(response, messages);
      }

      if (messages.isNotEmpty) {
        Logger.boxed(messages, tag: 'Dio | Response', redact: redact);
      }
    } catch (e, stackTrace) {
      Logger.e(
        'Failed to log response',
        error: e,
        stackTrace: stackTrace,
        tag: 'Dio | LogError',
      );
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (logError) {
      try {
        _logDioError(err);
      } catch (e, stackTrace) {
        Logger.e(
          'Failed to log error',
          error: e,
          stackTrace: stackTrace,
          tag: 'Dio | LogError',
        );
      }
    }

    handler.next(err);
  }

  /// Checks if request body can be logged.
  bool _canLogRequestBody(RequestOptions options) {
    return options.method != 'GET' && options.data != null;
  }

  /// Adds request headers to messages.
  void _addRequestHeaders(RequestOptions options, List<String> messages) {
    try {
      final headers = Map<String, dynamic>.from(options.headers);

      if (!logAuthHeader) {
        headers.remove(HttpHeaders.authorizationHeader);
        headers.remove('authorization');
        headers.remove('Authorization');
      }

      if (headers.isEmpty) return;

      messages.add('Headers:::\n${_encoder.convert(headers)}');
    } catch (e) {
      messages.add('Headers::: [Failed to encode]');
    }
  }

  /// Adds request body to messages.
  void _addRequestBody(RequestOptions options, List<String> messages) {
    try {
      final body = options.data;

      if (body is FormData) {
        _addFormDataBody(body, messages);
        return;
      }

      if (body is Map || body is List) {
        messages.add('Data:::\n${_encoder.convert(body)}');
        return;
      }

      if (body is String && body.isNotEmpty) {
        messages.add('Data:::\n$body');
        return;
      }

      messages.add('Data::: [${body.runtimeType}]');
    } catch (e) {
      messages.add('Data::: [Failed to encode]');
    }
  }

  /// Adds FormData body to messages.
  void _addFormDataBody(FormData formData, List<String> messages) {
    try {
      final fields = <String, dynamic>{};

      for (final field in formData.fields) {
        fields[field.key] = field.value;
      }

      for (final file in formData.files) {
        fields[file.key] = '[File: ${file.value.filename}]';
      }

      if (fields.isEmpty) return;

      messages.add('FormData:::\n${_encoder.convert(fields)}');
    } catch (e) {
      messages.add('FormData::: [Failed to encode]');
    }
  }

  /// Adds response headers to messages.
  void _addResponseHeaders(Response<dynamic> response, List<String> messages) {
    try {
      final headers = response.headers.map;
      if (headers.isEmpty) return;

      messages.add('Headers:::\n${_encoder.convert(headers)}');
    } catch (e) {
      messages.add('Headers::: [Failed to encode]');
    }
  }

  /// Adds response body to messages.
  void _addResponseBody(Response<dynamic> response, List<String> messages) {
    try {
      final body = response.data;

      if (body == null) {
        messages.add('Response::: [Empty]');
        return;
      }

      if (body is Map || body is List) {
        messages.add('Response:::\n${_encoder.convert(body)}');
        return;
      }

      if (body is Uint8List) {
        messages.add('Response:::\n${_formatBytes(body)}');
        return;
      }

      if (body is String) {
        final parsed = _tryParseJson(body);
        if (parsed is Map || parsed is List) {
          messages.add('Response:::\n${_encoder.convert(parsed)}');
        } else {
          messages.add('Response:::\n$body');
        }
        return;
      }

      messages.add('Response::: [${body.runtimeType}]');
    } catch (e) {
      messages.add('Response::: [Failed to encode]');
    }
  }

  /// Tries to parse JSON string, returns original if fails.
  dynamic _tryParseJson(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  /// Formats byte data for logging.
  String _formatBytes(Uint8List bytes) {
    if (bytes.isEmpty) return '[Empty bytes]';

    const chunkSize = 20;
    const maxChunks = 10;
    final totalChunks = (bytes.length / chunkSize).ceil();
    final chunksToShow = totalChunks > maxChunks ? maxChunks : totalChunks;

    final buffer = StringBuffer();
    buffer.writeln('[${bytes.length} bytes]');

    for (var i = 0; i < chunksToShow; i++) {
      final start = i * chunkSize;
      final end =
          (start + chunkSize > bytes.length) ? bytes.length : start + chunkSize;
      buffer.writeln(bytes.sublist(start, end).join(' '));
    }

    if (totalChunks > maxChunks) {
      buffer.writeln('... ${totalChunks - maxChunks} more chunks');
    }

    return buffer.toString().trimRight();
  }

  /// Logs DioException with details.
  void _logDioError(DioException err) {
    const tag = 'Dio | Error';
    final uri = err.requestOptions.uri;
    final method = err.requestOptions.method;

    switch (err.type) {
      case DioExceptionType.badResponse:
        _logBadResponse(err, tag);
      case DioExceptionType.connectionTimeout:
        Logger.e(
          '$method $uri\nConnection timeout',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.sendTimeout:
        Logger.e(
          '$method $uri\nSend timeout',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.receiveTimeout:
        Logger.e(
          '$method $uri\nReceive timeout',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.connectionError:
        Logger.e(
          '$method $uri\nConnection error: ${err.message}',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.cancel:
        Logger.w('$method $uri\nRequest cancelled', tag: tag, redact: redact);
      case DioExceptionType.badCertificate:
        Logger.e(
          '$method $uri\nBad certificate',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
      case DioExceptionType.unknown:
        Logger.e(
          '$method $uri\nUnknown error: ${err.message}',
          error: err.error,
          stackTrace: err.stackTrace,
          tag: tag,
          redact: redact,
        );
    }
  }

  /// Logs bad response errors (status code errors).
  void _logBadResponse(DioException err, String tag) {
    final statusCode = err.response?.statusCode ?? 'Unknown';
    final uri = err.requestOptions.uri;
    final method = err.requestOptions.method;
    final data = err.response?.data;

    final messages = <String>[
      '$method [$statusCode] $uri',
    ];

    if (data != null) {
      try {
        if (data is Map || data is List) {
          messages.add('Response:::\n${_encoder.convert(data)}');
        } else if (data is String && data.isNotEmpty) {
          messages.add('Response:::\n$data');
        }
      } catch (_) {
        messages.add('Response::: [Failed to encode]');
      }
    }

    Logger.e(
      messages.join('\n'),
      error: err.error,
      stackTrace: err.stackTrace,
      tag: tag,
      redact: redact,
    );
  }
}
