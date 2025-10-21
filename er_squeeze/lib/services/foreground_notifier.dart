import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class ForegroundNotifier {
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'compress_progress',
        channelName: 'Compression Progress',
        channelDescription:
            'Shows current folder and progress while compressing',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: true,
        // remove unsupported fields like isSticky, playSound defaults false
        // enableVibration/playSound can stay default false
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: IOSNotificationOptions(
        showNotification: true,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // ✅ required in recent versions
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<void> start(
      {required String title, required String text}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  static Future<void> update({String? title, String? text}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.stopService();
  }
}
