import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';

/// Utility class for HMAC calculation and validation.
class HmacUtil {
  HmacUtil._();

  /// Calculates HMAC-SHA256 of the provided data using the user ID as key.
  ///
  /// This matches the backend implementation which uses `${userId}${currentDate}`
  /// as the secret key, where currentDate is in YYYY-MM-DD format.
  ///
  /// [data] can be a String, Map, or any object that can be converted to JSON.
  /// [userId] is the user ID used to construct the secret key.
  ///
  /// Returns the HMAC as a hexadecimal string.
  ///
  /// Example:
  /// ```dart
  /// final hmac = HmacUtil.calculateHmac(responseData, userId);
  /// ```
  static String calculateHmac(dynamic data, String userId) {
    try {
      // Get current date in YYYY-MM-DD format (matches backend)
      final now = DateTime.now().toUtc();
      final dateString =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Construct the key as `${userId}${currentDate}` (matches backend)
      final secret = '$userId$dateString';

      // Convert data to string representation (matches backend JSON.stringify)
      String dataString;
      if (data is String) {
        dataString = data;
      } else {
        // Use regular jsonEncode to match JavaScript's JSON.stringify behavior
        // (maintains insertion order, doesn't sort keys)
        dataString = jsonEncode(data);
      }

      // Convert secret and data to bytes
      final keyBytes = utf8.encode(secret);
      final dataBytes = utf8.encode(dataString);

      // Create HMAC object using SHA-256
      final hmac = Hmac(sha256, keyBytes);

      // Compute the HMAC digest
      final digest = hmac.convert(dataBytes);

      // Return the HMAC as a hexadecimal string
      return digest.toString();
    } catch (e, stackTrace) {
      developer.log(
        'Error calculating HMAC',
        name: 'HmacUtil',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Validates HMAC by comparing the calculated HMAC with the provided HMAC.
  ///
  /// [data] is the data to validate (should exclude the 'hmac' field).
  /// [userId] is the user ID used to construct the secret key.
  /// [providedHmac] is the HMAC value to compare against.
  ///
  /// Returns true if the HMACs match, false otherwise.
  ///
  /// Example:
  /// ```dart
  /// final isValid = HmacUtil.validateHmac(
  ///   responseData,
  ///   userId,
  ///   responseHmac,
  /// );
  /// ```
  static bool validateHmac(dynamic data, String userId, String providedHmac) {
    try {
      final calculatedHmac = calculateHmac(data, userId);
      // Use constant-time comparison to prevent timing attacks
      return _constantTimeEquals(calculatedHmac, providedHmac);
    } catch (e) {
      developer.log('Error validating HMAC', name: 'HmacUtil', error: e);
      return false;
    }
  }

  /// Validates HMAC from a response map that contains an 'hmac' field.
  ///
  /// This is a convenience method that automatically excludes the 'hmac' field
  /// from the data before validation.
  ///
  /// [responseData] is the full response data map that includes the 'hmac' field.
  /// [userId] is the user ID used to construct the secret key.
  ///
  /// Returns true if the HMACs match, false otherwise.
  /// Returns false if the 'hmac' field is missing from the response.
  ///
  /// Example:
  /// ```dart
  /// final isValid = HmacUtil.validateHmacFromResponse(
  ///   responseData,
  ///   userId,
  /// );
  /// ```
  static bool validateHmacFromResponse(
    Map<String, dynamic> responseData,
    String userId,
  ) {
    try {
      final providedHmac = responseData['hmac'] as String?;
      if (providedHmac == null || providedHmac.isEmpty) {
        developer.log('HMAC field missing from response', name: 'HmacUtil');
        return false;
      }

      // Create a copy of the data without the 'hmac' field
      final dataWithoutHmac = Map<String, dynamic>.from(responseData);
      dataWithoutHmac.remove('hmac');

      return validateHmac(dataWithoutHmac, userId, providedHmac);
    } catch (e) {
      developer.log(
        'Error validating HMAC from response',
        name: 'HmacUtil',
        error: e,
      );
      return false;
    }
  }

  /// Constant-time string comparison to prevent timing attacks.
  ///
  /// Compares two strings in constant time, which prevents attackers from
  /// using timing differences to guess the correct HMAC.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }

    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
