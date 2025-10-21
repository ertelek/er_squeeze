import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:path/path.dart' as p;

typedef LogFn = void Function(String);

/// Thin wrapper around FFprobe/FFmpeg for a single-file H.264 + AAC re-encode.
class VideoProcessor {
  VideoProcessor();

  // ---- Logging -------------------------------------------------------------

  void _log(String msg) {
    // print(msg);
  }

  // ---- Utilities -----------------------------------------------------------

  /// Quotes a path safely for the shell invocation FFmpegKit builds internally.
  String _quote(String s) => '"${s.replaceAll('"', r'\"')}"';

  /// Probe average frame rate via FFprobe and return a string FFmpeg accepts
  /// for `-r` (e.g. "30", "29.970"). Falls back to "30" if unknown.
  Future<String> _probeFrameRateString(File input) async {
    final defaultFPS = '30';

    _log('FFprobe: probing media info → ${input.path}');
    try {
      final session = await FFprobeKit.getMediaInformation(input.path);
      final info = session.getMediaInformation();
      if (info == null) return defaultFPS;

      final streams = info.getStreams();
      if (streams == null) return defaultFPS;

      for (final s in streams) {
        if (s.getType() == 'video') {
          final afr =
              s.getAllProperties()?['avg_frame_rate']?.toString() ?? '0/0';
          if (!afr.contains('/')) break;

          final parts = afr.split('/');
          final num = double.tryParse(parts[0]) ?? 0.0;
          final den = double.tryParse(parts[1]) ?? 1.0;
          final fps = den == 0 ? 30.0 : (num / den);
          final value =
              (fps.isFinite && fps > 0) ? fps.toStringAsFixed(3) : defaultFPS;
          return value;
        }
      }
    } catch (e) {
      _log('FFprobe error: $e');
    }
    return defaultFPS;
  }

  // ---- Public API ----------------------------------------------------------

  /// Re-encodes [input] using H.264 (libx264) + AAC into [outputDirPath].
  ///
  /// - If [labelSuffix] is **empty**, the output is written as `<original>.temp`
  ///   with muxer forced to MP4; the caller will later swap it in-place.
  /// - If [labelSuffix] is **non-empty**, the output is written as
  ///   `<stem><suffix>.mp4`.
  ///
  /// Returns the FFmpeg session handle and the actual output path.
  Future<({dynamic session, String outPath})> reencodeH264AacAsync(
    File input, {
    required String outputDirPath,
    required String labelSuffix,
    int targetCrf = 23,
  }) async {
    final fps = await _probeFrameRateString(input);
    final stem = p.basenameWithoutExtension(input.path);

    // Empty suffix → in-place flow using temp file next to source.
    final toTemp = labelSuffix.trim().isEmpty;
    final originalBaseName = p.basename(input.path);
    final outPath = toTemp
        ? p.join(outputDirPath, '$originalBaseName.temp')
        : p.join(outputDirPath, '$stem$labelSuffix.mp4');

    // Build FFmpeg command.
    final cmd = <String>[
      '-y',
      '-i', _quote(input.path),
      // Video
      '-c:v', 'libx264',
      '-preset', 'medium',
      '-crf', targetCrf.toString(),
      '-r', fps,
      '-pix_fmt', 'yuv420p',
      // Audio
      '-c:a', 'aac',
      '-b:a', '128k',
      // Container flags
      '-movflags', '+faststart',
      if (toTemp) ...['-f', 'mp4'], // force MP4 when the suffix is .temp
      _quote(outPath),
    ];

    _log('FFmpeg: ${cmd.join(' ')}');
    final session = await FFmpegKit.executeAsync(cmd.join(' '));
    return (session: session, outPath: outPath);
  }
}
