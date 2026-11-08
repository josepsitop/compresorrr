import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/compressor.dart';
import '../engine/models.dart';
import '../engine/presets.dart';
import '../engine/tools.dart';
import 'fx.dart';
import 'theme.dart';

class PresetSheet extends StatefulWidget {
  const PresetSheet({super.key, required this.kind, required this.items});
  final Kind kind;
  final List<Item> items;

  @override
  State<PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<PresetSheet> {
  final comp = Compressor();
  List<Preset> presets = [];
  late Options opt;
  bool ready = false;
  bool busy = false;
  double? progress;
  String msg = '';
  double frac = .05;
  double duration = 0;
  Outcome? sample;
  final results = <Outcome>[];
  int burst = 0;

  List<Item> get items => widget.items;
  Kind get kind => widget.kind;
  bool get single => items.length == 1;
  int get totalBytes => items.fold(0, (a, b) => a + b.bytes);

  static const _muted = TextStyle(color: C.muted, fontSize: 13, height: 1.35);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Tools.init();
    presets = presetsFor(kind, pdf: items.every((e) => e.isPdf));
    opt = Options(presets.firstWhere((p) => p.recommended, orElse: () => presets.first));
    if (kind == Kind.video) duration = (await comp.ff.probe(items.first.path)).duration;
    if (mounted) setState(() => ready = true);
  }

