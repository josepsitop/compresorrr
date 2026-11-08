import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'commands.dart';
import 'models.dart';
import 'runner.dart';
import 'tools.dart';

Uint8List _rgbaToJpeg(Uint8List rgba, int w, int h, int quality) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = rgba[i + 3];
      int c(int v) => (v * a + 255 * (255 - a)) ~/ 255; // compone sobre blanco
      im.setPixelRgb(x, y, c(rgba[i]), c(rgba[i + 1]), c(rgba[i + 2]));
      i += 4;
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: quality));
}

class Compressor {
  final FfRunner ff = createRunner();
  bool _cancelled = false;
  Process? _proc;
  final _autoCache = <String, int>{};

  Future<void> cancel() async {
    _cancelled = true;
    await ff.cancel();
    _proc?.kill();
  }

  // ------------------------------------------------------------ carpetas
  static Future<String> tmpDir() async {
    final d = Directory(p.join((await getTemporaryDirectory()).path, 'squeeze_out'));
    await d.create(recursive: true);
    return d.path;
  }

  /// Borra temporales viejos (más de un día) de resultados y copias de "Compartir".
  static Future<void> cleanTemp({bool everything = false}) async {
    try {
      final root = (await getTemporaryDirectory()).path;
      final limit = DateTime.now().subtract(const Duration(days: 1));
      for (final name in ['squeeze_out', 'shared', 'file_picker']) {
        final d = Directory(p.join(root, name));
        if (!await d.exists()) continue;
        await for (final e in d.list()) {
          try {
            if (everything || (await e.stat()).modified.isBefore(limit)) {
              await e.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<int> tempBytes() async {
    var total = 0;
    try {
      final root = (await getTemporaryDirectory()).path;
      for (final name in ['squeeze_out', 'shared', 'file_picker']) {
        final d = Directory(p.join(root, name));
        if (!await d.exists()) continue;
        await for (final e in d.list(recursive: true)) {
          if (e is File) total += await e.length();
        }
      }
    } catch (_) {}
    return total;
  }

  Future<String> _outDir(Item it) async => Platform.isAndroid ? tmpDir() : p.dirname(it.path);

  Future<String> _unique(String dir, String base, String ext) async {
    var path = p.join(dir, '$base.$ext');
    var i = 2;
    while (await File(path).exists()) {
      path = p.join(dir, '${base}_$i.$ext');
      i++;
    }
    return path;
  }

  Future<void> _rm(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ----------------------------------------------------------- principal
  /// [sample] != null => solo procesa ese porcentaje del video (vista previa).
  Future<Outcome> run(Item it, Options o0,
      {double? sample, Progress? onProgress, String? outDirOverride}) async {
    _cancelled = false;
    final o = o0.copy();
    try {
      final dir = sample != null ? await tmpDir() : (outDirOverride ?? await _outDir(it));
      final k = o.preset.kind;
      Outcome r;
      if (k == Kind.video) {
        r = await _video(it, o, dir, sample, onProgress);
      } else if (k == Kind.photo) {
        r = await _photo(it, o, dir, onProgress);
      } else if (o.preset.group == 'pdf') {
        r = await _pdf(it, o, dir, onProgress);
      } else {
        r = await _archive(it, o, dir, onProgress);
      }
      if (_cancelled && !r.ok) return Outcome(it, error: 'Cancelado');
      return r;
    } catch (e) {
      return Outcome(it, error: '$e');
    }
  }

  Future<Outcome> _done(Item it, String out,
      {bool sample = false, double? secs, double? start, String? note}) async {
    final size = await File(out).length();
    if (!sample && size >= it.bytes) {
      await _rm(out);
      return Outcome(it,
          note: 'Este archivo ya estaba muy optimizado: el resultado pesaba igual o más, así que no se guardó.');
    }
    return Outcome(it, path: out, outBytes: size, sampleSeconds: secs, sampleStart: start, note: note);
  }

  /// Extrae un fotograma (para el comparador antes/después de video).
  Future<String?> frame(String path, double at, String tag) async {
    final out = p.join(await tmpDir(), '${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg');
    final r = await ff.run(['-y', '-ss', at.toStringAsFixed(2), '-i', path, '-frames:v', '1', '-q:v', '2', out]);
    return r.ok ? out : null;
  }

  // ----------------------------------------------------------------- video
  Future<Outcome> _video(Item it, Options o, String dir, double? sample, Progress? cb) async {
    cb?.call(null, 'Leyendo el video…');
    final pr = await ff.probe(it.path);
    if (o.audioOnly && !pr.hasAudio && pr.duration > 0) {
      return Outcome(it, error: 'Este video no tiene pista de audio.');
    }

    // Rango de trabajo (recorte) y, si es vista previa, un trozo del medio.
    final dur = pr.duration;
    final a = dur > 0 ? max(0.0, min(o.trimStart, dur)) : 0.0;
    var b = dur > 0 ? (o.trimEnd > 0 ? min(o.trimEnd, dur) : dur) : 0.0;
    if (dur > 0 && b <= a) b = dur;
    final range = dur > 0 ? b - a : 0.0;
    final trimmed = dur > 0 && (a > .01 || b < dur - .01);
    double? ss, t;
    var total = range;
    if (sample != null && range > 0) {
      t = min(range, min(90.0, max(3.0, range * sample)));
      ss = a + max(0.0, (range - t) / 2);
      total = t;
    } else if (trimmed) {
      ss = a;
      t = range;
    }

    // Calidad automática (VMAF, solo PC)
    if (o.auto && Tools.isPc && Tools.vmaf && !o.audioOnly && o.targetMB == 0) {
      final crf = await _autoCrf(it, o, pr, a, range, cb);
      if (_cancelled) return Outcome(it, error: 'Cancelado');
      if (crf != null) o.crfOverride = crf;
    }

    // Peso objetivo: bitrate fijo calculado a partir de la duración.
    int? kbps;
    if (o.targetMB > 0 && range > 0 && !o.audioOnly) {
      final audioK = o.noAudio ? 0 : (o.audio == 0 ? 128 : o.audio);
      kbps = max(150, ((o.targetMB * 1024 * 1024 * 8 * .97) / range / 1000).round() - audioK);
    }

    final stem = p.basenameWithoutExtension(it.name);
    final out = await _unique(dir, sample != null ? '${stem}_muestra' : '${stem}_squeeze', videoExt(o));

    var r = const FfResult(false, false, '');
    for (var round = 0; round < 3; round++) {
      final attempts = videoAttempts(it.path, out, pr, o,
          pc: Tools.isPc, nvenc: Tools.nvenc, ss: ss, t: t, kbps: kbps);
      for (var i = 0; i < attempts.length; i++) {
        cb?.call(0, i == 0 ? 'Comprimiendo…' : 'Reintentando con el modo de respaldo…');
        r = await ff.run(attempts[i], totalSeconds: total, onProgress: (f) {
          cb?.call(f, 'Comprimiendo… ${(f * 100).round()} %');
        });
        if (r.ok || r.cancelled) break;
      }
      if (!r.ok) break;
      if (kbps != null && sample == null) {
        final size = await File(out).length();
        final target = o.targetMB * 1024 * 1024;
        if (size > target * 1.03 && round < 2) {
          kbps = max(100, (kbps * target / size * .96).round());
          cb?.call(0, 'Ajustando para llegar a ${o.targetMB} MB…');
          await _rm(out);
          continue;
        }
      }
      break;
    }
    if (!r.ok) {
      await _rm(out);
      return Outcome(it,
          error: r.cancelled ? 'Cancelado' : (r.log.isNotEmpty ? r.log : 'FFmpeg no pudo procesar este video.'));
    }

    String? note;
    if (kbps != null && sample == null) {
      final size = await File(out).length();
      if (size > o.targetMB * 1024 * 1024 * 1.1) {
        note = 'Quedó en ${fmtBytes(size)}: no se pudo llegar a ${o.targetMB} MB sin arruinar la imagen.';
      }
    }
    if (o.crfOverride != null && o.auto) note = 'Calidad automática elegida: CRF ${o.crfOverride}.';
    return _done(it, out, sample: sample != null || o.audioOnly, secs: t, start: ss, note: note);
  }

  /// Busca el CRF más alto (más compresión) cuyo VMAF siga sobre el objetivo.
  Future<int?> _autoCrf(Item it, Options o, Probe pr, double a, double range, Progress? cb) async {
    if (range <= 0) return null;
    final key = '${it.path}|${o.preset.id}|${effectiveCodec(o)}|${o.vmaf}|${o.height}|${o.denoise}|$a|$range';
    final hit = _autoCache[key];
    if (hit != null) return hit;

    final len = min(range, 20.0);
    final s = a + max(0.0, (range - len) / 2);
    final tmp = await tmpDir();
    var lo = 18, hi = 34;
    int? best;
    double? bestScore;
    for (var i = 0; i < 5 && lo <= hi; i++) {
      final mid = (lo + hi) ~/ 2;
      final po = o.copy()..crfOverride = mid;
      final enc = p.join(tmp, 'auto_${DateTime.now().microsecondsSinceEpoch}.mkv');
      cb?.call(null, 'Buscando la mejor calidad… prueba ${i + 1} de 5 (CRF $mid)');
      var ok = false;
      for (final at in videoAttempts(it.path, enc, pr, po, pc: true, nvenc: Tools.nvenc, ss: s, t: len)) {
        final r = await ff.run(at, totalSeconds: len);
        if (r.cancelled) {
          await _rm(enc);
          return null;
        }
        if (r.ok) {
          ok = true;
          break;
        }
      }
      if (!ok) {
        await _rm(enc);
        return null;
      }
      final score = await _vmaf(enc, it.path, s, len, pr);
      await _rm(enc);
      if (score == null) return null;
      if (score >= o.vmaf) {
        best = mid;
        bestScore = score;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final r = best ?? 18;
    cb?.call(null, 'Calidad elegida: CRF $r${bestScore != null ? ' (VMAF ${bestScore.toStringAsFixed(1)})' : ''}');
    _autoCache[key] = r;
    return r;
  }

  Future<double?> _vmaf(String enc, String src, double ss, double len, Probe pr) async {
    final scale = (pr.width > 0 && pr.height > 0) ? 'scale=${pr.width}:${pr.height}:flags=bicubic,' : '';
    final threads = max(2, Platform.numberOfProcessors ~/ 2);
    final out = await ff.capture([
      '-i', enc,
      '-ss', ss.toStringAsFixed(2), '-t', len.toStringAsFixed(2), '-i', src,
      '-lavfi',
      '[0:v]${scale}setpts=PTS-STARTPTS[d];[1:v]setpts=PTS-STARTPTS[r];[d][r]libvmaf=n_threads=$threads',
      '-an', '-f', 'null', '-',
    ]);
    final m = RegExp(r'VMAF score:\s*([0-9.]+)').firstMatch(out);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  // ------------------------------------------------------------------ foto
  Future<Outcome> _photo(Item it, Options o, String dir, Progress? cb) async {
    cb?.call(null, 'Comprimiendo imagen…');
    final out = await _unique(dir, '${p.basenameWithoutExtension(it.name)}_squeeze', photoExt(o));
    FfResult r;
    String? note;
    if (o.targetKB > 0) {
      final target = o.targetKB * 1024;
      var q = photoBaseQuality(o);
      var shrink = 1.0;
      r = const FfResult(false, false, '');
      for (var i = 0; i < 9; i++) {
        cb?.call(null, 'Ajustando a ${o.targetKB} KB… (intento ${i + 1})');
        r = await ff.run(photoArgs(it.path, out, o, qOverride: q, shrink: shrink));
        if (!r.ok) break;
        if (await File(out).length() <= target) break;
        if (q > 45) {
          q = max(40, q - 15);
        } else {
          shrink *= .8;
        }
      }
      if (r.ok) {
        final size = await File(out).length();
        if (size > target) note = 'Quedó en ${fmtBytes(size)}: no se pudo llegar a ${o.targetKB} KB.';
      }
    } else {
      r = await ff.run(photoArgs(it.path, out, o));
    }
    if (!r.ok) {
      await _rm(out);
      return Outcome(it,
          error: r.cancelled ? 'Cancelado' : (r.log.isNotEmpty ? r.log : 'No se pudo procesar la imagen.'));
    }
    return _done(it, out, note: note);
  }

  // ------------------------------------------------------------------- pdf
  Future<(int, String)> _exec(String exe, List<String> args, {void Function(String s)? onOut}) async {
    final pr = await Process.start(exe, args);
    _proc = pr;
    final err = StringBuffer();
    pr.stdout.transform(utf8.decoder).listen((s) => onOut?.call(s));
    pr.stderr.transform(utf8.decoder).listen(err.write);
    final code = await pr.exitCode;
    _proc = null;
    return (code, err.toString().trim());
  }

  Future<Outcome> _pdf(Item it, Options o, String dir, Progress? cb) async {
    final out = await _unique(dir, '${p.basenameWithoutExtension(it.name)}_squeeze', 'pdf');
    final id = o.preset.id;

    if (id.startsWith('pdf_gs')) {
      cb?.call(null, 'Optimizando PDF con Ghostscript…');
      const modes = {'pdf_gs_print': '/printer', 'pdf_gs_ebook': '/ebook', 'pdf_gs_screen': '/screen'};
      final (code, err) = await _exec(Tools.gs!, [
        '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.6', '-dPDFSETTINGS=${modes[id]}',
        '-dNOPAUSE', '-dBATCH', '-dQUIET', '-dDetectDuplicateImages=true',
        '-dCompressFonts=true', '-dSubsetFonts=true', '-sOutputFile=$out', it.path,
      ]);
      if (code != 0) {
        await _rm(out);
        return Outcome(it, error: err.isEmpty ? 'Ghostscript falló (código $code).' : err);
      }
      return _done(it, out);
    }

    // Modo imagen: funciona en Android y PC.
    const cfg = {'pdf_r_sharp': (150, 70), 'pdf_r_compact': (110, 55), 'pdf_r_min': (80, 45)};
    final (dpi, q) = cfg[id]!;
    final bytes = await File(it.path).readAsBytes();
    final doc = pw.Document(compress: true);
    var n = 0;
    await for (final page in Printing.raster(bytes, dpi: dpi.toDouble())) {
      if (_cancelled) break;
      n++;
      cb?.call(null, 'Procesando página $n…');
      final rgba = page.pixels;
      final w = page.width;
      final h = page.height;
      final jpg = await Isolate.run(() => _rgbaToJpeg(rgba, w, h, q));
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(w * 72.0 / dpi, h * 72.0 / dpi, marginAll: 0),
        build: (_) => pw.FullPage(ignoreMargins: true, child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill)),
      ));
    }
    if (_cancelled) return Outcome(it, error: 'Cancelado');
    if (n == 0) return Outcome(it, error: 'No se pudo leer el PDF (¿tiene contraseña?).');
    await File(out).writeAsBytes(await doc.save());
    return _done(it, out);
  }

  // -------------------------------------------------------------- archivos
  Future<Outcome> _archive(Item it, Options o, String dir, Progress? cb) async {
    final id = o.preset.id;
    if (id == 'f_gz') {
      final out = await _unique(dir, it.name, 'gz');
      var read = 0;
      final total = max(1, it.bytes);
      final sink = File(out).openWrite();
      await File(it.path)
          .openRead()
          .map((c) {
            read += c.length;
            cb?.call(read / total, 'Comprimiendo… ${(read * 100 / total).round()} %');
            return c;
          })
          .transform(GZipCodec(level: 9).encoder)
          .pipe(sink);
      return _done(it, out);
    }
    final zip = id == 'f_zip';
    final out = await _unique(dir, p.basenameWithoutExtension(it.name), zip ? 'zip' : '7z');
    cb?.call(0, 'Comprimiendo con 7-Zip…');
    final pw0 = o.password;
    final (code, err) = await _exec(
      Tools.sevenZip!,
      [
        'a', zip ? '-tzip' : '-t7z', zip ? '-mm=Deflate' : '-m0=lzma2', '-mx=9', '-mmt=on',
        if (pw0.isNotEmpty) '-p$pw0',
        if (pw0.isNotEmpty) (zip ? '-mem=AES256' : '-mhe=on'),
        '-bso0', '-bsp1', '-y', out, it.path,
      ],
      onOut: (s) {
        final m = RegExp(r'(\d{1,3})%').allMatches(s);
        if (m.isNotEmpty) {
          final v = int.parse(m.last.group(1)!);
          cb?.call(v / 100, 'Comprimiendo con 7-Zip… $v %');
        }
      },
    );
    if (code != 0) {
      await _rm(out);
      return Outcome(it, error: err.isEmpty ? '7-Zip falló (código $code).' : err);
    }
    // Un archivo cifrado puede pesar un poco más; con contraseña siempre se guarda.
    if (pw0.isNotEmpty) {
      return Outcome(it, path: out, outBytes: await File(out).length(), note: 'Protegido con contraseña.');
    }
    return _done(it, out);
  }
}
