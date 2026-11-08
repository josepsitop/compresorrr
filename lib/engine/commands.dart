import 'dart:math';

import 'models.dart';

class _Base {
  const _Base(this.crf, this.pc, this.mob, [this.codec = 'hevc', this.extra = '']);
  final int crf; // en escala HEVC
  final String pc, mob, codec, extra;
}

const _bases = <String, _Base>{
  'hw': _Base(25, 'medium', 'veryfast'),
  'balanced': _Base(25, 'medium', 'veryfast'),
  'visual': _Base(20, 'slow', 'faster'),
  'max': _Base(28, 'slow', 'fast', 'hevc', 'aq-mode=3'),
  'social': _Base(29, 'medium', 'veryfast'),
  'compat': _Base(26, 'slow', 'veryfast', 'h264'),
  'av1': _Base(27, 'slow', 'fast', 'av1'),
};

/// Códec que se usará: el que elija la persona o, en "auto", el propio del modo.
String effectiveCodec(Options o) {
  final base = o.preset.id == 'custom' ? 'hevc' : (_bases[o.preset.id]?.codec ?? 'hevc');
  return o.codec == 'auto' ? base : o.codec;
}

String videoExt(Options o) {
  if (o.audioOnly) return o.audioFormat;
  return (effectiveCodec(o) == 'av1' && o.container == 'mov') ? 'mkv' : o.container;
}

List<String> audioArgs(String input, String out, Options o, double? ss, double? t) {
  final k = o.audio == 0 ? 128 : o.audio;
  return [
    '-y',
    if (ss != null) ...['-ss', ss.toStringAsFixed(2)],
    if (t != null) ...['-t', t.toStringAsFixed(2)],
    '-i', input, '-vn', '-map', '0:a:0',
    ...(o.audioFormat == 'mp3'
        ? ['-c:a', 'libmp3lame', '-b:a', '${k}k']
        : ['-c:a', 'aac', '-b:a', '${k}k']),
    if (o.stripMeta) ...['-map_metadata', '-1'],
    out,
  ];
}

/// Lista de intentos: si el primero falla (sin NVENC/MediaCodec) se prueba el siguiente.
/// [kbps] != null => modo "peso objetivo" (bitrate fijo en lugar de calidad CRF).
List<List<String>> videoAttempts(
  String input,
  String out,
  Probe pr,
  Options o, {
  required bool pc,
  required bool nvenc,
  double? ss,
  double? t,
  int? kbps,
}) {
  if (o.audioOnly) return [audioArgs(input, out, o, ss, t)];

  final id = o.preset.id;
  final base = id == 'custom'
      ? _Base(o.crf.round(), 'medium', 'veryfast')
      : (_bases[id] ?? _bases['balanced']!);
  final codec = effectiveCodec(o);
  final crf = o.crfOverride ?? base.crf;
  final speed = pc ? base.pc : base.mob;
  final cont = out.split('.').last.toLowerCase();
  final apple = cont == 'mp4' || cont == 'mov';
  final hvc = (apple && codec == 'hevc') ? ['-tag:v', 'hvc1'] : <String>[];

  List<String> rate(int k) => ['-b:v', '${k}k', '-maxrate', '${(k * 1.3).round()}k', '-bufsize', '${k * 2}k'];

  List<String> software() {
    if (codec == 'h264') {
      return [
        '-c:v', 'libx264', '-preset', speed,
        ...(kbps != null ? rate(kbps) : ['-crf', '${max(14, min(35, crf - 5))}']),
        '-profile:v', 'high', '-pix_fmt', 'yuv420p',
      ];
    }
    if (codec == 'av1') {
      final svt = speed == 'slow' ? '5' : (speed == 'medium' ? '6' : '8');
      return [
        '-c:v', 'libsvtav1', '-preset', svt,
        ...(kbps != null ? rate(kbps) : ['-crf', '${min(63, crf + 5)}']),
        '-pix_fmt', 'yuv420p',
      ];
    }
    return [
      '-c:v', 'libx265', '-preset', speed,
      ...(kbps != null ? rate(kbps) : ['-crf', '$crf']),
      '-x265-params', 'log-level=error${base.extra.isEmpty ? '' : ':${base.extra}'}',
      '-pix_fmt', 'yuv420p', ...hvc,
    ];
  }

  List<String>? hardware() {
    if (id != 'hw' || codec == 'av1') return null;
    if (pc && nvenc) {
      final q = codec == 'h264' ? crf - 3 : crf + 2;
      return [
        '-c:v', codec == 'h264' ? 'h264_nvenc' : 'hevc_nvenc',
        '-preset', 'p7', '-tune', 'hq', '-rc', 'vbr',
        ...(kbps != null
            ? ['-b:v', '${kbps}k', '-maxrate', '${(kbps * 1.3).round()}k']
            : ['-cq', '$q', '-b:v', '0']),
        '-spatial-aq', '1', '-temporal-aq', '1', '-rc-lookahead', '32',
        '-multipass', 'fullres', '-pix_fmt', 'yuv420p', ...hvc,
      ];
    }
    if (!pc) {
      final k = kbps ??
          (pr.bitrate > 0
              ? max(700, min(14000, ((pr.bitrate * (codec == 'h264' ? .6 : .45)) / 1000).round()))
              : 4000);
      return ['-c:v', codec == 'h264' ? 'h264_mediacodec' : 'hevc_mediacodec', '-b:v', '${k}k', '-pix_fmt', 'nv12', ...hvc];
    }
    return null;
  }

  final encoders = <List<String>>[
    if (hardware() != null) hardware()!,
    software(),
  ];

  final vfs = <String>[
    if (o.denoise == 'soft') 'hqdn3d=2:1.5:3:2.5',
    if (o.denoise == 'strong') 'hqdn3d=4:3:6:4.5',
    if (o.height > 0) "scale=-2:'min(${o.height},ih)'",
  ];
  final vf = vfs.isEmpty ? <String>[] : ['-vf', vfs.join(',')];
  final au = o.noAudio
      ? ['-an']
      : (o.audio == 0 ? ['-c:a', 'copy'] : ['-c:a', 'aac', '-b:a', '${o.audio}k']);
  final meta = o.stripMeta ? ['-map_metadata', '-1', '-map_chapters', '-1'] : ['-map_metadata', '0'];
  final fin = apple ? ['-movflags', '+faststart'] : <String>[];

  return [
    for (final enc in encoders)
      [
        '-y',
        if (ss != null) ...['-ss', ss.toStringAsFixed(2)],
        if (t != null) ...['-t', t.toStringAsFixed(2)],
        '-i', input,
        '-map', '0:v:0', if (!o.noAudio) ...['-map', '0:a?'], '-sn', '-dn',
        ...meta, ...vf, ...enc, ...au, ...fin, out,
      ],
  ];
}

