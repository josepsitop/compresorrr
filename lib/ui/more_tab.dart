import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/compressor.dart';
import '../engine/desktop.dart';
import '../engine/history.dart';
import '../engine/models.dart';
import '../engine/native.dart';
import '../engine/presets.dart';
import '../engine/store.dart';
import '../engine/tools.dart';
import 'theme.dart';

Future<void> openHeavyVideos(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HeavyVideosPage()));

class MoreTab extends StatefulWidget {
  const MoreTab({super.key});

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  bool menuOn = false;
  int tempBytes = 0;

  static const _muted = TextStyle(color: C.muted, fontSize: 13, height: 1.35);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final t = await Compressor.tempBytes();
    final m = Platform.isWindows ? await WinContext.installed() : false;
    if (mounted) setState(() { tempBytes = t; menuOn = m; });
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }

  BoxDecoration get _card =>
      BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line));

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: AnimatedBuilder(
          animation: Listenable.merge([history, watcher]),
          builder: (_, __) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Text('Más', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(height: 16),
              _saved(),
              const SizedBox(height: 20),
              const Text('Herramientas', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              ..._tools(),
              const SizedBox(height: 20),
              _historyList(),
              const SizedBox(height: 12),
              _diagnostics(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saved() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Espacio que has ahorrado', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(fmtBytes(history.saved),
              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
          Text('en ${history.entries.length} ${history.entries.length == 1 ? 'archivo' : 'archivos'}',
              style: const TextStyle(color: Colors.white70)),
        ]),
      );

  List<Widget> _tools() {
    final w = <Widget>[];
    if (Platform.isAndroid) {
      w.add(ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.search_rounded, color: C.blue),
        title: const Text('Buscar los videos más pesados'),
        subtitle: const Text('Encuentra lo que más espacio ocupa en tu teléfono.', style: _muted),
        onTap: () => openHeavyVideos(context),
      ));
    }
    if (Platform.isWindows) {
      w.add(SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.mouse_outlined, color: C.blue),
        title: const Text('Menú del clic derecho'),
        subtitle: const Text('Añade "Comprimir con Squeeze" al menú de cualquier archivo.', style: _muted),
        value: menuOn,
        onChanged: (v) async {
          if (v) {
            await WinContext.install();
          } else {
            await WinContext.remove();
          }
          _refresh();
        },
      ));
    }
    if (Tools.isPc) w.add(_watchCard());
    w.add(ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cleaning_services_outlined, color: C.blue),
      title: const Text('Liberar espacio temporal'),
      subtitle: Text('Archivos de trabajo guardados: ${fmtBytes(tempBytes)}', style: _muted),
      trailing: TextButton(
        onPressed: tempBytes == 0
            ? null
            : () async {
                store.clearAll();
                await Compressor.cleanTemp(everything: true);
                _refresh();
              },
        child: const Text('Limpiar'),
      ),
    ));
    return w;
  }

  Widget _watchCard() {
    final vids = presetsFor(Kind.video).where((p) => p.id != 'custom').toList();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: _card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.folder_special_outlined, color: C.blue),
          SizedBox(width: 10),
          Text('Carpeta vigilada', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
        ]),
        const SizedBox(height: 6),
        const Text('Todo lo que caiga en la carpeta se comprime solo. Los resultados van a la subcarpeta "Squeeze".', style: _muted),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(watcher.folder ?? 'Ninguna carpeta elegida', maxLines: 1, overflow: TextOverflow.ellipsis)),
          OutlinedButton(
            onPressed: watcher.running
                ? null
                : () async {
                    final d = await FilePicker.platform.getDirectoryPath();
                    if (d != null) setState(() => watcher.folder = d);
                  },
            child: const Text('Elegir'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('Modo para los videos', style: TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 8, children: [
          for (final p in vids)
            ChoiceChip(
              label: Text(p.name),
              selected: watcher.videoPresetId == p.id,
              onSelected: watcher.running ? null : (_) => setState(() => watcher.videoPresetId = p.id),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('También fotos (modo Equilibrado)'),
          value: watcher.photos,
          onChanged: watcher.running ? null : (v) => setState(() => watcher.photos = v),
        ),
        SizedBox(
          width: double.infinity,
          child: watcher.running
              ? FilledButton.tonalIcon(onPressed: watcher.stop, icon: const Icon(Icons.stop_rounded), label: const Text('Detener'))
              : FilledButton.icon(
                  onPressed: watcher.folder == null ? null : () => watcher.start(watcher.folder!),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Empezar a vigilar'),
                ),
        ),
        if (watcher.log.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final l in watcher.log.take(6)) Text(l, style: _muted, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }

  Widget _historyList() {
    if (history.entries.isEmpty) {
      return const Text('Tu historial aparecerá aquí cuando comprimas algo.', style: _muted);
    }
    final list = history.entries.take(30).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Historial', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        TextButton(onPressed: history.clear, child: const Text('Borrar')),
      ]),
      for (final e in list)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(switch (Kind.values[e.kind]) { Kind.photo => Icons.photo_outlined, Kind.video => Icons.movie_outlined, Kind.file => Icons.description_outlined },
                color: C.muted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${e.mode} · ${_date(e.at)}', style: _muted),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('−${e.inBytes == 0 ? 0 : ((1 - e.outBytes / e.inBytes) * 100).round()} %',
                  style: const TextStyle(color: C.mint, fontWeight: FontWeight.w800)),
              Text('${fmtBytes(e.inBytes)} → ${fmtBytes(e.outBytes)}', style: _muted),
            ]),
          ]),
        ),
    ]);
  }

  Widget _diagnostics() {
    final d = Native.device;
    final lines = <String>[];
    if (Platform.isAndroid) {
      if (d == null) {
        lines.add('No se pudo leer la información del celular.');
      } else {
        lines.addAll([
          'Modelo: ${d.model}',
          'Sistema: ${d.bitsText}, Android API ${d.sdk}',
          'Memoria: ${(d.ramMb / 1024).toStringAsFixed(1)} GB · ${d.cores} núcleos',
          'HEVC por hardware: ${d.hevcHw ? 'sí' : 'no'}',
          'H.264 por hardware: ${d.h264Hw ? 'sí' : 'no'}',
        ]);
      }
    } else {
      lines.addAll([
        'GPU NVIDIA (NVENC): ${Tools.nvenc ? 'detectada' : 'no detectada'}',
        'AV1 (SVT-AV1): ${Tools.svtav1 ? 'disponible' : 'no disponible'}',
        'Calidad automática (VMAF): ${Tools.vmaf ? 'disponible' : 'no disponible'}',
        'Ghostscript (PDF): ${Tools.gs != null ? 'disponible' : 'no encontrado'}',
        '7-Zip: ${Tools.sevenZip != null ? 'disponible' : 'no encontrado'}',
      ]);
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        expandedAlignment: Alignment.centerLeft,
        title: const Text('Sobre este equipo', style: TextStyle(fontWeight: FontWeight.w700)),
        children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: _muted))],
      ),
    );
  }
}

