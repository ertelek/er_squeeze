import 'dart:io';

/// Trashes a file by permanently deleting it.
/// Returns true if the file no longer exists when finished.
class TrashHelper {
  static Future<bool> trash(File file) async {
    try {
      if (await file.exists()) {
        await file.delete(); // permanent delete
      }
      return !await file.exists();
    } catch (_) {
      return false;
    }
  }
}
