import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

class StudentData {
  final String seatNo;
  final String name;
  final String grade;
  final String secretCode;

  StudentData({
    required this.seatNo,
    required this.name,
    this.grade = '',
    required this.secretCode,
  });
}

class StudentExcelResult {
  final List<StudentData> students;
  final int subjectCode;
  final String matchedSubjectName;
  final int totalMonths;

  StudentExcelResult({
    required this.students,
    required this.subjectCode,
    required this.matchedSubjectName,
    this.totalMonths = 8,
  });
}

class StudentExcelService {
  /// إصلاح أبعاد ملف الإكسيل المخزنة بشكل خاطئ
  static Uint8List _fixExcelDimensions(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (final file in archive) {
        if (file.isFile && file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml')) {
          final contentBytes = file.content as List<int>;
          String content = utf8.decode(contentBytes);
          
          if (content.contains('<dimension')) {
            content = content.replaceAll(RegExp(r'<dimension[^>]*>'), '<dimension ref="A1:Z10000"/>');
          }
          
          final newFile = ArchiveFile(file.name, content.length, utf8.encode(content));
          newArchive.addFile(newFile);
        } else {
          newArchive.addFile(file);
        }
      }

      final zipEncoder = ZipEncoder();
      final encoded = zipEncoder.encode(newArchive); 
      
      if (encoded != null) {
        return Uint8List.fromList(encoded);
      }
      return bytes;
    } catch (e) {
      return bytes; 
    }
  }

  /// استخراج النص النقي الخام
  static String _extractCleanText(dynamic cell) {
    if (cell == null) return '';
    final val = (cell is Data) ? cell.value : cell;
    if (val == null) return '';

    String text;
    if (val is TextCellValue) {
      text = val.value.text ?? '';
    } else if (val is IntCellValue) {
      text = val.value.toString();
    } else if (val is DoubleCellValue) {
      text = val.value.toInt().toString();
    } else {
      text = val.toString();
    }

    if (text.startsWith('TextCellValue(') && text.endsWith(')')) {
      text = text.substring(14, text.length - 1);
    }

    // إزالة المسافات الخفية وعلامات الاتجاه
    return text.replaceAll(RegExp(r'[\u200B-\u200F\u061C\uFEFF\u00A0\u00AD]'), '').trim();
  }

  /// تطبيع الحروف
  static String _normalizeArabic(String text) {
    var s = _extractCleanText(text).toLowerCase();
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[\u064B-\u0652]'), ''); // إزالة التشكيل
    s = s.replaceAll('\u0640', ''); // إزالة التطويل (الكشيدة)
    s = s.replaceAll('الصف', '').replaceAll('اساسي', '').replaceAll('الاساسي', '').trim();
    s = s.replaceAll(RegExp(r'\s+'), ''); // إزالة كل المسافات
    return s;
  }

  /// ✅ التعديل الجذري: التطابق التام المباشر فقط
  static bool _isGradeMatch(String studentGradeCell, String targetGrade) {
    final normCell = _normalizeArabic(studentGradeCell);
    final normTarget = _normalizeArabic(targetGrade);

    if (normTarget.isEmpty) return true;
    if (normCell.isEmpty) return false;

    // 1. التطابق التام المباشر (تاسع == تاسع)
    if (normCell == normTarget) return true;

    // 2. التطابق بعد إزالة "ال" التعريف (تاسع == التاسع)
    final cellClean = normCell.replaceFirst(RegExp(r'^ال'), '');
    final targetClean = normTarget.replaceFirst(RegExp(r'^ال'), '');
    if (cellClean == targetClean) return true;

    // 3. مطابقة الأرقام (9 == تاسع)
    final Map<String, List<String>> map = {
      'اول': ['1', '١'],
      'ثاني': ['2', '٢'],
      'ثالث': ['3', '٣'],
      'رابع': ['4', '٤'],
      'خامس': ['5', '٥'],
      'سادس': ['6', '٦'],
      'سابع': ['7', '٧'],
      'ثامن': ['8', '٨'],
      'تاسع': ['9', '٩'],
    };

    for (final entry in map.entries) {
      if (cellClean == entry.key || entry.value.contains(cellClean)) {
        if (targetClean == entry.key || entry.value.contains(targetClean)) {
          return true;
        }
      }
    }

    return false;
  }
  static bool _isTermTotalHeader(String value) {
    final normalized = _normalizeArabic(value);
    return normalized == 'م1' || normalized == 'م2' ||
        normalized == 'م١' || normalized == 'م٢' ||
        normalized == 'm1' || normalized == 'm2';
  }

  static List<String> extractMonthsFromSheet(Sheet sheet, {int? totalMonths}) {
    final months = <String>[];
    final seen = <String>{};
    // قراءة عناوين الصف الثاني فعلياً بدءاً من العمود E.
    for (int column = 4; column < sheet.maxColumns; column++) {
      final name = _extractCleanText(sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 1),
      ));
      if (name.isEmpty || _isTermTotalHeader(name)) continue;
      final key = _normalizeArabic(name);
      if (key.isEmpty || !seen.add(key)) continue;
      months.add(name);
    }
    return months;
  }

  static int detectTotalMonths(Sheet sheet) => extractMonthsFromSheet(sheet).length;

  static Future<Excel> _loadExcelFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return Excel.decodeBytes(_fixExcelDimensions(bytes));
  }

  static Future<List<String>> getSubjectSheetNames(String filePath) async {
    final excel = await _loadExcelFile(filePath);
    return excel.tables.entries
        .where((entry) => _isSubjectSheet(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  static Future<List<String>> getGrades(String filePath, String sheetName) async {
    final excel = await _loadExcelFile(filePath);
    final sheet = excel.tables[sheetName];
    if (sheet == null) throw Exception('ورقة المادة المحددة غير موجودة في ملف Excel.');
    final grades = <String>[];
    final seen = <String>{};
    for (int row = 3; row < sheet.maxRows; row++) {
      final grade = _extractCleanText(sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row),
      ));
      final key = _normalizeArabic(grade);
      if (grade.isEmpty || key.isEmpty || !seen.add(key)) continue;
      grades.add(grade);
    }
    return grades;
  }

  static Future<List<String>> getPeriods(String filePath, String sheetName) async {
    final excel = await _loadExcelFile(filePath);
    final sheet = excel.tables[sheetName];
    if (sheet == null) throw Exception('ورقة المادة المحددة غير موجودة في ملف Excel.');
    return <String>[...extractMonthsFromSheet(sheet), 'ف١', 'ف٢'];
  }
  static int _extractMonthOrderFromTitle(String examTitle, Sheet sheet, int totalMonths) {
    final title = _normalizeArabic(examTitle);
    final dynamicMonths = extractMonthsFromSheet(sheet, totalMonths: totalMonths);

    // The monthly code must come from the month sequence in row 2 of the
    // selected Excel worksheet; never substitute a hard-coded calendar order.
    for (int i = 0; i < dynamicMonths.length; i++) {
      final cleanMonthName = _normalizeArabic(dynamicMonths[i]);
      if (cleanMonthName.isNotEmpty &&
          (title.contains(cleanMonthName) || cleanMonthName.contains(title))) {
        return i + 1;
      }
    }

    throw Exception(
      'لم يتم العثور على اسم الشهر في عنوان الاختبار ضمن أسماء الأشهر في الصف الثاني من ورقة Excel المحددة. راجع عنوان الاختبار وورقة المادة.',
    );
  }

  /// يميز أوراق المواد من أوراق البيانات والإعدادات اعتماداً على
  /// ترويسة كشف الطلاب الموجودة في الصف الثالث (الفهرس 2).
  static bool _isSubjectSheet(Sheet sheet) {
    if (sheet.maxRows < 4 || sheet.maxColumns < 2) return false;

    final seatHeader = _normalizeArabic(_extractCleanText(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)),
    ));
    final nameHeader = _normalizeArabic(_extractCleanText(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)),
    ));

    final hasSeatHeader =
        seatHeader.contains('جلوس') || seatHeader == 'رقم' ||
        seatHeader.contains('رقمالجلوس');
    final hasNameHeader =
        nameHeader.contains('اسم') || nameHeader.contains('طالب');

    if (!hasSeatHeader || !hasNameHeader) return false;

    // لا نعد ورقة فارغة أو ورقة إعدادات ورقة مادة لمجرد وجود عنوان مشابه.
    for (int row = 3; row < sheet.maxRows && row < 12; row++) {
      final seat = _extractCleanText(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)),
      );
      final name = _extractCleanText(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)),
      );
      if (seat.isNotEmpty || name.isNotEmpty) return true;
    }
    return false;
  }

  static bool _isSemesterTitle(String normalizedTitle) {
    // نزيل علامات الترقيم والمسافات والرموز الخفية حتى لا يتأثر
    // التعرف باختلاف كتابة العبارة أو وجود نقطتين بعد "الدراسي".
    final cleanTitle = normalizedTitle.replaceAll(
      RegExp(r'[^ء-ي0-9٠-٩]'),
      '',
    );

    // يكفي وجود كلمة "فصل" مع تحديد الأول أو الثاني؛ وهذا يشمل:
    // الفصل الدراسي الأول/الثاني، ونهاية الفصل الدراسي: الأول/الثاني.
    final isFirstSemester = cleanTitle == 'ف1' || cleanTitle == 'ف١' ||
        cleanTitle.contains('اول') || cleanTitle.contains('١') || cleanTitle.contains('1');
    final isSecondSemester = cleanTitle == 'ف2' || cleanTitle == 'ف٢' ||
        cleanTitle.contains('ثاني') || cleanTitle.contains('٢') || cleanTitle.contains('2');
    final isSemester = cleanTitle == 'ف1' || cleanTitle == 'ف١' ||
        cleanTitle == 'ف2' || cleanTitle == 'ف٢' || cleanTitle.contains('فصل');
    return isSemester && (isFirstSemester || isSecondSemester);
  }

  static int resolveSmartQrCodeNumberDynamic({
    required String examTitle,
    required String subjectName,
    required Excel excel,
    int? totalMonths,
  }) {
    final title = _normalizeArabic(examTitle);
    final cleanSubject = _normalizeArabic(subjectName);

    if (cleanSubject.isEmpty) {
      throw Exception('يرجى تحديد اسم المادة أولاً.');
    }

    // الترتيب يحسب بين أوراق المواد فقط، مع تجاهل أوراق البيانات والإعدادات.
    final subjectSheets = excel.tables.entries
        .where((entry) => _isSubjectSheet(entry.value))
        .toList();

    int selectedSubjectIndex = -1;
    for (int i = 0; i < subjectSheets.length; i++) {
      final cleanSheet = _normalizeArabic(subjectSheets[i].key);
      if (cleanSheet == cleanSubject ||
          cleanSheet.contains(cleanSubject) ||
          cleanSubject.contains(cleanSheet)) {
        selectedSubjectIndex = i;
        break;
      }
    }

    if (selectedSubjectIndex < 0) {
      throw Exception(
        'لم يتم العثور على ورقة المادة المحددة ضمن أوراق المواد في ملف Excel. تحقق من اسم المادة وترويسة ورقة الطلاب.',
      );
    }

    final selectedSheet = subjectSheets[selectedSubjectIndex].value;
    final subjectSheetOrder = selectedSubjectIndex + 1;
    final int resolvedTotal = totalMonths ?? detectTotalMonths(selectedSheet);

    // الفصل الدراسي الأول أو الثاني: رقم ترتيب المادة بين أوراق المواد فقط.
    if (_isSemesterTitle(title)) {
      return subjectSheetOrder;
    }

    // بقية العناوين الشهرية تطابق اسم الشهر في الصف الثاني من ورقة المادة.
    return _extractMonthOrderFromTitle(examTitle, selectedSheet, resolvedTotal);
  }
  static Future<StudentExcelResult> parseExcelFile(
    String filePath, {
    String? expectedSubject,
    String? targetGrade,
    String? examTitle,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    return parseExcelBytes(
      bytes,
      expectedSubject: expectedSubject,
      targetGrade: targetGrade,
      examTitle: examTitle,
    );
  }

  static StudentExcelResult parseExcelBytes(
    Uint8List bytes, {
    String? expectedSubject,
    String? targetGrade,
    String? examTitle,
  }) {
    final fixedBytes = _fixExcelDimensions(bytes);
    final excel = Excel.decodeBytes(fixedBytes);

    if (excel.tables.isEmpty) {
      throw Exception('ملف الإكسيل فارغ ولا يحتوي على جداول بيانات.');
    }

    String targetSheetName = excel.tables.keys.first;
    final cleanExpected = _normalizeArabic(expectedSubject ?? '');

    if (cleanExpected.isNotEmpty) {
      for (final sheetName in excel.tables.keys) {
        final normSheet = _normalizeArabic(sheetName);
        if (normSheet == cleanExpected || normSheet.contains(cleanExpected) || cleanExpected.contains(normSheet)) {
          targetSheetName = sheetName;
          break;
        }
      }
    }

    final sheet = excel.tables[targetSheetName]!;

    if (sheet.maxRows < 4) {
      throw Exception('ورقة العمل لا تحتوي على بيانات كافية (الطلاب يبدأون من الصف الرابع).');
    }

    final int detectedMonths = detectTotalMonths(sheet);
    final String requiredGrade = targetGrade?.trim() ?? '';
    final List<StudentData> students = [];

    final int calculatedCode = resolveSmartQrCodeNumberDynamic(
      examTitle: examTitle ?? '',
      subjectName: expectedSubject ?? targetSheetName,
      excel: excel,
      totalMonths: detectedMonths,
    );

    const int colSeat = 0;
    const int colName = 1;
    const int colGrade = 2;
    const int colSecret = 3;

    int r = 3;
    int consecutiveEmptyRows = 0;
    int safeLimit = sheet.maxRows + 50;

    while (r < safeLimit) {
      final rawSeat = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colSeat, rowIndex: r)));
      final rawName = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colName, rowIndex: r)));
      final rawGrade = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colGrade, rowIndex: r)));
      final rawSecret = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colSecret, rowIndex: r)));

      if (rawSeat.isEmpty && rawName.isEmpty) {
        consecutiveEmptyRows++;
        if (consecutiveEmptyRows > 30) break; 
        r++;
        continue;
      }
      
      consecutiveEmptyRows = 0; 

      if (rawSeat.contains('جلوس') || rawName.contains('اسم')) {
        r++;
        continue; 
      }

      if (requiredGrade.isNotEmpty) {
        final bool isMatch = _isGradeMatch(rawGrade, requiredGrade);
        if (!isMatch) {
          r++;
          continue; 
        }
      }

      final finalSecretCode = rawSecret.isNotEmpty ? rawSecret : '$rawSeat-$calculatedCode';

      students.add(StudentData(
        seatNo: rawSeat,
        name: rawName,
        grade: rawGrade.isNotEmpty ? rawGrade : requiredGrade,
        secretCode: finalSecretCode,
      ));
      
      r++;
    }

    students.sort((a, b) {
      final intA = int.tryParse(a.seatNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final intB = int.tryParse(b.seatNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (intA > 0 && intB > 0) return intA.compareTo(intB);
      return a.seatNo.compareTo(b.seatNo);
    });

    return StudentExcelResult(
      students: students,
      subjectCode: calculatedCode,
      matchedSubjectName: targetSheetName,
      totalMonths: detectedMonths,
    );
  }

}