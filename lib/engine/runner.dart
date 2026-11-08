import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'models.dart';
import 'tools.dart';

/// Misma interfaz para Android (ffmpeg_kit) y PC (ffmpeg.exe con NVENC).
abstract class FfRunner {
  Future<Probe> probe(String path);
  Future<FfResult> run(List<String> args, {double? totalSeconds, void Function(double f)? onProgress});

  /// Ejecuta FFmpeg y devuelve todo su texto de salida (solo PC; en Android devuelve '').
  Future<String> capture(List<String> args);
  Future<void> cancel();
}

FfRunner createRunner() => Platform.isAndroid ? AndroidRunner() : DesktopRunner();

class AndroidRunner implements FfRunner {
  @override
  Future<Probe> probe(String path) async {
    try {
      final s = await FFprobeKit.getMediaInformation(path);
      final info = s.getMediaInformation();
      final d = double.tryParse(info?.getDuration() ?? '') ?? 0;
      final b = int.tryParse(info?.getBitrate() ?? '') ?? 0;
      var w = 0, h = 0;
      var vc = '';
      var audio = false;
      for (final st in info?.getStreams() ?? []) {
        final t = st.getType();
        if (t == 'video' && w == 0) {
          w = (st.getWidth() ?? 0).toInt();
          h = (st.getHeight() ?? 0).toInt();
          vc = st.getCodec() ?? '';
        }
        if (t == 'audio') audio = true;
      }
      return Probe(d, b, width: w, height: h, vcodec: vc, hasAudio: audio);
    } catch (_) {
      return const Probe(0, 0);
    }
  }

  @override
  Future<FfResult> run(List<String> args, {double? totalSeconds, void Function(double f)? onProgress}) {
    final done = Completer<FfResult>();
    final tail = <String>[];
    FFmpegKit.executeWithArgumentsAsync(
      ['-hide_banner', '-loglevel', 'error', ...args],
      (session) async {
        final rc = await session.getReturnCode();
        done.complete(FfResult(ReturnCode.isSuccess(rc), ReturnCode.isCancel(rc), tail.join('\n')));
      },
      (log) {
        final m = log.getMessage().trim();
        if (m.isEmpty) return;
        tail.add(m);
        if (tail.length > 12) tail.removeAt(0);
      },
      (stats) {
        if (totalSeconds == null || totalSeconds <= 0) return;
        final ms = stats.getTime().toDouble();
        onProgress?.call((ms / 1000 / totalSeconds).clamp(0.0, 1.0).toDouble());
      },
    );
    return done.future;
  }

  @override
  Future<String> capture(List<String> args) async => '';

  @override
  Future<void> cancel() async {
    try {
      await FFmpegKit.cancel();
    } catch (_) {}
  }
}

class DesktopRunner implements FfRunner {
  Process? _p;
  bool _killed = false;

  @override
  Future<Probe> probe(String path) async {
    try {
      final r = await Process.run(Tools.ffprobe, [
        '-v', 'error',
        '-show_entries', 'format=duration,bit_rate:stream=codec_type,codec_name,width,height',
        '-of', 'json', path,
      ]);
      final j = jsonDecode('${r.stdout}') as Map<String, dynamic>;
      final f = (j['format'] as Map?) ?? {};
      final d = double.tryParse('${f['duration']}') ?? 0;
      final b = int.tryParse('${f['bit_rate']}') ?? 0;
      var w = 0, h = 0;
      var vc = '';
      var audio = false;
      for (final s in (j['streams'] as List?) ?? []) {
        final m = s as Map;
        if (m['codec_type'] == 'video' && w == 0) {
          w = (m['width'] as num?)?.toInt() ?? 0;
          h = (m['height'] as num?)?.toInt() ?? 0;
          vc = '${m['codec_name'] ?? ''}';
        }
        if (m['codec_type'] == 'audio') audio = true;
      }
      return Probe(d, b, width: w, height: h, vcodec: vc, hasAudio: audio);
    } catch (_) {
      return const Probe(0, 0);
    }
  }

  @override
  Future<FfResult> run(List<String> args, {double? totalSeconds, void Function(double f)? onProgress}) async {
    _killed = false;
    final pr = await Process.start(Tools.ffmpeg, [
      '-nostdin', '-hide_banner', '-loglevel', 'error', '-progress', 'pipe:1', '-nostats', ...args,
    ]);
    _p = pr;
    final err = StringBuffer();
    pr.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      if (totalSeconds == null || totalSeconds <= 0) return;
      if (l.startsWith('out_time_us=') || l.startsWith('out_time_ms=')) {
        final v = int.tryParse(l.substring(l.indexOf('=') + 1));
        if (v != null && v >= 0) {
          onProgress?.call((v / 1e6 / totalSeconds).clamp(0.0, 1.0).toDouble());
        }
      }
    });
    pr.stderr.transform(utf8.decoder).listen(err.write);
    final code = await pr.exitCode;
    _p = null;
    final lines = err.toString().trim().split('\n');
    final tail = lines.length > 12 ? lines.sublist(lines.length - 12) : lines;
    return FfResult(code == 0, _killed, tail.join('\n'));
  }

  @override
  Future<String> capture(List<String> args) async {
    try {
      final r = await Process.run(Tools.ffmpeg, ['-hide_banner', '-nostdin', ...args]);
      return '${r.stderr}\n${r.stdout}';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> cancel() async {
    _killed = true;
    _p?.kill();
  }
}
