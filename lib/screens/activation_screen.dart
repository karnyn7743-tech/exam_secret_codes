import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/activation_service.dart';
import 'document_hub_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});
  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _keyController = TextEditingController();
  String _deviceId = 'جارٍ قراءة معرّف الجهاز...';
  String? _errorMessage;
  bool _loading = true, _submitting = false;
  int _remainingDays = 0;
  LicenseStatus _status = LicenseStatus.locked;

  @override
  void initState() { super.initState(); _loadStatus(); }
  @override
  void dispose() { _keyController.dispose(); super.dispose(); }

  Future<void> _loadStatus() async {
    try {
      final id = await ActivationService.getDeviceId();
      final status = await ActivationService.getLicenseStatus();
      final remaining = await ActivationService.getRemainingTrialDays();
      if (!mounted) return;
      setState(() { _deviceId = id; _status = status; _remainingDays = remaining; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _deviceId = 'تعذر قراءة معرّف الجهاز'; _errorMessage = e.toString(); _loading = false; });
    }
  }

  Future<void> _activate() async {
    if (_submitting) return;
    final key = _keyController.text.trim();
    if (key.isEmpty) { setState(() => _errorMessage = 'أدخل مفتاح التفعيل أولاً.'); return; }
    setState(() { _submitting = true; _errorMessage = null; });
    try {
      final status = await ActivationService.applyKey(key);
      if (!mounted) return;
      if (status == LicenseStatus.locked) {
        setState(() => _errorMessage = 'المفتاح غير صحيح أو غير مخصص لهذا الجهاز أو انتهت صلاحيته.');
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DocumentHubScreen()));
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'تعذر التحقق من المفتاح: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ معرّف الجهاز.')));
  }

  @override
  Widget build(BuildContext context) {
    final isTrial = _status == LicenseStatus.trial;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 56, color: Color(0xFF1E3A8A)),
                        const SizedBox(height: 12),
                        const Text('تفعيل بيانات الطلاب للاختبارات', textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                        const SizedBox(height: 8),
                        const Text('انسخ معرّف الجهاز وأرسله لإصدار مفتاح تجريبي لمدة 30 يوماً أو مفتاح دائم.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6)),
                        if (isTrial && _remainingDays > 0) ...[
                          const SizedBox(height: 14),
                          Text('الفترة التجريبية: متبقي $_remainingDays يوماً', textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                        ],
                        const Divider(height: 28),
                        const Text('معرّف الجهاز:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SelectableText(_deviceId, textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Color(0xFF0F766E))),
                        Align(alignment: Alignment.center, child: TextButton.icon(
                          onPressed: _loading ? null : _copyDeviceId, icon: const Icon(Icons.copy), label: const Text('نسخ معرّف الجهاز'))),
                        const SizedBox(height: 10),
                        TextField(controller: _keyController, textAlign: TextAlign.center, autocorrect: false, enableSuggestions: false,
                          decoration: InputDecoration(labelText: 'مفتاح التفعيل', hintText: 'الصق المفتاح هنا',
                            border: const OutlineInputBorder(), errorText: _errorMessage)),
                        const SizedBox(height: 14),
                        FilledButton.icon(onPressed: _loading || _submitting ? null : _activate,
                          icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_open),
                          label: const Text('تحقق من مفتاح التفعيل')),
                        const SizedBox(height: 8),
                        const Text('يعمل المفتاح على الجهاز المرتبط به فقط. يحمل مفتاح التجربة تاريخ انتهاء ثابتاً، فلا يبدأ العداد من جديد عند إعادة تثبيت التطبيق.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.black54, height: 1.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
