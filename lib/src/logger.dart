import 'package:ansicolor/ansicolor.dart';
import 'package:flutter/foundation.dart';
import 'package:fp_logger/src/utils/_printer.dart';
import 'package:fp_logger/src/utils/_security.dart';
import 'package:fp_logger/src/utils/_utils.dart';

/// {@template log_level}
/// The log level of a log message.
/// {@endtemplate}
enum _LogLevel {
  debug,
  info,
  warning,
  error,
  success;

  @override
  String toString() {
    return switch (this) {
      _LogLevel.debug => 'DEBUG',
      _LogLevel.info => 'INFO',
      _LogLevel.warning => 'WARNING',
      _LogLevel.error => 'ERROR',
      _LogLevel.success => 'SUCCESS',
    };
  }

  /// Returns the label associated with the log level.
  String get label => toString();

  /// Returns the ansi color associated with the log level.
  AnsiPen get color {
    return switch (this) {
      _LogLevel.debug => AnsiPen()..cyan(),
      _LogLevel.info => AnsiPen()..blue(),
      _LogLevel.warning => AnsiPen()..yellow(),
      _LogLevel.error => AnsiPen()..red(),
      _LogLevel.success => AnsiPen()..green(),
    };
  }

  /// Returns the icon associated with the log level.
  String get icon {
    return switch (this) {
      _LogLevel.debug => '🐛',
      _LogLevel.info => '💡',
      _LogLevel.warning => '⚠️',
      _LogLevel.error => '⛔',
      _LogLevel.success => '✅',
    };
  }

  /// Whether this log level can be logged in production builds.
  bool get canLogInProduction {
    return switch (this) {
      _LogLevel.error || _LogLevel.warning || _LogLevel.info => true,
      _ => false,
    };
  }
}

/// Cached redactor instance - singleton, compiled regex reused.
final _redactor = Redactor();

/// {@template logger}
/// A simple logger that logs messages to the console.
/// PCI DSS compliant with optional sensitive data redaction.
/// {@endtemplate}
abstract class Logger {
  /// {@macro logger}
  const Logger._();

  /// Global redaction flag - set to false to disable redaction globally.
  static bool globalRedact = true;

  /// Adds custom sensitive keys to the redactor.
  static void addSensitiveKeys(Iterable<String> keys) {
    _redactor.addSensitiveKeys(keys);
  }

  /// Removes keys from the sensitive set.
  static void removeSensitiveKeys(Iterable<String> keys) {
    _redactor.removeSensitiveKeys(keys);
  }

  /// Checks if a key is sensitive.
  static bool isSensitiveKey(String key) {
    return _redactor.isSensitiveKey(key);
  }

  /// Redacts sensitive data from input.
  static dynamic redactData(dynamic input) {
    return _redactor.redact(input);
  }