// ------------------------------------------------------------------- fotos
String photoExt(Options o) {
  if (o.imgFormat != 'auto') return o.imgFormat;
  return o.preset.id == 'p_jpg' ? 'jpg' : 'webp';
}

int photoBaseQuality(Options o) {
  switch (o.preset.id) {
    case 'p_web':
      return 85;
    case 'p_jpg':
      return 90;
    case 'p_bal':
      return 80;
    case 'p_min':
      return 70;
    case 'p_lossless':
      return 85;
    default:
      return o.quality;
  }
}

int photoSide(Options o) {
  switch (o.preset.id) {
    case 'p_bal':
      return 2560;
    case 'p_min':
      return 1600;
    case 'custom':
      return o.maxSide;
    default:
      return 0;
  }
}

/// [qOverride]/[shrink] los usa el modo "peso objetivo" para probar calidades menores.
List<String> photoArgs(String input, String out, Options o, {int? qOverride, double shrink = 1.0}) {
  final side = photoSide(o);
  final q = qOverride ?? photoBaseQuality(o);
  final lossless = o.preset.id == 'p_lossless' && qOverride == null;
  final jpg = photoExt(o) == 'jpg';
  final filters = <String>[
    if (side > 0)
      "scale=w='min($side,iw)':h='min($side,ih)':force_original_aspect_ratio=decrease",
    if (shrink < 1) "scale='trunc(iw*$shrink/2)*2':'trunc(ih*$shrink/2)*2'",
  ];
  final vf = filters.isEmpty ? <String>[] : ['-vf', filters.join(',')];
  final codec = jpg
      ? ['-c:v', 'mjpeg', '-q:v', '${max(2, min(31, ((100 - q) * 0.31).round()))}', '-pix_fmt', 'yuvj420p']
      : [
          '-c:v', 'libwebp', '-quality', '$q', '-compression_level', '6',
          if (lossless) ...['-lossless', '1'],
        ];
  return ['-y', '-i', input, ...vf, '-map_metadata', '-1', '-frames:v', '1', ...codec, out];
}