class HeavyVideosPage extends StatefulWidget {
  const HeavyVideosPage({super.key});

  @override
  State<HeavyVideosPage> createState() => _HeavyVideosPageState();
}

class _HeavyVideosPageState extends State<HeavyVideosPage> {
  bool loading = true;
  bool denied = false;
  bool adding = false;
  List<Map<dynamic, dynamic>> videos = [];
  final picked = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ok = await Native.videoPermission();
    if (!ok) {
      if (mounted) setState(() { denied = true; loading = false; });
      return;
    }
    final v = await Native.heaviest(limit: 40);
    if (mounted) setState(() { videos = v; loading = false; });
  }

  Future<void> _add() async {
    setState(() => adding = true);
    final paths = <String>[];
    for (final i in picked) {
      final v = videos[i];
      final path = v['path'] as String?;
      String? use;
      if (path != null && path.isNotEmpty) {
        try {
          if (await File(path).exists()) {
            final f = await File(path).open();
            await f.close();
            use = path;
          }
        } catch (_) {}
      }
      use ??= await Native.copyUri('${v['uri']}');
      if (use != null) paths.add(use);
    }
    await store.addPaths(paths);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (denied) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Para buscar tus videos necesito permiso para verlos. Puedes darlo desde Ajustes → Apps → Squeeze → Permisos.',
              textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
        ),
      );
    } else if (videos.isEmpty) {
      body = const Center(child: Text('No encontré videos.', style: TextStyle(color: C.muted)));
    } else {
      body = ListView.builder(
        itemCount: videos.length,
        itemBuilder: (_, i) {
          final v = videos[i];
          final ms = (v['duration'] as num?)?.toDouble() ?? 0;
          return CheckboxListTile(
            value: picked.contains(i),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (c) => setState(() => c == true ? picked.add(i) : picked.remove(i)),
            title: Text('${v['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${fmtBytes((v['size'] as num?) ?? 0)}${ms > 0 ? '  ·  ${fmtDur(ms / 1000)}' : ''}'),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos más pesados'),
        backgroundColor: C.paper,
        surfaceTintColor: Colors.transparent,
      ),
      body: body,
      bottomNavigationBar: picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: adding ? null : _add,
                  child: Text(adding ? 'Añadiendo…' : 'Añadir ${picked.length} a Videos'),
                ),
              ),
            ),
    );
  }
}
