import 'dart:io';

class ScanResult {
  final List<File> files;
  final int totalBytes;
  const ScanResult(this.files, this.totalBytes);
}
