import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseStatus { locked, trial, full }

class ActivationService {
  static const MethodChannel _channel = MethodChannel('com.example.exam_secret_codes/license');
  static const String _activationKey = 'exam_secret_codes_license_token';
  static const String _trialCountKey = 'exam_secret_codes_trial_count';
  static const String _legacyTrialStartKey = 'exam_secret_codes_legacy_trial_start';

  static Future<String> getDeviceId() async {
    final id = await _channel.invokeMethod<String>('getDeviceId');
    if (id == null || id.isEmpty) throw StateError('تعذر قراءة معرّف الجهاز من Android.');
    return id;
  }

  static Future<Map<String, dynamic>?> _verify(String token) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('verifyLicense', {'token': token});
    } on PlatformException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _verifyLegacy(String key) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'verifyLegacyKey',
        {'key': key},
      );
    } on PlatformException {
      return null;
    }
  }

  static Future<LicenseStatus> getLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_activationKey);
    if (token == null || token.isEmpty) return LicenseStatus.locked;

    final result = await _verify(token);
    if (result != null && result['valid'] == true) {
      if (result['type'] == 'full') return LicenseStatus.full;
      if (result['type'] == 'trial') return LicenseStatus.trial;
    }

    // Accept original TR-/FL- keys from exam_maker_app.
    final legacy = await _verifyLegacy(token);
    if (legacy == null || legacy['valid'] != true) return LicenseStatus.locked;
    if (legacy['type'] == 'full') return LicenseStatus.full;
    if (legacy['type'] == 'trial') {
      final startMillis = prefs.getInt(_legacyTrialStartKey);
      if (startMillis == null) {
        await prefs.setInt(_legacyTrialStartKey, DateTime.now().millisecondsSinceEpoch);
        return LicenseStatus.trial;
      }
      final daysPassed = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(startMillis))
          .inDays;
      return daysPassed >= 30 ? LicenseStatus.locked : LicenseStatus.trial;
    }
    return LicenseStatus.locked;
  }

  static Future<int> getRemainingTrialDays() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_activationKey);
    if (token == null || token.isEmpty) return 0;

    final result = await _verify(token);
    if (result != null && result['valid'] == true && result['type'] == 'trial') {
      final expiresAt = result['expiresAt'];
      if (expiresAt is! int) return 0;
      final remaining = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
          .difference(DateTime.now());
      return remaining.isNegative ? 0 : (remaining.inSeconds / 86400).ceil();
    }

    final legacy = await _verifyLegacy(token);
    if (legacy == null || legacy['valid'] != true || legacy['type'] != 'trial') return 0;
    final startMillis = prefs.getInt(_legacyTrialStartKey);
    if (startMillis == null) return 30;
    final daysPassed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(startMillis))
        .inDays;
    final remaining = 30 - daysPassed;
    return remaining > 0 ? remaining : 0;
  }

  static Future<int> getTrialCreatedCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_trialCountKey) ?? 0;
  }

  static Future<void> incrementTrialCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_trialCountKey, (prefs.getInt(_trialCountKey) ?? 0) + 1);
  }

  static Future<LicenseStatus> applyKey(String enteredKey) async {
    final key = enteredKey.trim();
    if (key.isEmpty) return LicenseStatus.locked;
    final prefs = await SharedPreferences.getInstance();

    // Keep the newer RSA-signed license format supported.
    final result = await _verify(key);
    if (result != null && result['valid'] == true) {
      final status = result['type'] == 'full'
          ? LicenseStatus.full
          : result['type'] == 'trial' ? LicenseStatus.trial : LicenseStatus.locked;
      if (status != LicenseStatus.locked) {
        await prefs.setString(_activationKey, key);
        await prefs.remove(_legacyTrialStartKey);
      }
      return status;
    }

    // Backward compatibility with original TR-/FL- keys.
    final legacy = await _verifyLegacy(key);
    if (legacy == null || legacy['valid'] != true) return LicenseStatus.locked;
    final status = legacy['type'] == 'full'
        ? LicenseStatus.full
        : legacy['type'] == 'trial' ? LicenseStatus.trial : LicenseStatus.locked;
    if (status != LicenseStatus.locked) {
      await prefs.setString(_activationKey, key.toUpperCase());
      if (status == LicenseStatus.trial) {
        await prefs.setInt(_legacyTrialStartKey, DateTime.now().millisecondsSinceEpoch);
      } else {
        await prefs.remove(_legacyTrialStartKey);
      }
    }
    return status;
  }
}
