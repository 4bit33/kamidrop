import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'discovery/discovery.dart';
import 'platform/platform_bridge.dart';
import 'theme.dart';
import 'ui/printer_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize(); // потрібно, бо PdfDocument використовуємо без віджета-переглядача
  runApp(const KamiDropApp());
}

class KamiDropApp extends StatefulWidget {
  const KamiDropApp({super.key, this.startDiscovery = true});

  /// У тестах вимикаємо реальний пошук у мережі.
  final bool startDiscovery;

  @override
  State<KamiDropApp> createState() => _KamiDropAppState();
}

class _KamiDropAppState extends State<KamiDropApp> {
  final discovery = PrinterDiscovery();

  /// Файл, отриманий через «Поділитися → KamiDrop» (Android).
  final sharedFile = ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    if (widget.startDiscovery) discovery.start();
    PlatformBridge.takeSharedFile().then((path) {
      if (path != null) sharedFile.value = path;
    });
    PlatformBridge.listenSharedFiles((path) => sharedFile.value = path);
  }

  @override
  void dispose() {
    discovery.dispose();
    sharedFile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KamiDrop',
      debugShowCheckedModeBanner: false,
      theme: kamiTheme(),
      home: PrinterListScreen(discovery: discovery, sharedFile: sharedFile),
    );
  }
}
