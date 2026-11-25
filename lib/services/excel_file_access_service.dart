import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ExcelFileSelection {
  final String reference;
  final String name;

  const ExcelFileSelection({required this.reference, required this.name});
}

/// Accesses the selected workbook through its original Android document URI.
/// No duplicate workbook is created or moved.
class ExcelFileAccessService {
  static const MethodChannel _channel =
      MethodChannel('com.example.exam_secret_codes/document_pdf');

  static Future<ExcelFileSelection?> pickExcelDocument() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickExcelDocument',
    );
    if (result == null) return null;

    final uri = result['uri']?.toString();
    final name = result['name']?.toString() ?? 'workbook.xlsx';
    if (uri == null || uri.isEmpty) {
      throw Exception('لم يُرجع منتقي الملفات مرجعًا صالحًا للملف.');
    }

    final extension = name.toLowerCase().split('.').last;
    if (extension != 'xlsx' && extension != 'xlsm') {
      throw Exception('الصيغة المدعومة هي XLSX أو XLSM فقط.');
    }
    return ExcelFileSelection(reference: uri, name: name);
  }

  static bool isDocumentUri(String reference) =>
      reference.startsWith('content://');

  static Future<Uint8List> readBytes(String reference) async {
    if (isDocumentUri(reference)) {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'readExcelDocument',
        <String, dynamic>{'uri': reference},
      );
      if (bytes == null || bytes.isEmpty) {
        throw Exception('ملف Excel الأصلي فارغ أو تعذرت قراءته.');
      }
      return bytes;
    }

    final file = File(reference);
    if (!await file.exists()) {
      throw Exception('ملف Excel المحدد غير موجود أو لم يعد متاحًا.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('ملف Excel الأصلي فارغ.');
    return bytes;
  }
}
