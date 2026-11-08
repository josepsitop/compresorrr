import 'dart:math';

import 'models.dart';

String videoExt(Options o) {
  final av1 = o.preset.id == 'av1' || (o.preset.id == 'custom' && o.codec == 'av1');
  return (av1 && o.container == 'mov') ? 'mkv' : o.container;
}

/// Devuelve una lista de intentos: si el primero falla (p. ej. no hay NVENC o
/// MediaCodec), se prueba el siguiente.
List<List<String>> videoAttempts(
  String input,
  String out,
  Probe pr,
  Options o, {
  required bool pc,
  required bool nvenc,
  double? ss,
  double? t,
}) {
  final id = o.preset.id;
  final cont = out.split('.').last.toLowerCase();
  final apple = cont == 'mp4' || cont == 'mov';
  final tag = apple ? ['-tag:v', 'hvc1'] : <String>[];
  final custom = id == 'custom';
  final height = id == 'social' ? 720 : (custom ? o.height : 0);
  final audio = id == 'social' ? 96 : (custom ? o.audio : 128);

  List<String> x265(String preset, int crf, {String extra = ''}) => [
        '-c:v', 'libx265', '-preset', preset, '-crf', '$crf',
        '-x265-params', 'log-level=error${extra.isEmpty ? '' : ':$extra'}',
        '-pix_fmt', 'yuv420p', ...tag,
      ];
  List<String> x264(String preset, int crf) => [
        '-c:v', 'libx264', '-preset', preset, '-crf', '$crf',
        '-profile:v', 'high', '-pix_fmt', 'yuv420p',
      ];
  List<String> av1(int crf) => ['-c:v', 'libsvtav1', '-preset', '5', '-crf', '$crf', '-pix_fmt', 'yuv420p'];

  final List<List<String>> vcodecs;
  if (id == 'hw') {
    if (pc && nvenc) {
      vcodecs = [
        [
          '-c:v', 'hevc_nvenc', '-preset', 'p7', '-tune', 'hq', '-rc', 'vbr', '-cq', '27',
          '-b:v', '0', '-spatial-aq', '1', '-temporal-aq', '1', '-rc-lookahead', '32',
          '-multipass', 'fullres', '-pix_fmt', 'yuv420p', ...tag,
        ],
        x265('medium', 25),
      ];
    } else if (pc) {
      vcodecs = [x265('medium', 25)];
    } else {
      final kb = pr.bitrate > 0 ? ((pr.bitrate * 0.45) / 1000).round().clamp(700, 14000) : 4000;
      vcodecs = [
        ['-c:v', 'hevc_mediacodec', '-b:v', '${kb}k', '-pix_fmt', 'nv12', ...tag],
        x265('veryfast', 27),
      ];
    }
  } else if (id == 'balanced') {
    vcodecs = [x265(pc ? 'medium' : 'veryfast', pc ? 25 : 26)];
  } else if (id == 'visual') {
    vcodecs = [x265(pc ? 'slow' : 'faster', 20)];
  } else if (id == 'max') {
    vcodecs = [x265(pc ? 'slow' : 'fast', 28, extra: 'aq-mode=3')];
  } else if (id == 'social') {
    vcodecs = [x265(pc ? 'medium' : 'veryfast', 29)];
  } else if (id == 'compat') {
    vcodecs = [x264(pc ? 'slow' : 'veryfast', pc ? 22 : 24)];
  } else if (id == 'av1') {
    vcodecs = [av1(32)];
  } else {
    final crf = o.crf.round();
    if (o.codec == 'h264') {
      vcodecs = [x264(pc ? 'slow' : 'veryfast', crf)];
    } else if (o.codec == 'av1') {
      vcodecs = [av1(min(63, crf + 6))];
    } else {
      vcodecs = [x265(pc ? 'medium' : 'veryfast', crf)];
    }
  }

  final vf = height > 0 ? ['-vf', "scale=-2:'min($height,ih)'"] : <String>[];
  final au = audio == 0 ? ['-c:a', 'copy'] : ['-c:a', 'aac', '-b:a', '${audio}k'];
  final fin = apple ? ['-movflags', '+faststart'] : <String>[];

  return [
    for (final vc in vcodecs)
      [
        '-y',
        if (ss != null) ...['-ss', ss.toStringAsFixed(2)],
        if (t != null) ...['-t', t.toStringAsFixed(2)],
        '-i', input,
        '-map', '0:v:0', '-map', '0:a?', '-sn', '-dn', '-map_metadata', '0',
        ...vf, ...vc, ...au, ...fin, out,
      ],
  ];
}

String photoExt(Options o) {
  switch (o.preset.id) {
    case 'p_jpg':
      return 'jpg';
    case 'custom':
      return o.imgFormat;
    default:
      return 'webp';
  }
}

List<String> photoArgs(String input, String out, Options o) {
  final id = o.preset.id;
  var side = 0;
  var q = 80;
  var lossless = false;
  var fmt = 'webp';
  switch (id) {
    case 'p_web':
      q = 85;
      break;
    case 'p_jpg':
      fmt = 'jpg';
      q = 90;
      break;
    case 'p_bal':
      side = 2560;
      q = 80;
      break;
    case 'p_min':
      side = 1600;
      q = 70;
      break;
    case 'p_lossless':
      lossless = true;
      break;
    default:
      side = o.maxSide;
      q = o.quality;
      fmt = o.imgFormat;
  }
  final vf = side > 0
      ? ['-vf', "scale=w='min($side,iw)':h='min($side,ih)':force_original_aspect_ratio=decrease"]
      : <String>[];
  final codec = fmt == 'jpg'
      ? ['-c:v', 'mjpeg', '-q:v', '${((100 - q) * 0.31).round().clamp(2, 31)}', '-pix_fmt', 'yuvj420p']
      : [
          '-c:v', 'libwebp', '-quality', '$q', '-compression_level', '6',
          if (lossless) ...['-lossless', '1'],
        ];
  return ['-y', '-i', input, ...vf, '-frames:v', '1', ...codec, out];
}
