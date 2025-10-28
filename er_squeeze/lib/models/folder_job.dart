import 'dart:convert';
import 'job_status.dart';

class FileState {
  final int originalBytes;
  final bool compressed;

  const FileState({required this.originalBytes, required this.compressed});

  Map<String, dynamic> toMap() => {
        'originalBytes': originalBytes,
        'compressed': compressed,
      };

  static FileState fromMap(Map<String, dynamic> m) => FileState(
        originalBytes: (m['originalBytes'] ?? 0) as int,
        compressed: (m['compressed'] ?? false) as bool,
      );
}

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

  // NEW: authoritative mapping of *all* videos found => size + compressed flag
  // Keys are *source* file paths (not outputs).
  Map<String, FileState> fileIndex;

  Map<String, int> completedSizes;
  Set<String> compressedPaths;

  FolderJob({
    required this.displayName,
    required this.folderPath,
    this.recursive = false,
    this.status = JobStatus.notStarted,
    this.totalBytes = 0,
    this.processedBytes = 0,
    this.currentFilePath,
    Map<String, FileState>? fileIndex,
    Map<String, int>? completedSizes,
    Set<String>? compressedPaths,
  })  : fileIndex = fileIndex ?? <String, FileState>{},
        completedSizes = completedSizes ?? <String, int>{},
        compressedPaths = compressedPaths ?? <String>{};

  // Helpers to compute totals from the index
  int get mappedTotalBytes =>
      fileIndex.values.fold(0, (a, f) => a + f.originalBytes);

  int get mappedCompressedBytes => fileIndex.entries
      .where((e) => e.value.compressed)
      .fold(0, (a, e) => a + e.value.originalBytes);

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'folderPath': folderPath,
        'recursive': recursive,
        'status': status.index,
        'totalBytes': totalBytes,
        'processedBytes': processedBytes,
        'currentFilePath': currentFilePath,
        'fileIndex': {
          for (final e in fileIndex.entries) e.key: e.value.toMap(),
        },
        'completedSizes': completedSizes,
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
        fileIndex: {
          for (final e
              in (m['fileIndex'] as Map? ?? const <String, dynamic>{}).entries)
            e.key: FileState.fromMap(Map<String, dynamic>.from(e.value)),
        },
        completedSizes: Map<String, int>.from(m['completedSizes'] ?? const {}),
        compressedPaths: ((m['compressedPaths'] ?? const <String>[]) as List)
            .map((e) => e.toString())
            .toSet(),
      );

  String toJson() => jsonEncode(toMap());
  static FolderJob fromJson(String s) => fromMap(jsonDecode(s));

  static String getPrettyFolderPath(String s) =>
      s.replaceFirst("/storage/emulated/0", "Internal Storage");
}
