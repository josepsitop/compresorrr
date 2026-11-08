import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/commands.dart';
import '../engine/compressor.dart';
import '../engine/history.dart';
import '../engine/models.dart';
import '../engine/native.dart';
import '../engine/presets.dart';
import '../engine/tools.dart';
import 'compare.dart';
import 'fx.dart';
import 'theme.dart';

void showPresetSheet(BuildContext context, Kind kind, List<Item> items) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 780),
    builder: (_) => PresetSheet(kind: kind, items: List.of(items)),
  );
}

class PresetSheet extends StatefulWidget {
  const PresetSheet({super.key, required this.kind, required this.items});
  final Kind kind;
  final List<Item> items;

  @override
  State<PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<PresetSheet> {
  final comp = Compressor();
  List<Compressor> _pool = [];
  List<Preset> presets = [];
  late Options opt;
  Probe? pr;
  bool ready = false;
  bool busy = false;
  bool comparing = false;
  bool _stop = false;
  double? progress;
  String msg = '';
  double frac = .05;
  double duration = 0;
  Outcome? sample;
  final results = <Outcome>[];
  int burst = 0;
  DateTime _lastNote = DateTime(2000);

  List<Item> get items => widget.items;
  Kind get kind => widget.kind;
  bool get single => items.length == 1;
  int get totalBytes => items.fold(0, (a, b) => a + b.bytes);
  String get _codec => effectiveCodec(opt);

  static const _muted = TextStyle(color: C.muted, fontSize: 13, height: 1.35);

  static const _cases = <Kind, List<(String, String)>>{
    Kind.video: [
      ('Enviar por chat', 'social'),
      ('Guardar en el equipo', 'balanced'),
      ('Archivar sin perder nada', 'visual'),
      ('Que abra en todos lados', 'compat'),
    ],
    Kind.photo: [
      ('Enviar por chat', 'p_min'),
      ('Guardar en el equipo', 'p_bal'),
      ('Calidad máxima', 'p_web'),
      ('Que abra en todos lados', 'p_jpg'),
    ],
  };

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Tools.init();
    await Native.loadDevice();
    presets = presetsFor(kind, pdf: items.every((e) => e.isPdf));
    var def = presets.firstWhere((p) => p.recommended, orElse: () => presets.first);
    final dev = Native.device;
    if (kind == Kind.video && dev != null && dev.weak) {
      // Celular justo: sugerimos el modo más ligero para él.
      final id = dev.hevcHw ? 'hw' : 'compat';
      def = presets.firstWhere((p) => p.id == id, orElse: () => def);
    }
    opt = Options(def);
    _defaults(def);
    if (kind == Kind.video) {
      pr = await comp.ff.probe(items.first.path);
      duration = pr!.duration;
    }
    if (mounted) setState(() => ready = true);
  }

  void _defaults(Preset p) {
    opt.height = p.id == 'social' ? 720 : 0;
    opt.audio = p.id == 'social' ? 96 : 128;
  }

