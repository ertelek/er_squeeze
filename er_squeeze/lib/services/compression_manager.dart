import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../models/folder_job.dart';
import '../models/job_status.dart';
import '../services/foreground_notifier.dart';
import '../services/storage.dart';
import '../services/trash_helper.dart';
import '../services/video_processor.dart';

/// Coordinates scanning folders, re-encoding videos, progress accounting,
/// and foreground notifications. Designed as a single-process singleton.
class CompressionManager {
  // ---- Singleton -----------------------------------------------------------

  static final CompressionManager _instance = CompressionManager._();
  CompressionManager._();
  factory CompressionManager() => _instance;

  // ---- Dependencies --------------------------------------------------------

  final StorageService _storage = StorageService();

  // ---- Runtime State -------------------------------------------------------

  bool _isRunningFlag = false;
  bool _isPausedFlag = false;

  /// Active FFmpeg session id (if any), used to cancel safely.
  int? _activeFfmpegSessionId;

  /// Completes once [start] has fully unwound and stopped.
  Completer<void>? _stopBarrier;

  // ---- Constants -----------------------------------------------------------

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.wmv',
    '.flv',
    '.m4v'
  };

  // ---- Public API ----------------------------------------------------------

  /// Returns `true` while the pipeline is running (even if currently paused).
  bool get isRunning => _isRunningFlag;

  /// Returns `true` if execution is temporarily paused.
  bool get isPaused => _isPausedFlag;

  /// Starts the compression pipeline if not already running.
  ///
  /// Walks selected jobs, prescans total original bytes (recursively),
  /// and then encodes one file at a time. Produces foreground notifications
  /// on Android and persists job progress to storage after each step.
  Future<void> start() async {
    if (_isRunningFlag) return;

    _isRunningFlag = true;
    _isPausedFlag = false;
    _stopBarrier = Completer<void>();
    _log('Compression START');

    // Foreground notification (Android) – safe to call elsewhere too
    await ForegroundNotifier.init();
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    await ForegroundNotifier.start(
      title: 'Setting things up',
      text: 'Preparing to squeeze…',
    );

    final jobs = await _storage.loadJobs();
    final options = await _storage.loadOptions();
    final suffix = (options['suffix'] ?? '_compressed').toString();
    final keepOriginal = (options['keepOriginal'] ?? false) as bool;

    for (final entry in jobs.entries) {
      if (!_isRunningFlag) break; // stop requested

      final job = entry.value;
      if (job.status == JobStatus.completed) continue;

      job.status = JobStatus.inProgress;
      await ForegroundNotifier.update(
        title: 'Squeezing ${job.displayName}',
        text: _buildNotificationText(job),
      );
      await _storage.saveJobs(jobs);

      _log('Working on: ${job.displayName}');

      // Resolve and validate target directory
      final folderDir = Directory(job.folderPath);
      if (!await _hasWriteAccess(folderDir)) {
        _toast('No write access to: ${job.displayName}');
        _log('No write access to: ${job.displayName}');
      }
      if (!await folderDir.exists()) {
        _toast('Folder missing: ${job.displayName}');
        _log('Folder missing: ${job.displayName}');
        job.status = JobStatus.completed; // nothing to do
        await _storage.saveJobs(jobs);
        continue;
      }

      // Prescan original sizes across the tree (authoritative total)
      await _prescanOriginalSizesRecursively(folderDir, job);
      await _storage.saveJobs(jobs);

      await ForegroundNotifier.update(
        title: 'Squeezing ${_composeDisplayTitle(job)}',
        text: _buildNotificationText(job),
      );

      // Main file-processing loop
      while (_isRunningFlag) {
        if (_isPausedFlag) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }

        // Choose next unprocessed file
        final next = await _findNextVideoRecursively(folderDir, job);
        if (next == null) {
          job.status = JobStatus.completed;
          await _storage.saveJobs(jobs);
          _log('Folder completed: ${job.displayName}');
          break;
        }

        job.currentFilePath = next.path;
        await _storage.saveJobs(jobs);
        await ForegroundNotifier.update(
          title: 'Squeezing ${_composeDisplayTitle(job)}',
          text: _buildNotificationText(job),
        );

        final videoProcessor = VideoProcessor();

        // Kick off FFmpeg and retain session id for cancellation
        final handle = await videoProcessor.reencodeH264AacAsync(
          next,
          outputDirPath: job.folderPath,
          labelSuffix: suffix, // pure naming; detection is not based on this
          targetCrf: 28,
        );
        _activeFfmpegSessionId = await handle.session.getSessionId();

        // Busy-wait with pause/stop handling
        while (true) {
          if (!_isRunningFlag || _isPausedFlag) {
            final id = _activeFfmpegSessionId;
            if (id != null) {
              await FFmpegKit.cancel(id);
            }
            break;
          }
          final rc = await handle.session.getReturnCode();
          if (rc != null) break; // finished
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }

        // Completion handling
        final rc = await handle.session.getReturnCode();
        if (rc != null && rc.isValueSuccess()) {
          // 1) Account original size (authoritative)
          final originalSize = await _tryGetFileSize(next);
          job.completedSizes[next.path] = originalSize;
          job.processedBytes += originalSize;

          // 2) If output grew, replace it with the original bytes
          await _ensureOutputNoBiggerThanInput(
            input: next,
            outputPath: handle.outPath,
            inputSize: originalSize,
          );

          // 3) In-place mode (empty suffix) → swap temp into original
          if (suffix.trim().isEmpty) {
            await _commitTempOverOriginal(
              tempPath: handle.outPath,
              original: next,
              job: job,
            );
          } else {
            // Separate output file (normal case)
            job.compressedPaths.add(handle.outPath);
          }

          // 4) Optional: move/delete original if keeping is disabled (suffix mode only)
          if (suffix.trim().isNotEmpty && !keepOriginal) {
            await TrashHelper.trash(next);
          }

          await _storage.saveJobs(jobs);
          _log('Finished: ${next.path}');

          await ForegroundNotifier.update(
            title: 'Squeezing ${_composeDisplayTitle(job)}',
            text: _buildNotificationText(job),
          );
          await _storage.saveJobs(jobs);

          // 5) Gentle pacing to reduce thermal/IO stress
          for (int i = 0; i < 300; i++) {
            if (!_isRunningFlag || _isPausedFlag) break;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        } else {
          // Error handling: try to capture logs or at least an exception string
          try {
            final allLogs = await handle.session.getAllLogs();
            final output = allLogs.map((e) => e.getMessage()).join('\n');
            job.errorMessage = output;
          } catch (e) {
            job.errorMessage = e.toString();
          }
          await _storage.saveJobs(jobs);

          if (_isPausedFlag) {
            while (_isPausedFlag && _isRunningFlag) {
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
          } else if (!_isRunningFlag) {
            break;
          } else {
            // Mark as “done” with size 0 to avoid infinite retry loops for bad files
            job.completedSizes[next.path] = job.completedSizes[next.path] ?? 0;
            await _storage.saveJobs(jobs);
          }
        }
      }
      // end while
    }
    // end for

    // Teardown
    _isRunningFlag = false;
    _isPausedFlag = false;
    _activeFfmpegSessionId = null;
    await ForegroundNotifier.stop();

    if (!(_stopBarrier?.isCompleted ?? true)) {
      _stopBarrier!.complete();
    }
    _stopBarrier = null;

    _log('Compression STOP (done or stopped)');
  }

  /// Temporarily pauses the pipeline. Call [resume] to continue.
  Future<void> pause() async {
    _isPausedFlag = true;
    await ForegroundNotifier.update(
      text:
          'Paused • ${DateTime.now().toLocal().toString().split(' ')[1].substring(0, 8)}',
    );
    _log('PAUSE requested');
  }

  /// Resumes the pipeline if it was previously paused.
  Future<void> resume() async {
    _isPausedFlag = false;
    await ForegroundNotifier.update(text: 'Resumed');
    _log('RESUME');
  }

  /// Requests a stop and waits up to [timeout] for the pipeline to unwind.
  ///
  /// If an FFmpeg session is in-flight, it will be cancelled.
  Future<void> stopAndWait(
      {Duration timeout = const Duration(seconds: 5)}) async {
    _isRunningFlag = false;
    _isPausedFlag = false;
    _log('STOP requested');

    final id = _activeFfmpegSessionId;
    if (id != null) {
      try {
        await FFmpegKit.cancel(id);
      } catch (_) {
        // ignore cancellation errors
      }
    }

    final future = _stopBarrier?.future;
    if (future != null) {
      try {
        await future.timeout(timeout);
      } catch (_) {
        // timeout is acceptable; caller just wanted a best-effort wait
      }
    }
  }

  /// Requests a stop. Alias of [stopAndWait] with default timeout.
  Future<void> stop() => stopAndWait();

  // ---- Private helpers -----------------------------------------------------

  void _log(String message) {} //print(message);

  void _toast(String msg) {
    Fluttertoast.showToast(msg: msg, toastLength: Toast.LENGTH_LONG);
  }

  String _composeDisplayTitle(FolderJob job) {
    final current = job.currentFilePath;
    if (current == null) return job.displayName;

    final parentDirPath = File(current).parent.path;
    final leafFolder = p.basename(parentDirPath);
    if (p.equals(parentDirPath, job.folderPath)) return job.displayName;

    return '${job.displayName} > $leafFolder';
  }

  String _buildNotificationText(FolderJob job) {
    return 'Completed: ${_formatPercent(job.processedBytes, job.totalBytes)}';
  }

  String _formatPercent(int done, int total) {
    if (total <= 0) return '0%';
    final pct = (done / total * 100).clamp(0, 100);
    return '${pct.toStringAsFixed(1)}%';
  }

  bool _looksLikeVideoPath(String path) {
    final lower = path.toLowerCase();
    for (final ext in _videoExtensions) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  Future<int> _tryGetFileSize(File f) async {
    try {
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _ensureOutputNoBiggerThanInput({
    required File input,
    required String outputPath,
    required int inputSize,
  }) async {
    try {
      final outFile = File(outputPath);
      if (!await outFile.exists()) {
        _log('Output file missing when comparing sizes: $outputPath');
        return;
      }
      final outSize = await outFile.length();
      if (outSize > inputSize) {
        _log(
            'Output larger than input ($outSize > $inputSize). Replacing output with original bytes.');
        await outFile.writeAsBytes(await input.readAsBytes(), flush: true);
      }
    } catch (e) {
      _log('Size compare/overwrite failed for $outputPath: $e');
    }
  }

  Future<void> _commitTempOverOriginal({
    required String tempPath,
    required File original,
    required FolderJob job,
  }) async {
    var pathToUse = tempPath;

    // Guard: never let temp == original
    if (pathToUse == original.path) {
      _log('Internal error: temp path equals original');
      pathToUse += DateTime.now().millisecondsSinceEpoch.toString();
    }

    try {
      if (await original.exists()) {
        await TrashHelper.trash(original);
      }

      final tempFile = File(pathToUse);
      if (await tempFile.exists()) {
        try {
          await tempFile.rename(original.path);
          job.compressedPaths.add(original.path);
          _log('Replaced original with compressed file: ${original.path}');
        } catch (e) {
          _log('Rename temp -> original failed: $e');
          job.compressedPaths.add(pathToUse); // best-effort fallback
        }
      } else {
        _log('Temp file missing: $pathToUse');
      }
    } catch (e, st) {
      _log('In-place replace error: $e\n$st');
      job.compressedPaths.add(tempPath); // best-effort fallback
    }
  }

  Future<void> _prescanOriginalSizesRecursively(
    Directory root,
    FolderJob job,
  ) async {
    int total = 0;

    try {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (entity.path.contains('.Trash')) continue;

        final filePath = entity.path;
        if (!_looksLikeVideoPath(filePath)) continue;
        if (job.compressedPaths.contains(filePath))
          continue; // skip our outputs

        // If already completed, include the known original size
        if (job.completedSizes.containsKey(filePath)) {
          total += job.completedSizes[filePath]!;
          continue;
        }

        total += await _tryGetFileSize(entity);
      }
    } catch (_) {
      // silently ignore traversal errors
    }

    job.totalBytes = total;

    // Keep processedBytes consistent with sum of completed originals
    job.processedBytes =
        job.completedSizes.values.fold<int>(0, (acc, v) => acc + v);
  }

  Future<File?> _findNextVideoRecursively(Directory root, FolderJob job) async {
    try {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (entity.path.contains('.Trash')) continue;

        final filePath = entity.path;
        if (!_looksLikeVideoPath(filePath)) continue;

        // Skip files we already processed or that are our produced outputs
        if (job.completedSizes.containsKey(filePath)) continue;
        if (job.compressedPaths.contains(filePath)) continue;

        return entity;
      }
    } catch (_) {
      // silently ignore traversal errors
    }
    return null;
  }

  Future<bool> _hasWriteAccess(Directory dir) async {
    try {
      final probe = File(
        p.join(
            dir.path, '.write_probe_${DateTime.now().microsecondsSinceEpoch}'),
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
