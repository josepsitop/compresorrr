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

  Future<void> cancel() async {
    _cancelled = true;
    await ff.cancel();
    _proc?.kill();
  }

  Future<String> _tmpDir() async {
    final d = Directory(p.join((await getTemporaryDirectory()).path, 'squeeze_out'));
    await d.create(recursive: true);
    return d.path;
  }

  Future<String> _outDir(Item it) async => Platform.isAndroid ? _tmpDir() : p.dirname(it.path);

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

  /// [sample] != null => solo procesa ese porcentaje del video (vista previa).
  Future<Outcome> run(Item it, Options o, {double? sample, Progress? onProgress}) async {
    _cancelled = false;
    try {
      final dir = sample != null ? await _tmpDir() : await _outDir(it);
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

  Future<Outcome> _done(Item it, String out, {bool sample = false, double? secs}) async {
    final size = await File(out).length();
    if (!sample && size >= it.bytes) {
      await _rm(out);
      return Outcome(it,
          note: 'Este archivo ya estaba muy optimizado: el resultado pesaba igual o más, así que no se guardó.');
    }
    return Outcome(it, path: out, outBytes: size, sampleSeconds: secs);
  }

  // ------------------------------------------------------------------ video
  Future<Outcome> _video(Item it, Options o, String dir, double? sample, Progress? cb) async {
    cb?.call(null, 'Leyendo el video…');
    final pr = await ff.probe(it.path);
    double? ss, t;
    var total = pr.duration;
    if (sample != null && pr.duration > 0) {
      t = min(pr.duration, min(90.0, max(3.0, pr.duration * sample)));
      ss = max(0.0, (pr.duration - t) / 2);
      total = t;
    }
    final stem = p.basenameWithoutExtension(it.name);
    final out = await _unique(dir, sample != null ? '${stem}_muestra' : '${stem}_squeeze', videoExt(o));
    final attempts = videoAttempts(it.path, out, pr, o,
        pc: Tools.isPc, nvenc: Tools.nvenc, ss: ss, t: t);

    var r = const FfResult(false, false, '');
    for (var i = 0; i < attempts.length; i++) {
      cb?.call(0, i == 0 ? 'Comprimiendo…' : 'Reintentando con el modo de respaldo…');
      r = await ff.run(attempts[i], totalSeconds: total, onProgress: (f) {
        cb?.call(f, 'Comprimiendo… ${(f * 100).round()} %');
      });
      if (r.ok || r.cancelled) break;
    }
    if (!r.ok) {
      await _rm(out);
      return Outcome(it,
          error: r.cancelled ? 'Cancelado' : (r.log.isNotEmpty ? r.log : 'FFmpeg no pudo procesar este video.'));
    }
    return _done(it, out, sample: sample != null, secs: t);
  }

  // ------------------------------------------------------------------ foto
  Future<Outcome> _photo(Item it, Options o, String dir, Progress? cb) async {
    cb?.call(null, 'Comprimiendo imagen…');
    final out = await _unique(dir, '${p.basenameWithoutExtension(it.name)}_squeeze', photoExt(o));
    final r = await ff.run(photoArgs(it.path, out, o));
    if (!r.ok) {
      await _rm(out);
      return Outcome(it, error: r.cancelled ? 'Cancelado' : (r.log.isNotEmpty ? r.log : 'No se pudo procesar la imagen.'));
    }
    return _done(it, out);
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
    final (code, err) = await _exec(
      Tools.sevenZip!,
      ['a', zip ? '-tzip' : '-t7z', zip ? '-mm=Deflate' : '-m0=lzma2', '-mx=9', '-mmt=on',
        '-bso0', '-bsp1', '-y', out, it.path],
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
    return _done(it, out);
  }
}
