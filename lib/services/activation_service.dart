import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicenseStatus { locked, trial, full }

class ActivationService {
  static const MethodChannel _channel = MethodChannel('com.example.exam_secret_codes/license');
  static const String _activationKey = 'exam_secret_codes_license_token';
  static const String _trialCountKey = 'exam_secret_codes_trial_count';

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

  static Future<LicenseStatus> getLicenseStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_activationKey);
    if (token == null || token.isEmpty) return LicenseStatus.locked;
    final result = await _verify(token);
    if (result == null || result['valid'] != true) return LicenseStatus.locked;
    if (result['type'] == 'full') return LicenseStatus.full;
    if (result['type'] == 'trial') return LicenseStatus.trial;
    return LicenseStatus.locked;
  }

  static Future<int> getRemainingTrialDays() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_activationKey);
    if (token == null || token.isEmpty) return 0;
    final result = await _verify(token);
    if (result == null || result['valid'] != true || result['type'] != 'trial') return 0;
    final expiresAt = result['expiresAt'];
    if (expiresAt is! int) return 0;
    final remaining = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000).difference(DateTime.now());
    return remaining.isNegative ? 0 : (remaining.inSeconds / 86400).ceil();
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
    final token = enteredKey.trim();
    if (token.isEmpty) return LicenseStatus.locked;
    final result = await _verify(token);
    if (result == null || result['valid'] != true) return LicenseStatus.locked;
    final status = result['type'] == 'full'
        ? LicenseStatus.full
        : result['type'] == 'trial' ? LicenseStatus.trial : LicenseStatus.locked;
    if (status != LicenseStatus.locked) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activationKey, token);
    }
    return status;
  }
}
