// cspell:disable

/// PCI DSS compliant sensitive data redactor.
/// Singleton pattern for performance - regex compiled once, reused.
class Redactor {
  Redactor._();

  static final Redactor _instance = Redactor._();

  /// Returns the singleton instance of [Redactor].
  factory Redactor() => _instance;

  /// Sensitive keys that should be redacted from logs.
  /// PCI DSS compliant - includes payment card industry sensitive fields.
  final Set<String> sensitiveKeys = {
    // Authentication & Tokens
    'password',
    'pass',
    'pwd',
    'passwd',
    'secret',
    'clientsecret',
    'apikey',
    'accesstoken',
    'refreshtoken',
    'auth',
    'authorization',
    'bearer',
    'jwt',
    'idtoken',
    'privatekey',
    'publickey',
    'session',
    'sessionid',
    'sessiontoken',
    'csrf',
    'xsrf',
    'otp',
    'pin',
    'totp',
    'mfa',
    'credential',
    'credentials',
    'access_token',
    'refresh_token',
    'x-access-token',
    'x-refresh-token',

    // Card & Payment (PCI DSS)
    'card',
    'cardnumber',
    'cardno',
    'pan',
    'cvv',
    'cvc',
    'cvv2',
    'cvc2',
    'securitycode',
    'expiry',
    'expmonth',
    'expyear',
    'expdate',
    'expirationdate',
    'billingaddress',
    'paymentmethod',
    'bankaccount',
    'accountnumber',
    'accountno',
    'routingnumber',
    'iban',
    'swift',
    'bic',
    'upi',
    'vpa',
    'ach',
    'sortcode',

    // Payment Providers
    'stripekey',
    'stripesecret',
    'paypal',
    'razorpay',
    'braintree',
    'encryptionkey',
    'merchantid',
    'merchantkey',

    // PII (Personally Identifiable Information)
    'ssn',
    'socialsecurity',
    'taxid',
    'dob',
    'dateofbirth',
    'driverslicense',
    'passport',
    'nationalid',
  };

  /// Fields where last 4 digits should be shown (PCI DSS compliant).
  static const Set<String> _last4Fields = {
    'pan',
    'card',
    'cardnumber',
    'cardno',
    'accountnumber',
    'accountno',
    'bankaccount',
  };

  /// Fields that must be completely removed (PCI DSS requirement).
  static const Set<String> _removeFields = {
    'cvv',
    'cvc',
    'cvv2',
    'cvc2',
    'securitycode',
    'pin',
  };

  /// Cached regex for key normalization.
  static final RegExp _normalizeRegex = RegExp(r'[_\-\s.]');

  /// Cached regex for extracting digits.
  static final RegExp _digitsRegex = RegExp(r'\D');

  /// Default replacement string.
  static const String defaultReplacement = '***[REDACTED]***';

  /// Default maximum recursion depth.
  static const int defaultMaxDepth = 15;

  /// Normalize a key by converting to lowercase and removing
  /// underscores, hyphens, spaces, and dots.
  String normalizeKey(String key) {
    return key.toLowerCase().replaceAll(_normalizeRegex, '');
  }

  /// Checks if the key is a sensitive field.
  bool isSensitiveKey(String key) {
    return sensitiveKeys.contains(normalizeKey(key));
  }

  /// Adds custom sensitive keys to the set.
  void addSensitiveKeys(Iterable<String> keys) {
    sensitiveKeys.addAll(keys.map(normalizeKey));
  }

  /// Removes keys from the sensitive set.
  void removeSensitiveKeys(Iterable<String> keys) {
    for (final key in keys) {
      sensitiveKeys.remove(normalizeKey(key));
    }
  }

  /// Redact sensitive information from input.
  /// PCI DSS compliant with proper masking strategies.
  dynamic redact(
    dynamic input, {
    String replacement = defaultReplacement,
    int depth = 0,
    int maxDepth = defaultMaxDepth,
  }) {
    if (depth > maxDepth) return input;

    if (input is Map) {
      return _redactMap(input, replacement, depth, maxDepth);
    }

    if (input is List) {
      return _redactList(input, replacement, depth, maxDepth);
    }

    return input;
  }

  /// Redacts sensitive fields from a Map.
  Map<dynamic, dynamic> _redactMap(
    Map<dynamic, dynamic> input,
    String replacement,
    int depth,
    int maxDepth,
  ) {
    return input.map((key, value) {
      final normalized = normalizeKey(key.toString());

      if (sensitiveKeys.contains(normalized)) {
        return MapEntry(key, _maskValue(normalized, value, replacement));
      }

      return MapEntry(
        key,
        redact(value,
            replacement: replacement, depth: depth + 1, maxDepth: maxDepth),
      );
    });
  }

  /// Redacts sensitive fields from a List.
  List<dynamic> _redactList(
    List<dynamic> input,
    String replacement,
    int depth,
    int maxDepth,
  ) {
    return input
        .map((e) => redact(e,
            replacement: replacement, depth: depth + 1, maxDepth: maxDepth))
        .toList();
  }

  /// Masks value based on field type (PCI DSS compliant).
  dynamic _maskValue(String normalized, dynamic value, String replacement) {
    // PCI DSS: CVV/PIN must never exist in logs
    if (_removeFields.contains(normalized)) {
      return null;
    }

    // PCI DSS: Show last 4 digits for card/account numbers
    if (_last4Fields.contains(normalized) && value is String) {
      return _maskWithLast4(value);
    }

    // Email: show domain only
    if (value is String && _isEmail(value)) {
      return _maskEmail(value);
    }

    return replacement;
  }

  /// Masks value showing only last 4 digits.
  String _maskWithLast4(String value) {
    final digits = value.replaceAll(_digitsRegex, '');
    if (digits.length >= 4) {
      return '****-****-****-${digits.substring(digits.length - 4)}';
    }
    return defaultReplacement;
  }

  /// Checks if the value is an email.
  bool _isEmail(String value) {
    return value.contains('@') && value.contains('.');
  }

  /// Masks email showing only domain.
  String _maskEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex != -1 && atIndex < email.length - 1) {
      return '***@${email.substring(atIndex + 1)}';
    }
    return defaultReplacement;
  }
}

// cspell:enable
