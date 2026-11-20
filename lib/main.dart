import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/document_hub_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExamSecretCodesApp());
}

class ExamSecretCodesApp extends StatelessWidget {
  const ExamSecretCodesApp({super.key});

  @override
  Widget build(BuildContext context) {
    const appColor = Color(0xFF52796F);
    return MaterialApp(
      title: 'بيانات الطلاب لأوراق الاختبارات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'YE'),
      supportedLocales: const [
        Locale('ar', 'YE'),
        Locale('ar', ''),
        Locale('en', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: appColor),
        useMaterial3: true,
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DocumentHubScreen(),
      ),
    );
  }
}