  @override
  void dispose() {
    _stop = true;
    if (busy) {
      for (final c in [..._pool, comp]) {
        c.cancel();
      }
      try {
        WakelockPlus.disable();
      } catch (_) {}
      Native.serviceStop();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  double get _range => max(0.0, (opt.trimEnd > 0 ? opt.trimEnd : duration) - opt.trimStart);
  double get _sampleSecs => _range <= 0 ? 0 : min(_range, min(90.0, max(3.0, _range * frac)));

  // ---------------------------------------------------------------- acciones
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

  void _cancel() {
    _stop = true;
    for (final c in [..._pool, comp]) {
      c.cancel();
    }
  }

  Future<void> _runAll() async {
    final n = items.length;
    final fracs = List<double>.filled(n, 0);
    var started = 0;
    var finished = 0;
    _stop = false;
    setState(() { busy = true; progress = null; results.clear(); msg = 'Empezando…'; });
    try { await WakelockPlus.enable(); } catch (_) {}
    await Native.serviceStart('Comprimiendo…');

    // Con NVENC se pueden codificar 2 videos a la vez.
    final workers = (Tools.isPc && Tools.nvenc && opt.preset.id == 'hw' && !opt.audioOnly && n > 1) ? 2 : 1;
    _pool = List.generate(workers, (_) => Compressor());

    void tick(int i, double? f, String m) {
      if (!mounted) return;
      if (f != null) fracs[i] = f;
      final overall = fracs.fold<double>(0, (a, b) => a + b) / n;
      final label = n > 1 ? 'Archivo ${min(finished + 1, n)} de $n · $m' : m;
      setState(() { progress = n > 1 ? overall : f; msg = label; });
      final now = DateTime.now();
      if (now.difference(_lastNote).inMilliseconds > 1500) {
        _lastNote = now;
        Native.serviceUpdate(label, (overall * 100).round());
      }
    }

    Future<void> worker(Compressor c) async {
      while (!_stop) {
        final i = started++;
        if (i >= n) return;
        if (opt.onlyCharging && Native.on) {
          while (!_stop && !(await Native.charging())) {
            if (mounted) setState(() { progress = null; msg = 'Esperando a que conectes el cargador…'; });
            await Future.delayed(const Duration(seconds: 5));
          }
          if (_stop) return;
        }
        final r = await c.run(items[i], opt, onProgress: (f, m) => tick(i, f, m));
        fracs[i] = 1;
        finished++;
        if (!mounted) return;
        setState(() => results.add(r));
        if (r.ok) history.add(r, opt.audioOnly ? 'Solo audio' : opt.preset.name, kind);
        if (r.error == 'Cancelado') _stop = true;
      }
    }

    await Future.wait(_pool.map(worker));
    try { await WakelockPlus.disable(); } catch (_) {}
    await Native.serviceStop();
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
        if (kind == Kind.video && !opt.audioOnly) {
          await Gal.putVideo(path, album: 'Squeeze');
        } else if (kind == Kind.photo) {
          await Gal.putImage(path, album: 'Squeeze');
        } else {
          await Share.shareXFiles([XFile(path)]);
          return;
        }
        _toast('Guardado en la galería, álbum Squeeze. Si quieres liberar espacio, borra el original desde la galería.');
      } else if (Platform.isAndroid) {
        await Share.shareXFiles([XFile(path)]);
      } else {
        await Process.run('explorer.exe', ['/select,', path]);
      }
    } catch (e) {
      _toast('No se pudo guardar: $e');
    }
  }

