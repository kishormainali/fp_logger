/// {@template logger_options}
/// Configuration options for logging HTTP requests and responses.
/// {@endtemplate}
class LoggerOptions {
  /// {@macro logger_options}
  const LoggerOptions({
    this.authHeader = false,
    this.requestBody = true,
    this.requestHeader = false,
    this.responseBody = true,
    this.responseHeader = false,
    this.error = true,
    this.redact = true,
  });

  /// Whether to log authentication headers.
  final bool authHeader;

  /// Whether to log request bodies.
  final bool requestBody;

  /// Whether to log request headers.
  final bool requestHeader;

  /// Whether to log response bodies.
  final bool responseBody;

  /// Whether to log response headers.
  final bool responseHeader;

  /// Whether to log errors.
  final bool error;

  /// Whether to redact sensitive information from logs.
  final bool redact;
}
