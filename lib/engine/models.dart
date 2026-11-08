import 'package:path/path.dart' as p;

enum Kind { photo, video, file }

typedef Progress = void Function(double? fraction, String message);

const videoExts = {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', '3gp', 'ts', 'mts', 'm2ts', 'wmv', 'flv', 'mpg', 'mpeg'};
const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'tif', 'tiff', 'heic', 'heif'};
const packedExts = {
  'jpg', 'jpeg', 'png', 'webp', 'mp4', 'mkv', 'mov', 'mp3', 'm4a', 'zip', 'rar', '7z', 'gz', 'docx', 'xlsx', 'pptx', 'apk',
};

class Item {
  const Item(this.path, this.name, this.bytes);
  final String path;
  final String name;
  final int bytes;
  String get ext => p.extension(name).replaceFirst('.', '').toLowerCase();
  bool get isPdf => ext == 'pdf';
  bool get isPacked => packedExts.contains(ext);
  Kind get guessKind =>
      videoExts.contains(ext) ? Kind.video : (imageExts.contains(ext) ? Kind.photo : Kind.file);
}

class Probe {
  const Probe(this.duration, this.bitrate,
      {this.width = 0, this.height = 0, this.vcodec = '', this.hasAudio = true});
  final double duration; // segundos
  final int bitrate; // bits por segundo
  final int width;
  final int height;
  final String vcodec;
  final bool hasAudio;

  /// Bits por píxel y por segundo: mide qué tan comprimido viene el video.
  double get bpps => (width > 0 && height > 0 && bitrate > 0) ? bitrate / (width * height) : 0;
}

class FfResult {
  const FfResult(this.ok, this.cancelled, this.log);
  final bool ok;
  final bool cancelled;
  final String log;
}

class Preset {
  const Preset({
    required this.id,
    required this.kind,
    required this.name,
    required this.tagline,
    required this.explain,
    required this.versus,
    required this.savings,
    required this.speed,
    required this.quality,
    this.group,
    this.pcOnly = false,
    this.needs,
    this.recommended = false,
  });
  final String id;
  final Kind kind;
  final String name;
  final String tagline;
  final String explain;
  final String versus;
  final String savings;
  final int speed; // 1..5
  final int quality; // 1..5
  final String? group; // 'pdf' | 'generic'
  final bool pcOnly;
  final String? needs; // 'gs' | '7z' | 'svtav1'
  final bool recommended;
}

class Options {
  Options(this.preset);
  Preset preset;

  // --- video
  String container = 'mp4';
  String codec = 'auto'; // auto | hevc | h264 | av1
  double crf = 26; // solo "Personalizado" (escala HEVC)
  int height = 0; // 0 = original
  int audio = 128; // kbps, 0 = copiar
  int targetMB = 0; // 0 = sin peso objetivo
  bool auto = false; // calidad automática (VMAF, solo PC)
  int vmaf = 95;
  bool stripMeta = false;
  bool noAudio = false;
  bool audioOnly = false;
  String audioFormat = 'm4a';
  String denoise = 'off'; // off | soft | strong
  double trimStart = 0;
  double trimEnd = 0; // 0 = hasta el final
  int? crfOverride; // lo rellena la calidad automática
  bool onlyCharging = false; // solo Android

  // --- foto
  int quality = 80;
  int maxSide = 0;
  String imgFormat = 'auto'; // auto | webp | jpg
  int targetKB = 0;

  // --- archivos
  String password = '';

  Options copy() {
    final o = Options(preset);
    o.container = container;
    o.codec = codec;
    o.crf = crf;
    o.height = height;
    o.audio = audio;
    o.targetMB = targetMB;
    o.auto = auto;
    o.vmaf = vmaf;
    o.stripMeta = stripMeta;
    o.noAudio = noAudio;
    o.audioOnly = audioOnly;
    o.audioFormat = audioFormat;
    o.denoise = denoise;
    o.trimStart = trimStart;
    o.trimEnd = trimEnd;
    o.crfOverride = crfOverride;
    o.onlyCharging = onlyCharging;
    o.quality = quality;
    o.maxSide = maxSide;
    o.imgFormat = imgFormat;
    o.targetKB = targetKB;
    o.password = password;
    return o;
  }
}

class Outcome {
  Outcome(this.item,
      {this.path, this.outBytes = 0, this.error, this.note, this.sampleSeconds, this.sampleStart});
  final Item item;
  final String? path;
  final String? error;
  final String? note;
  final int outBytes;
  final double? sampleSeconds;
  final double? sampleStart;
  int get inBytes => item.bytes;
  bool get ok => error == null && path != null;
  double get saved => inBytes == 0 ? 0 : 1 - outBytes / inBytes;
}

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${u[i]}';
}

String fmtDur(double s) {
  final t = s.round();
  final h = t ~/ 3600;
  final m = (t % 3600) ~/ 60;
  final sec = t % 60;
  if (h > 0) return '$h h $m min';
  if (m > 0) return '$m min $sec s';
  return '$sec s';
}

String fmtClock(double s) {
  final t = s.round();
  final m = t ~/ 60;
  final sec = t % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}
