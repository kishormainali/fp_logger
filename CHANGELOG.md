# Changelog

### 3.0.1 (2026-01-25)

- Export LoggerLink
- Minor fixes and improvements
- Enabled error,warning and info logs in release mode

## 3.0.0 (2026-01-24)

- Removed `_redactor` instances from `DioLogger`, `GraphqlDioLogger`, and `LoggerLink`
- All loggers now pass `redact` parameter to `Logger` methods
  `Logger` handles redaction internally via `_redactMessage()` and `_redactError()`

- **Removed `DioLoggerOptions` class** - All properties now available directly in `DioLogger` and `GraphqlDioLogger` classes

- **Disabled logging in release mode by default** - `kReleaseMode` check in `Logger._log()`

## New Features

- **LoggerLink**
  - Introduced `LoggerLink` for GraphQL logging with redaction support for non DioLink usage

- **Global redaction control**
  - `Logger.globalRedact` - Enable/disable redaction globally
  - Per-call `redact` parameter overrides global setting

- **Redaction API on Logger**
  - `Logger.addSensitiveKeys()` - Add custom sensitive keys
  - `Logger.removeSensitiveKeys()` - Remove keys from sensitive set
  - `Logger.isSensitiveKey()` - Check if a key is sensitive
  - `Logger.redactData()` - Manually redact data

- **New Logger methods**
  - `Logger.raw()` - Log without box formatting
  - `Logger.json()` - Pretty print JSON with redaction

- **All log methods support redaction**
  - `Logger.d()`, `Logger.i()`, `Logger.w()`, `Logger.e()`, `Logger.s()`
  - `Logger.boxed()` - Boxed logs with redaction

### Improvements

- **Simplified time formatting** - Changed to `yyyy-mm-dd hh:mm:ss AM/PM time zone` format
- **Better DioException handling** - Switch on `DioExceptionType` for specific error messages
- **Improved byte formatting** - Shows total byte count, limits chunks displayed
- **JSON string parsing** - Attempts to parse JSON strings in responses
- **Consistent tag format** - `Dio | Request`, `Dio | Response`, `GraphQL | Request`, etc.
- **Cleaner code** - Single responsibility, redaction centralized in `Logger`

## 2.0.0

> Breaking changes:

- removed DioLoggerOptions class and all properties are now available directly in DioLogger and GraphQLDioLogger classes
- disable logging in release mode by default
- improved logging output

## 1.0.10

## 1.0.9

## 1.0.8

- improved dio and graphql logger

## 1.0.7

## 1.0.6

## 1.0.5

- improved logging output
- added `GraphQLDioLogger`

## 1.0.4

- add support for web

## 1.0.3

- improved logging output

## 1.0.2

- improved logging output
- updated dependencies

## 1.0.1

## 1.0.0

- initial release.