  Future<void> _compareFrame(Outcome s) async {
    setState(() => comparing = true);
    final len = s.sampleSeconds ?? 0;
    final a = await comp.frame(items.first.path, (s.sampleStart ?? 0) + len / 2, 'orig');
    final b = await comp.frame(s.path!, len / 2, 'comp');
    if (!mounted) return;
    setState(() => comparing = false);
    if (a == null || b == null) {
      _toast('No pude extraer el fotograma.');
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BeforeAfter(before: a, after: b, height: 260),
            const SizedBox(height: 8),
            const Text('Desliza para comparar el original con la muestra comprimida.', style: _muted),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ]),
        ),
      ),
    );
  }

  void _explain(Preset p) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p.name),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(p.explain, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            const Text('Comparado con otros modos', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(p.versus, style: const TextStyle(height: 1.4)),
          ]),
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
          child: ListView(shrinkWrap: true, children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 14, runSpacing: 4, children: [
                    _stat('Ahorro', p.savings),
                    _dots('Velocidad', p.speed),
                    _dots('Calidad', p.quality),
                  ]),
                ]),
              ),
            const Text('El ahorro real depende del archivo original: uno ya comprimido baja menos.', style: _muted),
          ]),
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
        padding: const EdgeInsets.only(top: 18),
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

  Widget _notice(String text) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.noteBg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 18, color: C.noteFg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: C.noteFg, fontSize: 13, height: 1.35))),
        ]),
      );

  List<String> _notices() {
    final n = <String>[];
    final x = pr;
    if (kind == Kind.video && single && x != null) {
      final modern = {'hevc', 'av1', 'vp9'}.contains(x.vcodec);
      if (x.bpps > 0 && (x.bpps < 1.5 || (modern && x.bpps < 3))) {
        n.add('Este video ya viene muy comprimido: ahorrarás poco. "Mini para compartir" o bajar la resolución rinden más.');
      }
    }
    if (kind == Kind.photo && single) {
      if (items.first.bytes < 200 * 1024) {
        n.add('Esta foto ya pesa muy poco; el ahorro será pequeño.');
      } else if (items.first.ext == 'webp') {
        n.add('Ya es WebP: el ahorro será menor que con un JPEG o PNG.');
      }
    }
    if (kind == Kind.file && !items.any((e) => e.isPdf) && items.every((e) => e.isPacked)) {
      n.add('Estos archivos ya vienen comprimidos (JPG, MP4, ZIP, DOCX…): la compresión sin pérdida casi no los reducirá.');
    }
    final d = Native.device;
    if (Platform.isAndroid && kind == Kind.video && d != null && d.weak) {
      n.add('Tu ${d.model.isEmpty ? 'celular' : d.model} (${d.bitsText}, ${(d.ramMb / 1024).toStringAsFixed(1)} GB de RAM) '
          'es justo para video pesado. Dejé seleccionado el modo más ligero para él.');
    }
    return n;
  }

  String _tagline(Preset p) {
    if (p.id == 'hw' && kind == Kind.video) {
      if (Tools.isPc) {
        return Tools.nvenc
            ? 'Usa tu GPU NVIDIA (NVENC): minutos en vez de horas.'
            : 'No se detectó NVENC: usará el procesador.';
      }
      final d = Native.device;
      if (d != null && !d.hevcHw) return 'Este celular no tiene HEVC por hardware: usará el modo de respaldo.';
    }
    return p.tagline;
  }

  Widget _tile(Preset p) {
    final sel = p.id == opt.preset.id;
    final note = (kind == Kind.video && Platform.isAndroid) ? Native.device?.noteFor(p, sel ? _codec : effectiveCodecFor(p), pr) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : () => setState(() { opt.preset = p; _defaults(p); sample = null; }),
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
                        child: Text('Recomendado', style: TextStyle(color: C.mint, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(_tagline(p), style: _muted),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Ojo: $note', style: const TextStyle(color: C.noteFg, fontSize: 12.5, height: 1.3)),
                    ),
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

  String effectiveCodecFor(Preset p) {
    final o = Options(p)..codec = opt.codec;
    return effectiveCodec(o);
  }

  // ------------------------------------------------------------- ajustes
  Widget _settings() {
    final c = <Widget>[];
    if (kind == Kind.video) {
      const containerHelp = {
        'mp4': 'MP4 abre en todo: celulares, TV y redes sociales. Es la opción segura.',
        'mkv': 'MKV es muy flexible, pero iPhone y Mac no lo reproducen bien.',
        'mov': 'MOV es el contenedor de Apple; funciona en Mac, iPhone y la mayoría de editores.',
      };
      const codecHelp = {
        'auto': 'Auto usa el códec propio de cada modo (casi todos usan HEVC).',
        'hevc': 'HEVC (H.265): archivos más pequeños; puede no abrir en aparatos muy viejos.',
        'h264': 'H.264: lo abre todo, pero pesa más a igual calidad.',
        'av1': 'AV1: el más eficiente; lento y solo en PC.',
      };
      if (!opt.audioOnly) {
        c.add(_section(
          'Formato de salida',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _chips<String>([('MP4', 'mp4'), ('MKV', 'mkv'), ('MOV', 'mov')], opt.container, (v) => opt.container = v),
            const SizedBox(height: 6),
            Text(containerHelp[opt.container]!, style: _muted),
          ]),
        ));
        c.add(_section(
          'Códec',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _chips<String>([
              ('Auto', 'auto'),
              ('HEVC', 'hevc'),
              ('H.264', 'h264'),
              if (Tools.isPc && Tools.svtav1) ('AV1', 'av1'),
            ], opt.codec, (v) => opt.codec = v),
            const SizedBox(height: 6),
            Text(codecHelp[opt.codec]!, style: _muted),
          ]),
        ));
        if (opt.preset.id == 'custom') {
          c.add(_section(
            'Calidad (CRF ${opt.crf.round()})',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Slider(
                value: opt.crf, min: 16, max: 38, divisions: 22,
                onChanged: busy ? null : (v) => setState(() { opt.crf = v; sample = null; }),
              ),
              const Text('Número bajo = mejor calidad y más peso. 18 casi sin pérdida · 23 muy buena · 28 aceptable.', style: _muted),
            ]),
          ));
        }
        c.add(_section('Resolución máxima', _chips<int>(
            [('Original', 0), ('1080p', 1080), ('720p', 720), ('480p', 480)], opt.height, (v) => opt.height = v)));
      }
      c.add(_section('Audio', _chips<int>(
          [('Copiar', 0), ('64 kbps', 64), ('96 kbps', 96), ('128 kbps', 128), ('192 kbps', 192)],
          opt.audio, (v) => opt.audio = v)));
    }
    if (kind == Kind.photo) {
      c.add(_section('Formato', _chips<String>(
          [('Auto', 'auto'), ('WebP', 'webp'), ('JPEG', 'jpg')], opt.imgFormat, (v) => opt.imgFormat = v)));
      if (opt.preset.id == 'custom') {
        c.add(_section(
          'Calidad ${opt.quality}',
          Slider(
            value: opt.quality.toDouble(), min: 40, max: 95, divisions: 55,
            onChanged: busy ? null : (v) => setState(() => opt.quality = v.round()),
          ),
        ));
        c.add(_section('Tamaño máximo (lado mayor)', _chips<int>(
            [('Original', 0), ('4096', 4096), ('2560', 2560), ('1920', 1920), ('1280', 1280)],
            opt.maxSide, (v) => opt.maxSide = v)));
      }
      c.add(const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text('Las fotos se guardan sin ubicación ni datos de la cámara.', style: _muted),
      ));
    }
    if (kind == Kind.file && (opt.preset.id == 'f_7z' || opt.preset.id == 'f_zip')) {
      c.add(_section(
        'Contraseña (opcional)',
        TextField(
          key: const ValueKey('pw'),
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Déjalo vacío para no cifrar', border: OutlineInputBorder()),
          onChanged: (v) => opt.password = v,
        ),
      ));
    }
    if (kind == Kind.video || kind == Kind.photo) c.add(_extras());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: c);
  }

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> on) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub, style: _muted),
        value: value,
        onChanged: busy ? null : (v) => setState(() { on(v); sample = null; }),
      );

  Widget _extras() {
    final c = <Widget>[];
    if (kind == Kind.video) {
      c.add(_section('Peso objetivo', _chips<int>(
          [('Sin límite', 0), ('10 MB', 10), ('25 MB', 25), ('50 MB', 50), ('100 MB', 100), ('500 MB', 500)],
          opt.targetMB, (v) { opt.targetMB = v; if (v > 0) opt.auto = false; })));
      if (opt.targetMB > 0) {
        c.add(const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('La app ajusta la calidad para quedar justo bajo ese peso. Si es muy pequeño para la duración, se verá mal.', style: _muted),
        ));
      }
      if (Tools.isPc && Tools.vmaf) {
        c.add(_section('Calidad automática', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _switch('Buscar el ajuste más liviano que se vea igual',
              'Prueba varias calidades en un trozo y mide el parecido con el original (VMAF). Tarda más.',
              opt.auto, (v) { opt.auto = v; if (v) opt.targetMB = 0; }),
          if (opt.auto)
            _chips<int>([('Buena (93)', 93), ('Casi imperceptible (95)', 95), ('Idéntica (97)', 97)], opt.vmaf, (v) => opt.vmaf = v),
        ])));
      }
      c.add(_section('Reducir ruido', _chips<String>(
          [('No', 'off'), ('Suave', 'soft'), ('Fuerte', 'strong')], opt.denoise, (v) => opt.denoise = v)));
      c.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Ayuda mucho en videos oscuros o con grano: ahorra bastante peso. Tarda más.', style: _muted),
      ));
      if (single && duration > 0) c.add(_trim());
      c.add(const SizedBox(height: 6));
      c.add(_switch('Quitar ubicación y datos de la cámara', 'Borra los metadatos del video.', opt.stripMeta, (v) => opt.stripMeta = v));
      c.add(_switch('Quitar el audio', 'El video queda sin sonido.', opt.noAudio, (v) { opt.noAudio = v; if (v) opt.audioOnly = false; }));
      c.add(_switch('Solo audio', 'Extrae el sonido y lo guarda como ${opt.audioFormat.toUpperCase()}; no se guarda video.',
          opt.audioOnly, (v) { opt.audioOnly = v; if (v) opt.noAudio = false; }));
      if (opt.audioOnly) {
        c.add(_chips<String>([('M4A (AAC)', 'm4a'), ('MP3', 'mp3')], opt.audioFormat, (v) => opt.audioFormat = v));
      }
    } else {
      c.add(_section('Peso objetivo', _chips<int>(
          [('Sin límite', 0), ('200 KB', 200), ('500 KB', 500), ('1 MB', 1024), ('2 MB', 2048)],
          opt.targetKB, (v) => opt.targetKB = v)));
      if (opt.targetKB > 0) {
        c.add(const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Baja la calidad y, si hace falta, el tamaño hasta quedar bajo ese peso.', style: _muted),
        ));
      }
    }
    if (Native.on && kind == Kind.video) {
      c.add(_switch('Solo cuando esté cargando', 'Espera a que conectes el cargador para no gastar batería.',
          opt.onlyCharging, (v) => opt.onlyCharging = v));
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        expandedAlignment: Alignment.centerLeft,
        title: const Text('Más ajustes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        children: c,
      ),
    );
  }

  Widget _trim() {
    double cl(double v) => v < 0 ? 0 : (v > duration ? duration : v);
    final end = opt.trimEnd > 0 ? opt.trimEnd : duration;
    return _section(
      'Recortar',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RangeSlider(
          values: RangeValues(cl(opt.trimStart), cl(end)),
          min: 0,
          max: duration,
          onChanged: busy
              ? null
              : (v) => setState(() {
                    opt.trimStart = v.start;
                    opt.trimEnd = v.end >= duration - .5 ? 0 : v.end;
                    sample = null;
                  }),
        ),
        Text('De ${fmtClock(opt.trimStart)} a ${fmtClock(end)} · dura ${fmtDur(max(0.0, end - opt.trimStart))}', style: _muted),
      ]),
    );
  }

  Widget _samplePanel() {
    final s = sample;
    Widget? res;
    if (s != null) {
      if (!s.ok) {
        res = Text(s.error ?? s.note ?? 'No se pudo generar la muestra.', style: const TextStyle(color: C.warn, fontSize: 13));
      } else {
        final secs = s.sampleSeconds ?? _sampleSecs;
        final est = secs > 0 && _range > 0 ? s.outBytes / secs * _range : 0;
        final pct = est > 0 && items.first.bytes > 0 ? ((1 - est / items.first.bytes) * 100).round() : null;
        res = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Muestra de ${secs.round()} s: ${fmtBytes(s.outBytes)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (est > 0 && !opt.audioOnly)
            Text('Completo pesaría unos ${fmtBytes(est)}${pct != null ? ' (−$pct %)' : ''}',
                style: const TextStyle(color: C.mint, fontWeight: FontWeight.w700)),
          if (s.note != null) Text(s.note!, style: _muted),
          const Text('Es una estimación: varía según las escenas del resto del video.', style: _muted),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              onPressed: () => OpenFilex.open(s.path!),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(opt.audioOnly ? 'Escuchar' : 'Ver la muestra'),
            ),
            if (!opt.audioOnly)
              TextButton.icon(
                onPressed: comparing ? null : () => _compareFrame(s),
                icon: comparing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.compare_rounded),
                label: const Text('Comparar fotograma'),
              ),
          ]),
        ]);
      }
    }
    return _section(
      'Vista previa',
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Procesa solo un trozo del medio del video para ver cómo queda y cuánto pesaría completo.', style: _muted),
          Row(children: [
            Expanded(
              child: Slider(
                value: frac, min: .02, max: .2, divisions: 18, label: '${(frac * 100).round()} %',
                onChanged: busy ? null : (v) => setState(() { frac = v; sample = null; }),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(_range > 0 ? '${(frac * 100).round()} % · ${_sampleSecs.round()} s' : '${(frac * 100).round()} %',
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
    final savedTxt = r.outBytes >= r.inBytes ? '+${-pct} %' : '−$pct %';
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
                child: Text(savedTxt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('${fmtBytes(r.inBytes)}  →  ${fmtBytes(r.outBytes)}', style: const TextStyle(fontSize: 15))),
          ]),
          if (r.note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.note!, style: _muted)),
          if (kind == Kind.photo) ...[
            const SizedBox(height: 12),
            BeforeAfter(before: r.item.path, after: r.path!, height: 220),
            const SizedBox(height: 4),
            const Text('Desliza la barra para comparar el antes y el después.', style: _muted),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => _save(r),
              icon: Icon(Platform.isAndroid ? (kind == Kind.file || opt.audioOnly ? Icons.ios_share : Icons.download_rounded) : Icons.folder_open),
              label: Text(Platform.isAndroid
                  ? (kind == Kind.file || opt.audioOnly ? 'Guardar o compartir' : 'Guardar en galería')
                  : 'Mostrar en carpeta'),
            ),
            TextButton(onPressed: () => OpenFilex.open(r.path!), child: const Text('Abrir')),
          ]),
        ]),
      ),
    );
  }

  List<Widget> _content() {
    final ok = results.where((r) => r.ok).toList();
    final cases = _cases[kind];
    return [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 14),
      Text(single ? items.first.name : '${items.length} archivos',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3)),
      const SizedBox(height: 2),
      Text('${fmtBytes(totalBytes)}${kind == Kind.video && duration > 0 && single ? '  ·  ${fmtDur(duration)}' : ''}',
          style: const TextStyle(color: C.muted)),
      if (kind == Kind.file && items.any((e) => e.isPdf) && !items.every((e) => e.isPdf))
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Mezclaste PDF con otros formatos: se usa compresión general para todos.', style: _muted),
        ),
      for (final n in _notices()) _notice(n),
      if (cases != null) ...[
        const SizedBox(height: 16),
        const Text('¿Para qué lo quieres?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final cs in cases)
            if (presets.any((p) => p.id == cs.$2))
              ChoiceChip(
                label: Text(cs.$1),
                selected: opt.preset.id == cs.$2,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                          opt.preset = presets.firstWhere((p) => p.id == cs.$2);
                          _defaults(opt.preset);
                          sample = null;
                        }),
              ),
        ]),
      ],
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('Elige un modo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
        TextButton.icon(onPressed: _compare, icon: const Icon(Icons.compare_arrows_rounded, size: 20), label: const Text('Comparar')),
      ]),
      const SizedBox(height: 6),
      for (final p in presets) _tile(p),
      _settings(),
      if (kind == Kind.video && single) _samplePanel(),
      const SizedBox(height: 22),
      if (busy) ...[
        LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 8),
        Text(msg, style: _muted),
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _cancel, child: const Text('Cancelar'))),
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
          if (burst > 0) Positioned.fill(child: IgnorePointer(child: Center(child: SparkleBurst(key: ValueKey(burst), size: 340)))),
        ]),
      ),
    );
  }
}
