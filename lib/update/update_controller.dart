import 'package:flutter/foundation.dart';

import '../platform/platform_bridge.dart';
import '../settings.dart';
import 'updater.dart';
import '../l10n/l10n.dart';

enum UpdateState { idle, checking, upToDate, available, downloading, installing, error }

/// Стан оновлення для банера на головному екрані й екрана налаштувань.
class UpdateController extends ChangeNotifier {
  UpdateController(this.settings) {
    PlatformBridge.listenUpdateErrors((msg) => _fail(l10n.updateInstallFailed(msg)));
  }

  KamiSettings settings;

  UpdateState state = UpdateState.idle;
  UpdateInfo? info;
  double progress = 0;
  String? message;
  String? currentVersion;
  bool dismissed = false; // банер закрили — до наступного запуску не показуємо

  bool get bannerVisible =>
      !dismissed &&
      (state == UpdateState.available ||
          state == UpdateState.downloading ||
          state == UpdateState.installing ||
          (state == UpdateState.error && info != null));

  /// Перевіряє оновлення. Без [force] — не частіше раза на добу й лише якщо дозволено в налаштуваннях.
  Future<void> check({bool force = false}) async {
    final app = await PlatformBridge.appInfo();
    if (app == null) return; // оновлення лише для Android-збірки
    currentVersion = app.version;
    if (!force) {
      if (!settings.checkUpdates) return;
      final last = settings.lastUpdateCheck;
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) return;
    }
    if (state == UpdateState.checking || state == UpdateState.downloading || state == UpdateState.installing) return;
    _set(UpdateState.checking);
    try {
      final found = await checkForUpdate(currentVersion: app.version, abi: app.abi);
      settings
        ..lastUpdateCheck = DateTime.now()
        ..save();
      info = found;
      dismissed = false;
      _set(found == null ? UpdateState.upToDate : UpdateState.available);
    } catch (e) {
      _fail(l10n.updateCheckFailed('$e'));
    }
  }

  Future<void> install() async {
    final i = info;
    if (i == null) return;
    _set(UpdateState.downloading);
    try {
      progress = 0;
      final path = await downloadUpdate(i, onProgress: (p) {
        progress = p;
        notifyListeners();
      });
      final r = await PlatformBridge.installApk(path);
      if (r == 'permission') {
        message = l10n.updateAllowInstall;
        _set(UpdateState.available);
      } else {
        message = null;
        _set(UpdateState.installing);
      }
    } catch (e) {
      _fail(l10n.updateDownloadFailed('$e'));
    }
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  void _fail(String msg) {
    message = msg;
    _set(UpdateState.error);
  }

  void _set(UpdateState s) {
    state = s;
    if (s != UpdateState.available && s != UpdateState.error) message = null;
    notifyListeners();
  }
}
