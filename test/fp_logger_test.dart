import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:fp_logger/fp_logger.dart';
import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart' as gql;
import 'package:gql_link/gql_link.dart';

class _TestErrorHandler extends dio.ErrorInterceptorHandler {
  dio.DioException? receivedError;

  @override
  void next(dio.DioException err) {
    receivedError = err;
  }
}

class _TestRequestHandler extends dio.RequestInterceptorHandler {
  dio.RequestOptions? receivedOptions;

  @override
  void next(dio.RequestOptions requestOptions) {
    receivedOptions = requestOptions;
  }
}

class _TestResponseHandler extends dio.ResponseInterceptorHandler {
  dio.Response<dynamic>? receivedResponse;

  @override
  void next(dio.Response<dynamic> response) {
    receivedResponse = response;
  }
}

void main() {
  group('LoggerOptions', () {
    test('default options are correctly configured', () {
      const options = LoggerOptions();
      expect(options.authHeader, isFalse);
      expect(options.requestBody, isTrue);
      expect(options.requestHeader, isFalse);
      expect(options.responseBody, isTrue);
      expect(options.responseHeader, isFalse);
      expect(options.error, isTrue);
      expect(options.redact, isTrue);
    });

    test('custom options are respected', () {
      const options = LoggerOptions(
        authHeader: true,
        requestBody: false,
        requestHeader: true,
        responseBody: false,
        responseHeader: true,
        error: false,
        redact: false,
      );
      expect(options.authHeader, isTrue);
      expect(options.requestBody, isFalse);
      expect(options.requestHeader, isTrue);
      expect(options.responseBody, isFalse);
      expect(options.responseHeader, isTrue);
      expect(options.error, isFalse);
      expect(options.redact, isFalse);
    });
  });

  group('Logger Redaction and Logging Methods', () {
    setUp(() {
      Logger.globalRedact = true;
    });

    test('isSensitiveKey detects default sensitive keys', () {
      expect(Logger.isSensitiveKey('password'), isTrue);
      expect(Logger.isSensitiveKey('authorization'), isTrue);
      expect(Logger.isSensitiveKey('accessToken'), isTrue);
      expect(Logger.isSensitiveKey('secret'), isTrue);
      expect(Logger.isSensitiveKey('username'), isFalse);
    });

    test('addSensitiveKeys and removeSensitiveKeys work as expected', () {
      Logger.addSensitiveKeys(['custom_token', 'apiKey']);
      expect(Logger.isSensitiveKey('custom_token'), isTrue);
      expect(Logger.isSensitiveKey('apiKey'), isTrue);

      Logger.removeSensitiveKeys(['custom_token']);
      expect(Logger.isSensitiveKey('custom_token'), isFalse);
    });

    test('redactData redacts sensitive values in map', () {
      final input = {
        'username': 'john_doe',
        'password': 'secret_password_123',
        'card': '1234567812345678',
        'nested': {
          'secret': 'nested_secret_value',
          'public_info': 'visible',
        },
      };

      final redacted = Logger.redactData(input) as Map;
      expect(redacted['username'], equals('john_doe'));
      expect(redacted['password'], equals('***[REDACTED]***'));
      expect(redacted['card'], equals('****-****-****-5678'));
      expect((redacted['nested'] as Map)['secret'], equals('***[REDACTED]***'));
      expect((redacted['nested'] as Map)['public_info'], equals('visible'));
    });

    test('redactData redacts sensitive values in list', () {
      final input = [
        {'password': 'secret_password'},
        {'pin': '1234'},
      ];

      final redacted = Logger.redactData(input) as List;
      expect((redacted[0] as Map)['password'], equals('***[REDACTED]***'));
      expect((redacted[1] as Map)['pin'], isNull);
    });

    test('Logger methods run without exceptions', () {
      expect(() => Logger.d('Debug message'), returnsNormally);
      expect(() => Logger.i('Info message'), returnsNormally);
      expect(() => Logger.w('Warning message'), returnsNormally);
      expect(
        () => Logger.e('Error message',
            error: Exception('test error'), stackTrace: StackTrace.current),
        returnsNormally,
      );
      expect(() => Logger.s('Success message'), returnsNormally);
      expect(() => Logger.boxed(['Line 1', 'Line 2']), returnsNormally);
      expect(() => Logger.raw('Raw message'), returnsNormally);
      expect(() => Logger.json({'key': 'value', 'password': '123'}),
          returnsNormally);
      expect(() => Logger.json('not a json object'), returnsNormally);
    });
  });

  group('DioLogger', () {
    test('DioLogger handles all DioExceptionType cases including transformTimeout',
        () {
      const logger = DioLogger();
      final requestOptions = dio.RequestOptions(
        path: '/test',
        baseUrl: 'https://api.example.com',
        method: 'POST',
        headers: {'Authorization': 'Bearer secret_token', 'Accept': 'application/json'},
        data: {'password': '123', 'query': 'data'},
        extra: {'startTime': DateTime.now().subtract(const Duration(milliseconds: 100))},
      );

      for (final type in dio.DioExceptionType.values) {
        final exception = dio.DioException(
          requestOptions: requestOptions,
          type: type,
          message: 'Error for type $type',
          response: dio.Response(
            requestOptions: requestOptions,
            statusCode: 500,
            data: {'error': 'Internal server error'},
          ),
        );

        final handler = _TestErrorHandler();
        logger.onError(exception, handler);
        expect(handler.receivedError, equals(exception));
      }
    });

    test('DioLogger handles onRequest and onResponse', () {
      const logger = DioLogger(
        loggerOptions: LoggerOptions(
          requestHeader: true,
          requestBody: true,
          responseHeader: true,
          responseBody: true,
        ),
      );
      final requestOptions = dio.RequestOptions(
        path: '/test',
        baseUrl: 'https://api.example.com',
        method: 'GET',
        headers: {'Custom-Header': 'value'},
        data: {'foo': 'bar'},
      );

      final reqHandler = _TestRequestHandler();
      logger.onRequest(requestOptions, reqHandler);
      expect(reqHandler.receivedOptions, equals(requestOptions));

      final resHandler = _TestResponseHandler();
      final response = dio.Response(
        requestOptions: requestOptions,
        statusCode: 200,
        data: {'success': true},
      );
      logger.onResponse(response, resHandler);
      expect(resHandler.receivedResponse, equals(response));
    });
  });

  group('GraphqlDioLogger', () {
    test('GraphqlDioLogger handles all DioExceptionType cases including transformTimeout',
        () {
      const logger = GraphqlDioLogger();
      final requestOptions = dio.RequestOptions(
        path: '/graphql',
        baseUrl: 'https://api.example.com',
        method: 'POST',
        data: {
          'query': 'query GetUser { user { id name } }',
          'operationName': 'GetUser',
          'variables': {'id': '123'},
        },
      );

      for (final type in dio.DioExceptionType.values) {
        final exception = dio.DioException(
          requestOptions: requestOptions,
          type: type,
          message: 'Error for type $type',
          response: dio.Response(
            requestOptions: requestOptions,
            statusCode: 400,
            data: {'errors': [{'message': 'GraphQL syntax error'}]},
          ),
        );

        final handler = _TestErrorHandler();
        logger.onError(exception, handler);
        expect(handler.receivedError, equals(exception));
      }
    });

    test('GraphqlDioLogger handles onRequest and onResponse', () {
      const logger = GraphqlDioLogger(
        loggerOptions: LoggerOptions(
          requestHeader: true,
          requestBody: true,
          responseHeader: true,
          responseBody: true,
        ),
      );
      final requestOptions = dio.RequestOptions(
        path: '/graphql',
        baseUrl: 'https://api.example.com',
        method: 'POST',
        data: {
          'query': 'query GetUser { user { id name } }',
          'operationName': 'GetUser',
          'variables': {'id': '123'},
        },
      );

      final reqHandler = _TestRequestHandler();
      logger.onRequest(requestOptions, reqHandler);
      expect(reqHandler.receivedOptions, equals(requestOptions));

      final resHandler = _TestResponseHandler();
      final response = dio.Response(
        requestOptions: requestOptions,
        statusCode: 200,
        data: {
          'data': {
            'user': {'id': '123', 'name': 'Alice'}
          }
        },
      );
      logger.onResponse(response, resHandler);
      expect(resHandler.receivedResponse, equals(response));
    });
  });

  group('LoggerLink', () {
    test('logs GraphQL requests and responses through link stream', () async {
      const link = LoggerLink(
        options: LoggerOptions(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
        ),
      );

      final document = parseString('query GetUser { user { id } }');
      final request = gql.Request(
        operation: gql.Operation(document: document, operationName: 'GetUser'),
        variables: const {'id': '1'},
      );

      final forwardLink = Link.function((req, [forward]) {
        return Stream.value(
          const gql.Response(
            data: {
              'user': {'id': '1'}
            },
            response: {
              'data': {
                'user': {'id': '1'}
              }
            },
          ),
        );
      });

      final stream = link.request(request, forwardLink.request);
      final responses = await stream.toList();

      expect(responses.length, equals(1));
      expect(responses.first.data?['user']?['id'], equals('1'));
    });

    test('handles GraphQL error responses in link stream', () async {
      const link = LoggerLink();
      final document = parseString('query Fail { fail }');
      final request = gql.Request(
        operation: gql.Operation(document: document, operationName: 'Fail'),
      );

      final forwardLink = Link.function((req, [forward]) {
        return Stream.value(
          const gql.Response(
            errors: [
              gql.GraphQLError(message: 'Something went wrong'),
            ],
            response: {
              'errors': [
                {'message': 'Something went wrong'}
              ]
            },
          ),
        );
      });

      final stream = link.request(request, forwardLink.request);
      final responses = await stream.toList();

      expect(responses.length, equals(1));
      expect(responses.first.errors?.first.message, equals('Something went wrong'));
    });
  });
}
