import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/folder_job.dart';
import '../models/job_status.dart';
import '../services/storage.dart';
import '../services/compression_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';

/// Settings screen for configuring compression scope, options, and starting/stopping
/// the background compression pipeline.
///
/// Behavior highlights:
/// - Two modes: **Selected folders** vs **All folders**.
/// - When **All folders** is selected, the suffix is cleared (unused in that flow).
/// - When **Keep original files** is **unchecked**, the suffix is cleared.
/// - “Permissions” section is hidden once MANAGE_EXTERNAL_STORAGE is granted.
/// - The Start/Stop button disables starting when suffix is required but empty.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, this.goToStatusTab});
  final VoidCallback? goToStatusTab;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  // Services
  final _storage = StorageService();
  final _manager = CompressionManager();

  // State
  Map<String, FolderJob> _jobs = {};
  final TextEditingController _suffixCtl = TextEditingController();
  bool _keepOriginal = false;

  /// `false` = Selected folders; `true` = All folders.
  bool _allFoldersMode = true;

  /// Tracks MANAGE_EXTERNAL_STORAGE ("All files access") status on Android.
  bool _hasAllFilesAccess = false;

  /// Disable Start when:
  /// - In selected-folders mode, no folders are chosen; or
  /// - In selected-folders mode + keepOriginal is ON + suffix is empty.
  bool get _shouldDisableStart =>
      (!_allFoldersMode && _jobs.isEmpty) ||
      (!_manager.isRunning &&
          !_allFoldersMode &&
          _keepOriginal &&
          _suffixCtl.text.trim().isEmpty);

  static const String _scopeInfoText =
      'All videos in your Internal Storage will be compressed. '
      'The “Internal Storage” root will be processed without recursion, '
      'and each immediate folder within it will be processed recursively. '
      'Original files will be deleted when done.';

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  @override
  void dispose() {
    _suffixCtl.dispose();
    super.dispose();
  }

  /// Confirms that the user understands originals will be replaced/deleted.
  /// Returns true if the user chooses to proceed.
  Future<bool> _confirmOriginalsWillBeDeleted() async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start compression'),
        content: const Text(
          'Your original videos will be replaced with the compressed versions, '
          'and the originals will be deleted.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I understand, start'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Permissions
  // ────────────────────────────────────────────────────────────────────────────

  /// Refreshes and caches whether MANAGE_EXTERNAL_STORAGE is granted.
  Future<void> _refreshAllFilesAccessStatus() async {
    if (!Platform.isAndroid) {
      setState(() => _hasAllFilesAccess = true);
      return;
    }
    final status = await Permission.manageExternalStorage.status;
    if (mounted) setState(() => _hasAllFilesAccess = status.isGranted);
  }

  /// Opens the “All files access” settings page and polls for grant.
  Future<void> _requestAllFilesAccess() async {
    if (!Platform.isAndroid) return;

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) {
      setState(() => _hasAllFilesAccess = true);
      return;
    }

    const intent = AndroidIntent(
      action: 'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
      data: 'package:com.ertelek.squeeze',
    );
    await intent.launch();

    // Poll briefly for the user's decision.
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      status = await Permission.manageExternalStorage.status;
      if (status.isGranted) break;
    }
    if (mounted) setState(() => _hasAllFilesAccess = status.isGranted);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Loading & persistence
  // ────────────────────────────────────────────────────────────────────────────

  /// Loads jobs and options from storage, infers mode, and updates permission state.
  Future<void> _loadPersistedState() async {
    _jobs = await _storage.loadJobs();

    final options = await _storage.loadOptions();
    _suffixCtl.text = (options['suffix'] ?? '').toString();
    _keepOriginal = (options['keepOriginal'] ?? false) as bool;

    // Infer mode from existing jobs (presence of "Internal Storage" root).
    _allFoldersMode = _jobs.isEmpty ||
        _jobs.values.any((j) =>
            j.displayName == 'Internal Storage' &&
            p.normalize(j.folderPath) ==
                p.normalize(_androidInternalStorageRoot()));

    await _refreshAllFilesAccessStatus();

    if (mounted) setState(() {});
  }

  /// Resets progress counters/fields on all jobs to their initial state.
  void _resetAllJobsProgress(Map<String, FolderJob> jobs) {
    for (final job in jobs.values) {
      job.processedBytes = 0;
      job.totalBytes = 0;
      job.currentFilePath = null;
      job.completedSizes.clear();
      job.compressedPaths.clear();
      job.status = JobStatus.notStarted;
    }
  }

  /// Clears the suffix field in-memory and on disk, and rebuilds the UI.
  Future<void> _clearSuffixAndPersist() async {
    if (_suffixCtl.text.isEmpty) return;
    _suffixCtl.text = '';
    await _storage.saveOptions(suffix: '');
    if (mounted) setState(() {});
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Folder selection & indexing
  // ────────────────────────────────────────────────────────────────────────────

  /// Prompts the user to choose a folder and registers it as a recursive job
  /// (only for Selected-folders mode).
  Future<void> _pickAndAddFolder() async {
    await _requestAllFilesAccess(); // ensure access first (Android)
    if (!_hasAllFilesAccess) return;

    final dirPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Pick a folder');
    if (dirPath == null) return;

    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    final display = _leafName(dirPath);
    _jobs[dirPath] = FolderJob(
      displayName: display,
      folderPath: dirPath,
      recursive: true,
    );

    await _storage.saveJobs(_jobs);
    await _storage.saveOptions(selectedFolders: _jobs.keys.toList());
    if (mounted) setState(() {});
  }

  /// Returns the leaf folder name for display, falling back to the full path.
  String _leafName(String folderPath) {
    final base = p.basename(folderPath);
    return base.isEmpty ? folderPath : base;
  }

  /// Platform root used to enumerate user-visible storage on Android.
  /// On non-Android, returns the process directory (not used for whole-device scan).
  String _androidInternalStorageRoot() {
    if (!Platform.isAndroid) return Directory.current.path;
    return Directory('/storage/emulated/0').path;
  }

  /// Builds jobs for **All folders** mode:
  /// - Adds “Internal Storage” root (non-recursive)
  /// - Adds each immediate child directory (recursive)
  Future<void> _indexAllFoldersJobs() async {
    _jobs.clear();

    final rootPath = _androidInternalStorageRoot();
    final rootDir = Directory(rootPath);

    _jobs[rootPath] = FolderJob(
      displayName: 'Internal Storage',
      folderPath: rootPath,
      recursive: false,
    );

    try {
      await for (final ent
          in rootDir.list(recursive: false, followLinks: false)) {
        if (ent is! Directory) continue;
        final path = ent.path;
        final name = p.basename(path);
        if (name.isEmpty || name == 'Android' || name.startsWith('.')) continue;

        _jobs[path] = FolderJob(
          displayName: name,
          folderPath: path,
          recursive: true,
        );
      }
    } catch (_) {
      // ignore traversal errors (permission prompts appear elsewhere)
    }

    await _storage.saveJobs(_jobs);
    await _storage.saveOptions(selectedFolders: _jobs.keys.toList());
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Start / Stop
  // ────────────────────────────────────────────────────────────────────────────

  /// Starts or stops the compression pipeline.
  ///
  /// On stop:
  /// - Waits for the worker to unwind
  /// - Clears jobs and selected folders, so Status tab shows empty state
  Future<void> _onStartStopPressed() async {
    // If running/paused → this is a STOP request; do NOT show the dialog.
    if (_isLocked) {
      await _manager.stopAndWait();
      _jobs.clear();
      await _storage.saveJobs({});
      await _storage.saveOptions(selectedFolders: []);
      _jobs = await _storage.loadJobs();
      if (mounted) setState(() {});
      return;
    }

    // We are about to START. If "All folders" OR "Keep original" is OFF,
    // ask for explicit confirmation that originals will be replaced/deleted.
    final bool needsWarning = _allFoldersMode || !_keepOriginal;
    if (needsWarning) {
      final ok = await _confirmOriginalsWillBeDeleted();
      if (!ok) return; // user cancelled
    }

    // Build jobs according to the selected mode
    if (_allFoldersMode) {
      await _requestAllFilesAccess();
      if (!_hasAllFilesAccess) return;
      await _indexAllFoldersJobs();
    } else {
      await _storage.saveOptions(selectedFolders: _jobs.keys.toList());
    }

    // Persist options (use current suffix/keepOriginal values)
    await _storage.saveOptions(
      suffix: _suffixCtl.text.trim(),
      keepOriginal: _keepOriginal,
    );

    // Reset progress & save
    final jobs = await _storage.loadJobs();
    _resetAllJobsProgress(jobs);
    await _storage.saveJobs(jobs);

    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    // Start worker
    // ignore: unawaited_futures
    _manager.start();

    // Jump to Status tab
    widget.goToStatusTab?.call();

    if (mounted) setState(() {});
  }

  /// Prepares **All folders** mode by ensuring permissions and indexing scope.
  Future<void> _prepareAllFoldersMode() async {
    await _requestAllFilesAccess();
    if (!_hasAllFilesAccess) return;
    await _indexAllFoldersJobs();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ────────────────────────────────────────────────────────────────────────────

  bool get _isLocked => _manager.isRunning || _manager.isPaused;

  /// Greys out and disables a subtree while compression is running/paused.
  Widget _disabledWhenLocked({required Widget child}) {
    return Opacity(
      opacity: _isLocked ? 0.5 : 1,
      child: AbsorbPointer(absorbing: _isLocked, child: child),
    );
  }

  Widget _sectionDivider() => const Divider(height: 32, thickness: 1);

  /// Start/Stop floating action button with contextual tooltip and disabled logic.
  Widget _startStopFab({required bool running}) {
    final disabled = _shouldDisableStart;
    final Color? bgColor =
        running ? Colors.red : (disabled ? null : Colors.green);
    final tooltip = running
        ? 'Stop compression'
        : (disabled
            ? 'Add a suffix or uncheck “Keep original files”'
            : 'Start compression');

    return Tooltip(
      message: tooltip,
      child: FloatingActionButton.extended(
        onPressed: disabled ? null : _onStartStopPressed,
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        icon: Icon(
            running ? Icons.stop_circle_outlined : Icons.play_arrow_rounded),
        label: Text(running ? 'Stop compression' : 'Start compression'),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      );

  // ────────────────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final running = _manager.isRunning;
    final suffixRequired = !_allFoldersMode && _keepOriginal;
    final suffixEmpty = _suffixCtl.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Mode
          _sectionHeader('Mode'),
          _disabledWhenLocked(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Expanded(
                    child: Text('Compress all videos on this device'),
                  ),
                  IconButton(
                    tooltip: 'More info',
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Compress all videos'),
                          content: const Text(_scopeInfoText),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              trailing: Switch.adaptive(
                value: _allFoldersMode,
                onChanged: _isLocked
                    ? null
                    : (v) async {
                        setState(() => _allFoldersMode = v);
                        if (v) {
                          // Switching to ALL folders → clear suffix immediately.
                          await _clearSuffixAndPersist();
                          await _prepareAllFoldersMode();
                          if (mounted) setState(() {});
                        } else {
                          _jobs.clear();
                          await _storage.saveJobs(_jobs);
                          await _storage.saveOptions(selectedFolders: []);
                          if (mounted) setState(() {});
                        }
                      },
              ),
            ),
          ),

          _sectionDivider(),

          // Permissions (hidden once granted or on non-Android)
          if (!_hasAllFilesAccess) ...[
            _sectionHeader('Permissions'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Grant “All files access”'),
              subtitle: const Text('Required for scanning / saving videos'),
              onTap: _requestAllFilesAccess,
              trailing: const Icon(Icons.chevron_right),
            ),
            _sectionDivider(),
          ],

          // Selected-folders options
          if (!_allFoldersMode) ...[
            _sectionHeader('Folders & Options'),
            _disabledWhenLocked(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Add folder'),
                    subtitle: const Text('Choose a folder to include'),
                    enabled: !_isLocked,
                    onTap: _isLocked ? null : _pickAndAddFolder,
                    trailing: const Icon(Icons.chevron_right),
                  ),

                  // Keep original files
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _keepOriginal,
                    onChanged: _isLocked
                        ? null
                        : (v) async {
                            final next = (v ?? false);
                            setState(() => _keepOriginal = next);
                            // If user deselects "Keep original" → clear suffix now.
                            if (!next) {
                              await _clearSuffixAndPersist();
                            }
                          },
                    title: const Text('Keep original files after compression'),
                  ),

                  // Suffix is visible only when keeping originals.
                  if (_keepOriginal)
                    TextField(
                      controller: _suffixCtl,
                      onChanged: (_) => setState(() {}),
                      enabled: !_isLocked,
                      decoration: InputDecoration(
                        isDense: true,
                        label: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Compressed file suffix'),
                              if (suffixRequired)
                                TextSpan(
                                  text: ' *',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 14),
                        ),
                        floatingLabelStyle: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 12),
                        errorText: (suffixRequired && suffixEmpty)
                            ? 'Suffix is required.'
                            : null,
                      ),
                    ),

                  const SizedBox(height: 20),
                  const Text('Selected folders'),
                  const SizedBox(height: 8),

                  _jobs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('No folders selected yet.'),
                        )
                      : Column(
                          children: _jobs.values
                              .map(
                                (j) => ListTile(
                                  leading: const Icon(Icons.folder),
                                  title: Text(j.displayName),
                                  subtitle: Text(FolderJob.getPrettyFolderPath(
                                      j.folderPath)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: _isLocked
                                        ? null
                                        : () async {
                                            _jobs.remove(j.folderPath);
                                            await _storage.saveJobs(_jobs);
                                            await _storage.saveOptions(
                                              selectedFolders:
                                                  _jobs.keys.toList(),
                                            );
                                            if (mounted) setState(() {});
                                          },
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ],
              ),
            ),
          ],

          // “All folders” preview
          if (_allFoldersMode) ...[
            _sectionHeader('All folders'),
            const SizedBox(height: 8),
            if (_jobs.isNotEmpty)
              Column(
                children: _jobs.values
                    .map((j) => ListTile(
                          dense: true,
                          leading: Icon(
                            j.recursive
                                ? Icons.folder_copy_outlined
                                : Icons.folder_outlined,
                          ),
                          title: Text(j.displayName),
                          subtitle: Text(
                            '${FolderJob.getPrettyFolderPath(j.folderPath)}\nrecursive: ${j.recursive}',
                          ),
                          isThreeLine: true,
                        ))
                    .toList(),
              )
            else
              const Text('No folders indexed yet.'),
          ],

          const SizedBox(height: 64),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _startStopFab(running: running),
    );
  }
}
