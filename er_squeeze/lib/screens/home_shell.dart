import 'package:flutter/material.dart';
import 'status_tab.dart';
import 'settings_tab.dart';
import 'about_tab.dart';
import '../services/storage.dart';
import '../services/compression_manager.dart';
import '../models/job_status.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int? _index; // null = deciding
  final _storage = StorageService();
  final _mgr = CompressionManager();
  final _statusKey = GlobalKey<StatusTabState>(); // ⬅️ updated type

  @override
  void initState() {
    super.initState();
    _decideInitialTab();
    _autoResumeIfNeeded();
  }

  Future<void> _autoResumeIfNeeded() async {
    final jobs = await _storage.loadJobs();
    final anyInProgress =
        jobs.values.any((j) => j.status == JobStatus.inProgress);
    if (anyInProgress && !_mgr.isRunning) {
      // ignore: unawaited_futures
      _mgr.start();
    }
  }

  Future<void> _decideInitialTab() async {
    // If a run is already active, go to Status.
    if (_mgr.isRunning) {
      setState(() => _index = 0);
      _statusKey.currentState?.refreshJobs();
      return;
    }

    // Otherwise check selected folders in persisted options.
    final opts = await _storage.loadOptions();
    final selected =
        (opts['selectedFolders'] as List?)?.cast<String>() ?? const <String>[];
    setState(() => _index = selected.isEmpty ? 1 : 0); // 1=Settings, 0=Status
  }

  void _goToStatusTab() {
    setState(() => _index = 0);
    _statusKey.currentState?.refreshJobs();
  }

  @override
  Widget build(BuildContext context) {
    if (_index == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _index!,
        children: [
          StatusTab(key: _statusKey), // ⬅️ updated class
          SettingsTab(
              goToStatusTab: _goToStatusTab), // switch to Status after Start
          const AboutTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index!,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 0) {
            _statusKey.currentState?.refreshJobs();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Status',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: 'About',
          ),
        ],
      ),
    );
  }
}
