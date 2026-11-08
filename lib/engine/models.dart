import 'package:path/path.dart' as p;

enum Kind { photo, video, file }

typedef Progress = void Function(double? fraction, String message);

class Item {
  const Item(this.path, this.name, this.bytes);
  final String path;
  final String name;
  final int bytes;
  String get ext => p.extension(name).replaceFirst('.', '').toLowerCase();
  bool get isPdf => ext == 'pdf';
}

class Probe {
  const Probe(this.duration, this.bitrate);
  final double duration; // segundos
  final int bitrate; // bits por segundo
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
  String container = 'mp4';
  // personalizado (video)
  double crf = 26;
  int height = 0; // 0 = original
  int audio = 128; // 0 = copiar
  String codec = 'hevc';
  // personalizado (foto)
  int quality = 80;
  int maxSide = 0;
  String imgFormat = 'webp';
}

class Outcome {
  Outcome(this.item, {this.path, this.outBytes = 0, this.error, this.note, this.sampleSeconds});
  final Item item;
  final String? path;
  final String? error;
  final String? note;
  final int outBytes;
  final double? sampleSeconds;
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
