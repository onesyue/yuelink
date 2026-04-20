import 'package:url_launcher/url_launcher.dart';

abstract interface class PaymentLauncher {
  Future<bool> launch(String url);
}

class UrlLauncherPaymentLauncher implements PaymentLauncher {
  const UrlLauncherPaymentLauncher();

  @override
  Future<bool> launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) return false;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }
}
