import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/folder_job.dart';

/// Simple JSON file storage to persist state across sessions.
class StorageService {
  static final StorageService _i = StorageService._();
  StorageService._();
  factory StorageService() => _i;

  File? _file;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/jobs_state.json');
    if (!await f.exists()) {
      await f.writeAsString(jsonEncode({
        'jobs': <String, dynamic>{},
        'options': {
          'suffix': '',
          'keepOriginal': false,
          'selectedFolders': <String>[],
        }
      }));
    }
    _file = f;
    return f;
  }

  Future<Map<String, dynamic>> readAll() async {
    final f = await _ensureFile();
    final s = await f.readAsString();
    return jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> writeAll(Map<String, dynamic> data) async {
    final f = await _ensureFile();
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
  }

  Future<Map<String, FolderJob>> loadJobs() async {
    final m = await readAll();
    final raw = (m['jobs'] ?? {}) as Map<String, dynamic>;
    final out = <String, FolderJob>{};
    for (final e in raw.entries) {
      out[e.key] = FolderJob.fromMap(Map<String, dynamic>.from(e.value));
    }
    return out;
  }

  Future<void> saveJobs(Map<String, FolderJob> jobs) async {
    final m = await readAll();
    m['jobs'] = {for (final e in jobs.entries) e.key: e.value.toMap()};
    await writeAll(m);
  }

  Future<Map<String, dynamic>> loadOptions() async {
    final m = await readAll();
    return Map<String, dynamic>.from(m['options'] ?? {});
  }

  Future<void> saveOptions(
      {String? suffix,
      bool? keepOriginal,
      List<String>? selectedFolders}) async {
    final m = await readAll();
    final o = Map<String, dynamic>.from(m['options'] ?? {});
    if (suffix != null) o['suffix'] = suffix;
    if (keepOriginal != null) o['keepOriginal'] = keepOriginal;
    if (selectedFolders != null) o['selectedFolders'] = selectedFolders;
    m['options'] = o;
    await writeAll(m);
  }
}
