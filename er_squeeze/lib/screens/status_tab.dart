import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/folder_job.dart';
import '../models/job_status.dart';
import '../services/storage.dart';
import '../services/compression_manager.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});
  @override
  State<StatusTab> createState() => StatusTabState();
}

class StatusTabState extends State<StatusTab> {
  Timer? _refreshTimer;
  final _storage = StorageService();
  Map<String, FolderJob> _jobs = {};
  final _mgr = CompressionManager();

  @override
  void initState() {
    super.initState();
    refreshJobs();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (mounted) {
          refreshJobs();
        }
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> refreshJobs() async {
    _jobs = await _storage.loadJobs();
    if (mounted) setState(() {});
  }

  Color _dotColorFor(FolderJob job, int idx) {
    switch (job.status) {
      case JobStatus.inProgress:
        return _mgr.isPaused ? Colors.yellow : Colors.green; // current
      case JobStatus.completed:
        return Colors.blue; // finished
      case JobStatus.notStarted:
        return Colors.red; // not yet
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
      ),
      body: RefreshIndicator(
        onRefresh: refreshJobs,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: _jobs.values.map((job) {
            String composedName(FolderJob j) {
              if (j.currentFilePath == null) {
                return j.displayName.isNotEmpty
                    ? j.displayName
                    : p.basename(j.folderPath);
              }
              final leaf = p.basename(File(j.currentFilePath!).parent.path);
              if (p.equals(
                  File(j.currentFilePath!).parent.path, j.folderPath)) {
                return j.displayName.isNotEmpty
                    ? j.displayName
                    : p.basename(j.folderPath);
              }
              final root = j.displayName.isNotEmpty
                  ? j.displayName
                  : p.basename(j.folderPath);
              return '$root > $leaf';
            }

            final name = composedName(job);
            final sizePct = job.totalBytes == 0
                ? 0
                : ((job.processedBytes / job.totalBytes) * 100)
                    .clamp(0, 100)
                    .toDouble();

            return Card(
              child: ExpansionTile(
                leading:
                    Icon(Icons.circle, color: _dotColorFor(job, 0), size: 12),
                title: Text(name),
                subtitle: (job.status != JobStatus.completed)
                    ? Text('${sizePct.toStringAsFixed(1)}%')
                    : null,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _kv('Folder path', FolderJob.getPrettyFolderPath(job.folderPath)),
                  _kv('Completed', '${sizePct.toStringAsFixed(1)}%'),
                  if (job.currentFilePath != null)
                    _kv('Current file',
                        FolderJob.getPrettyFolderPath(job.currentFilePath!)),
                  if (job.errorMessage != null) _kv('Error', job.errorMessage!),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_mgr.isRunning || _mgr.isPaused)
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (_mgr.isPaused) {
                  await _mgr.resume();
                } else {
                  await _mgr.pause();
                }
                if (mounted) setState(() {});
              },
              icon: Icon(_mgr.isPaused ? Icons.play_arrow : Icons.pause),
              label: Text('${_mgr.isPaused ? 'Resume' : 'Pause'} compression'),
            )
          : null,
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                k,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