  /// Logs a message
  static void _log(
    _LogLevel level,
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    bool boxListItem = false,
    bool? redact,
  }) {
    // Do not log debug in release mode
    if (kReleaseMode && !level.canLogInProduction) return;

    try {
      final shouldRedact = redact ?? globalRedact;
      final redactedMessage = shouldRedact ? _redactMessage(message) : message;
      final redactedError =
          shouldRedact && error != null ? _redactError(error) : error;

      final formattedTag = tag != null ? '[$tag]' : '';
      final errorLines = redactedError?.toString().split('\n');
      final stackTraceLines = formatStackTrace(stackTrace);

      final tagLine =
          '$leftLine [${level.label} ${level.icon}] [${_formatTime(DateTime.now())}] $formattedTag';

      final messages = <String>[];

      if (redactedMessage is Iterable && boxListItem) {
        _addBoxedMessages(redactedMessage, messages);
      } else {
        messages.addAll(
          stringifyMessage(redactedMessage).map((m) => '$leftLine $m'),
        );
      }

      final outputs = <String>[
        topLine,
        tagLine,
        divider,
        ...messages,
        if (errorLines != null) ...[
          divider,
          ...errorLines.map((e) => '$leftLine $e'),
        ],
        if (stackTraceLines != null) ...[
          divider,
          ...stackTraceLines.map((line) => '$leftLine $line'),
        ],
        bottomLine,
      ];

      final coloredOutputs =
          outputs.map((m) => level.color.write(m.trim())).toList();
      outputLog(coloredOutputs);
    } catch (e, st) {
      // Fallback logging if formatting fails
      debugPrint('Logger error: $e\n$st');
      debugPrint('Original message: $message');
    }
  }

  /// Redacts sensitive data from message.
  static dynamic _redactMessage(dynamic message) {
    if (message is Map || message is List) {
      return _redactor.redact(message);
    }
    return message;
  }

  /// Redacts sensitive data from error.
  static Object _redactError(Object error) {
    if (error is Map || error is List) {
      return _redactor.redact(error);
    }
    return error;
  }

  /// Adds boxed messages to output list.
  static void _addBoxedMessages(
      Iterable<dynamic> messages, List<String> output) {
    final messageList = messages.map((e) => e.toString()).toList();

    for (var index = 0; index < messageList.length; index++) {
      final item = messageList[index];

      for (final line in item.split('\n')) {
        output.add('$leftLine $line');
      }

      if (index != messageList.length - 1) {
        output.add(divider);
      }
    }
  }

  /// Returns the current time in ISO 8601 format with 12-hour time and timezone.
  static String _formatTime(DateTime time) {
    final year = time.year;
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour24 = time.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    final offset = time.timeZoneOffset;
    final offsetSign = offset.isNegative ? '-' : '+';
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes =
        (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$year-$month-$day ${hour12.toString().padLeft(2, '0')}:$minute:$second $period $offsetSign$offsetHours:$offsetMinutes';
  }

  /// Logs a message with a box around it.
  static void boxed(
    dynamic message, {
    String? tag,
    Object? error,
    bool? redact,
  }) {
    return _log(
      error != null ? _LogLevel.error : _LogLevel.info,
      message,
      tag: tag,
      error: error,
      boxListItem: true,
      redact: redact,
    );
  }

  /// Logs a debug message.
  static void d(
    dynamic message, {
    String? tag,
    Object? error,
    bool? redact,
  }) {
    return _log(
      _LogLevel.debug,
      message,
      tag: tag,
      error: error,
      redact: redact,
    );
  }

  /// Logs an info message.
  static void i(
    dynamic message, {
    String? tag,
    Object? error,
    bool? redact,
  }) {
    return _log(
      _LogLevel.info,
      message,
      tag: tag,
      error: error,
      redact: redact,
    );
  }

  /// Logs a warning message.
  static void w(
    dynamic message, {
    String? tag,
    Object? error,
    bool? redact,
  }) {
    return _log(
      _LogLevel.warning,
      message,
      tag: tag,
      error: error,
      redact: redact,
    );
  }

  /// Logs an error message.
  static void e(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    String? tag,
    bool? redact,
  }) {
    return _log(
      _LogLevel.error,
      message,
      error: error,
      stackTrace: stackTrace,
      tag: tag,
      redact: redact,
    );
  }

  /// Logs a success message.
  static void s(
    dynamic message, {
    String? tag,
    bool? redact,
  }) {
    return _log(
      _LogLevel.success,
      message,
      tag: tag,
      redact: redact,
    );
  }

  /// Logs raw data without formatting (useful for large payloads).
  static void raw(
    dynamic message, {
    String? tag,
    bool? redact,
  }) {
    if (kReleaseMode) return;

    try {
      final shouldRedact = redact ?? globalRedact;
      final redactedMessage = shouldRedact ? _redactMessage(message) : message;
      final formattedTag = tag != null ? '[$tag] ' : '';

      debugPrint('$formattedTag$redactedMessage');
    } catch (e) {
      debugPrint('Logger raw error: $e');
    }
  }

  /// Logs a Map or List with pretty formatting.
  static void json(
    dynamic data, {
    String? tag,
    bool? redact,
  }) {
    if (kReleaseMode) return;

    if (data is! Map && data is! List) {
      i(data, tag: tag, redact: redact);
      return;
    }

    final shouldRedact = redact ?? globalRedact;
    final redactedData = shouldRedact ? _redactor.redact(data) : data;

    i(redactedData, tag: tag ?? 'JSON', redact: false);
  }
}
