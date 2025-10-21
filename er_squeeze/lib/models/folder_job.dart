import 'dart:convert';
import 'job_status.dart';

class FolderJob {
  final String displayName; // e.g., "DCIM"
  final String folderPath; // full path to the root selected in Settings
  final bool recursive;
  JobStatus status;

  // NEW semantics:
  // - totalBytes = sum of ORIGINAL sizes of all videos found (root + all descendants) at job start
  // - processedBytes = sum of ORIGINAL sizes of completed videos
  int totalBytes;
  int processedBytes;

  String? currentFilePath; // file being processed or last paused file
  String? errorMessage;

  // REPLACED: donePaths -> completedSizes (path -> ORIGINAL size in bytes)
  Map<String, int> completedSizes;

  // Keep: tracks outputs created by the app (absolute paths) so we ignore them when scanning/picking.
  Set<String> compressedPaths;

  FolderJob({
    required this.displayName,
    required this.folderPath,
    this.recursive = false,
    this.status = JobStatus.notStarted,
    this.totalBytes = 0,
    this.processedBytes = 0,
    this.currentFilePath,
    Map<String, int>? completedSizes,
    Set<String>? compressedPaths,
  })  : completedSizes = completedSizes ?? <String, int>{},
        compressedPaths = compressedPaths ?? <String>{};

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'folderPath': folderPath,
        'recursive': recursive,
        'status': status.index,
        'totalBytes': totalBytes,
        'processedBytes': processedBytes,
        'currentFilePath': currentFilePath,
        'completedSizes': completedSizes, // NEW
        'compressedPaths': compressedPaths.toList(),
      };

  static FolderJob fromMap(Map<String, dynamic> m) => FolderJob(
        displayName: m['displayName'],
        folderPath: m['folderPath'],
        recursive: (m['recursive'] ?? false) as bool,
        status: JobStatus.values[(m['status'] ?? 0) as int],
        totalBytes: (m['totalBytes'] ?? 0) as int,
        processedBytes: (m['processedBytes'] ?? 0) as int,
        currentFilePath: m['currentFilePath'],
        completedSizes: Map<String, int>.from(m['completedSizes'] ?? const {}),
        compressedPaths: ((m['compressedPaths'] ?? const <String>[]) as List)
            .map((e) => e.toString())
            .toSet(),
      );

  String toJson() => jsonEncode(toMap());
  static FolderJob fromJson(String s) => fromMap(jsonDecode(s));
}
