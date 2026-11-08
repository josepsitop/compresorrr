import 'dart:io';

import 'package:path/path.dart' as p;

/// Herramientas externas de la versión PC (FFmpeg con NVENC, Ghostscript, 7-Zip).
/// En Android no se usa: ahí todo va con ffmpeg_kit.
class Tools {
  static bool get isPc => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static String ffmpeg = 'ffmpeg';
  static String ffprobe = 'ffprobe';
  static String? gs;
  static String? sevenZip;
  static bool nvenc = false;
  static bool svtav1 = false;
  static bool vmaf = false;

  static Future<void>? _init;
  static Future<void> init() => _init ??= _doInit();

  static Future<void> _doInit() async {
    if (!isPc) return;
    try {
      final base = p.join(File(Platform.resolvedExecutable).parent.path, 'tools');
      String? pick(String rel) {
        final f = p.join(base, rel);
        return File(f).existsSync() ? f : null;
      }

      ffmpeg = pick('ffmpeg.exe') ?? ffmpeg;
      ffprobe = pick('ffprobe.exe') ?? ffprobe;
      gs = pick(p.join('gs', 'bin', 'gswin64c.exe')) ?? await _which('gswin64c');
      sevenZip = pick('7z.exe') ?? await _which('7z');

      final enc = await Process.run(ffmpeg, ['-hide_banner', '-encoders']);
      final out = '${enc.stdout}';
      svtav1 = out.contains('libsvtav1');
      final fl = await Process.run(ffmpeg, ['-hide_banner', '-filters']);
      vmaf = '${fl.stdout}'.contains('libvmaf');
      if (out.contains('hevc_nvenc')) nvenc = await _testNvenc();
    } catch (_) {}
  }

  static Future<String?> _which(String name) async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [name]);
      if (r.exitCode != 0) return null;
      final line = '${r.stdout}'.split('\n').first.trim();
      return line.isEmpty ? null : line;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _testNvenc() async {
    try {
      final r = await Process.run(ffmpeg, [
        '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
        'color=c=black:s=256x256:d=0.2', '-c:v', 'hevc_nvenc', '-f', 'null', '-',
      ]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
