import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/activation_screen.dart';
import 'screens/document_hub_screen.dart';
import 'services/activation_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = await ActivationService.getLicenseStatus();
  runApp(ExamSecretCodesApp(
    hasValidLicense: status == LicenseStatus.full || status == LicenseStatus.trial,
  ));
}

class ExamSecretCodesApp extends StatelessWidget {
  final bool hasValidLicense;
  const ExamSecretCodesApp({super.key, required this.hasValidLicense});

  @override
  Widget build(BuildContext context) {
    const appColor = Color(0xFF52796F);
    return MaterialApp(
      title: 'بيانات الطلاب للاختبارات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [Locale('ar', 'YE'), Locale('ar', ''), Locale('en', '')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        useMaterial3: true,
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: hasValidLicense ? const DocumentHubScreen() : const ActivationScreen(),
      ),
    );
  }
}