  @override
  void dispose() {
    if (busy) comp.cancel();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  double get _sampleSecs => duration <= 0 ? 0 : min(duration, min(90.0, max(3.0, duration * frac)));

  // ------------------------------------------------------------- acciones
  Future<void> _runSample() async {
    setState(() {
      busy = true;
      sample = null;
      progress = null;
      msg = 'Preparando la muestra…';
    });
    final r = await comp.run(items.first, opt, sample: frac, onProgress: (f, m) {
      if (mounted) setState(() { progress = f; msg = m; });
    });
    if (!mounted) return;
    setState(() { busy = false; sample = r; });
  }

  Future<void> _runAll() async {
    setState(() { busy = true; progress = null; results.clear(); msg = 'Empezando…'; });
    try { await WakelockPlus.enable(); } catch (_) {}
    for (var i = 0; i < items.length; i++) {
      final r = await comp.run(items[i], opt, onProgress: (f, m) {
        if (!mounted) return;
        setState(() {
          progress = f;
          msg = items.length > 1 ? 'Archivo ${i + 1} de ${items.length} · $m' : m;
        });
      });
      if (!mounted) return;
      setState(() => results.add(r));
      if (r.error == 'Cancelado') break;
    }
    try { await WakelockPlus.disable(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      busy = false;
      if (results.any((r) => r.ok)) burst++;
    });
  }

  Future<void> _save(Outcome r) async {
    final path = r.path!;
    try {
      if (Platform.isAndroid && kind != Kind.file) {
        if (!await Gal.hasAccess(toAlbum: true)) await Gal.requestAccess(toAlbum: true);
        if (kind == Kind.video) {
          await Gal.putVideo(path, album: 'Squeeze');
        } else {
          await Gal.putImage(path, album: 'Squeeze');
        }
        _toast('Guardado en la galería, álbum Squeeze.');
      } else if (Platform.isAndroid) {
        await Share.shareXFiles([XFile(path)]);
      } else {
        await Process.run('explorer.exe', ['/select,', path]);
      }
    } catch (e) {
      _toast('No se pudo guardar: $e');
    }
  }

  void _explain(Preset p) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.explain, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              const Text('Comparado con otros modos', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(p.versus, style: const TextStyle(height: 1.4)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  void _compare() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Comparar modos'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in presets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 14, runSpacing: 4, children: [
                        _stat('Ahorro', p.savings),
                        _dots('Velocidad', p.speed),
                        _dots('Calidad', p.quality),
                      ]),
                    ],
                  ),
                ),
              const Text('El ahorro real depende del archivo original: uno ya comprimido baja menos.', style: _muted),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  // ------------------------------------------------------------ componentes
  Widget _stat(String label, String value) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: _muted),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.mint)),
      ]);

  Widget _dots(String label, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: _muted),
        for (var i = 0; i < 5; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(shape: BoxShape.circle, color: i < n ? C.blue : C.line),
          ),
      ]);

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _chips<T>(List<(String, T)> opts, T value, ValueChanged<T> on) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final o in opts)
            ChoiceChip(
              label: Text(o.$1),
              selected: value == o.$2,
              onSelected: busy ? null : (_) => setState(() { on(o.$2); sample = null; }),
            ),
        ],
      );

  Widget _tile(Preset p) {
    final sel = p.id == opt.preset.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : () => setState(() { opt.preset = p; sample = null; }),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? C.blue : C.line, width: sel ? 2 : 1),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                    if (p.recommended)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('Recomendado',
                            style: TextStyle(color: C.mint, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(p.tagline, style: _muted),
                  const SizedBox(height: 8),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    _stat('Ahorro', p.savings),
                    _dots('Velocidad', p.speed),
                    _dots('Calidad', p.quality),
                  ]),
                ]),
              ),
              IconButton(
                tooltip: 'Qué significa',
                icon: const Icon(Icons.info_outline_rounded, color: C.blue),
                onPressed: () => _explain(p),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _options() {
    final children = <Widget>[];
    if (kind == Kind.video) {
      const help = {
        'mp4': 'MP4 abre en todo: celulares, TV, redes sociales. Es la opción segura.',
        'mkv': 'MKV es muy flexible, pero iPhone y Mac no lo reproducen bien.',
        'mov': 'MOV es el contenedor de Apple; funciona en Mac y iPhone y en la mayoría de editores.',
      };
      children.add(_section(
        'Formato de salida',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _chips<String>([('MP4', 'mp4'), ('MKV', 'mkv'), ('MOV', 'mov')], opt.container, (v) => opt.container = v),
          const SizedBox(height: 6),
          Text(help[opt.container]!, style: _muted),
        ]),
      ));
      if (opt.preset.id == 'custom') {
        children.addAll([
          _section('Códec', _chips<String>([
            ('HEVC (H.265)', 'hevc'),
            ('H.264', 'h264'),
            if (Tools.isPc && Tools.svtav1) ('AV1', 'av1'),
          ], opt.codec, (v) => opt.codec = v)),
          _section(
            'Calidad (CRF ${opt.crf.round()})',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Slider(
                value: opt.crf, min: 16, max: 38, divisions: 22,
                onChanged: busy ? null : (v) => setState(() { opt.crf = v; sample = null; }),
              ),
              const Text('Número bajo = mejor calidad y más peso. 18 casi sin pérdida · 23 muy buena · 28 aceptable.',
                  style: _muted),
            ]),
          ),
          _section('Resolución máxima', _chips<int>(
              [('Original', 0), ('1080p', 1080), ('720p', 720), ('480p', 480)], opt.height, (v) => opt.height = v)),
          _section('Audio', _chips<int>(
              [('Copiar', 0), ('64 kbps', 64), ('96 kbps', 96), ('128 kbps', 128), ('192 kbps', 192)],
              opt.audio, (v) => opt.audio = v)),
        ]);
      }
    } else if (kind == Kind.photo && opt.preset.id == 'custom') {
      children.addAll([
        _section('Formato', _chips<String>([('WebP', 'webp'), ('JPEG', 'jpg')], opt.imgFormat, (v) => opt.imgFormat = v)),
        _section(
          'Calidad ${opt.quality}',
          Slider(
            value: opt.quality.toDouble(), min: 40, max: 95, divisions: 55,
            onChanged: busy ? null : (v) => setState(() => opt.quality = v.round()),
          ),
        ),
        _section('Tamaño máximo (lado mayor)', _chips<int>(
            [('Original', 0), ('4096', 4096), ('2560', 2560), ('1920', 1920), ('1280', 1280)],
            opt.maxSide, (v) => opt.maxSide = v)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _samplePanel() {
    final s = sample;
    Widget? res;
    if (s != null) {
      if (!s.ok) {
        res = Text(s.error ?? s.note ?? 'No se pudo generar la muestra.',
            style: const TextStyle(color: C.warn, fontSize: 13));
      } else {
        final secs = s.sampleSeconds ?? _sampleSecs;
        final est = secs > 0 && duration > 0 ? s.outBytes / secs * duration : 0;
        final pct = est > 0 && items.first.bytes > 0 ? ((1 - est / items.first.bytes) * 100).round() : null;
        res = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Muestra de ${secs.round()} s: ${fmtBytes(s.outBytes)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (est > 0)
            Text('Completo pesaría unos ${fmtBytes(est)}${pct != null ? ' (−$pct %)' : ''}',
                style: const TextStyle(color: C.mint, fontWeight: FontWeight.w700)),
          const Text('Es una estimación: varía según las escenas del resto del video.', style: _muted),
          TextButton.icon(
            onPressed: () => OpenFilex.open(s.path!),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Ver la muestra'),
          ),
        ]);
      }
    }
    return _section(
      'Vista previa',
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Procesa solo un trozo del medio del video para ver cómo queda y cuánto pesaría completo.',
              style: _muted),
          Row(children: [
            Expanded(
              child: Slider(
                value: frac, min: .02, max: .2, divisions: 18,
                label: '${(frac * 100).round()} %',
                onChanged: busy ? null : (v) => setState(() { frac = v; sample = null; }),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(duration > 0 ? '${(frac * 100).round()} % · ${_sampleSecs.round()} s' : '${(frac * 100).round()} %',
                  textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          OutlinedButton.icon(
            onPressed: busy ? null : _runSample,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Probar muestra'),
          ),
          if (res != null) ...[const SizedBox(height: 10), res],
        ]),
      ),
    );
  }

  Widget _result(Outcome r) {
    if (!r.ok) {
      final bad = r.error != null;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(bad ? Icons.error_outline : Icons.info_outline, color: bad ? C.warn : C.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${r.item.name}\n${r.error ?? r.note}',
                style: TextStyle(color: bad ? C.warn : C.muted, fontSize: 13, height: 1.35)),
          ),
        ]),
      );
    }
    final pct = (r.saved * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: C.mint, borderRadius: BorderRadius.circular(20)),
                child: Text('−$pct %', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('${fmtBytes(r.inBytes)}  →  ${fmtBytes(r.outBytes)}', style: const TextStyle(fontSize: 15))),
          ]),
          if (kind == Kind.photo) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _before(r.item.path, 'Antes')),
              const SizedBox(width: 8),
              Expanded(child: _before(r.path!, 'Después')),
            ]),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => _save(r),
              icon: Icon(Platform.isAndroid ? (kind == Kind.file ? Icons.ios_share : Icons.download_rounded) : Icons.folder_open),
              label: Text(Platform.isAndroid ? (kind == Kind.file ? 'Guardar o compartir' : 'Guardar en galería') : 'Mostrar en carpeta'),
            ),
            TextButton(onPressed: () => OpenFilex.open(r.path!), child: const Text('Abrir')),
          ]),
        ]),
      ),
    );
  }

  Widget _before(String path, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(path),
              height: 120, width: double.infinity, fit: BoxFit.cover, cacheHeight: 240,
              errorBuilder: (_, __, ___) => Container(height: 120, color: C.line)),
        ),
        const SizedBox(height: 4),
        Text(label, style: _muted),
      ]);

  List<Widget> _content() {
    final ok = results.where((r) => r.ok).toList();
    return [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 14),
      Text(single ? items.first.name : '${items.length} archivos',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
      const SizedBox(height: 2),
      Text('${fmtBytes(totalBytes)}${kind == Kind.video && duration > 0 && single ? '  ·  ${fmtDur(duration)}' : ''}',
          style: const TextStyle(color: C.muted)),
      if (kind == Kind.file && !items.every((e) => e.isPdf) && items.any((e) => e.isPdf))
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Mezclaste PDF con otros formatos: se usa compresión general para todos.', style: _muted),
        ),
      const SizedBox(height: 18),
      Row(children: [
        const Expanded(child: Text('Elige un modo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
        TextButton.icon(onPressed: _compare, icon: const Icon(Icons.compare_arrows_rounded, size: 20), label: const Text('Comparar')),
      ]),
      const SizedBox(height: 6),
      for (final p in presets) _tile(p),
      _options(),
      if (kind == Kind.video && single) _samplePanel(),
      const SizedBox(height: 22),
      if (busy) ...[
        LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 8),
        Text(msg, style: _muted),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: comp.cancel, child: const Text('Cancelar')),
        ),
      ] else
        GradientButton(
          label: single ? 'Comprimir' : 'Comprimir los ${items.length}',
          icon: Icons.compress_rounded,
          onTap: _runAll,
        ),
      if (ok.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            'Total: ${fmtBytes(ok.fold<int>(0, (a, r) => a + r.inBytes))} → ${fmtBytes(ok.fold<int>(0, (a, r) => a + r.outBytes))}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: C.mint),
          ),
        ),
      for (final r in results) _result(r),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .94,
      minChildSize: .6,
      maxChildSize: .97,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(color: C.paper, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Stack(children: [
          ready
              ? ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: _content())
              : const Center(child: CircularProgressIndicator()),
          if (burst > 0) Positioned.fill(child: Center(child: SparkleBurst(key: ValueKey(burst), size: 340))),
        ]),
      ),
    );
  }
}
