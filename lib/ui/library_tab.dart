import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/store.dart';
import '../engine/tools.dart';
import 'fx.dart';
import 'more_tab.dart';
import 'preset_sheet.dart';
import 'theme.dart';

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key, required this.kind});
  final Kind kind;

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  bool _dragging = false;

  List<Item> get items => store.items[widget.kind]!;

  String get _title => switch (widget.kind) { Kind.photo => 'Fotos', Kind.video => 'Videos', Kind.file => 'Archivos' };
  String get _subtitle => switch (widget.kind) {
        Kind.photo => 'Baja el peso sin que se note.',
        Kind.video => 'Cambia de códec o formato y prueba antes de comprimir.',
        Kind.file => 'PDF, documentos y cualquier otro formato.',
      };
  String get _cta => switch (widget.kind) {
        Kind.photo => 'Elegir fotos',
        Kind.video => 'Elegir videos',
        Kind.file => 'Elegir archivos',
      };
  IconData get _icon => switch (widget.kind) {
        Kind.photo => Icons.photo_outlined,
        Kind.video => Icons.movie_outlined,
        Kind.file => Icons.description_outlined,
      };

  Future<void> _pick() async {
    final type = switch (widget.kind) {
      Kind.photo => FileType.image,
      Kind.video => FileType.video,
      Kind.file => FileType.any,
    };
    final r = await FilePicker.platform.pickFiles(type: type, allowMultiple: true);
    if (r == null) return;
    store.addItems(widget.kind, [
      for (final f in r.files)
        if (f.path != null) Item(f.path!, f.name, f.size),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(animation: store, builder: (_, __) => _content(context));
    if (!Tools.isPc) return body;
    // En PC se pueden arrastrar archivos desde el explorador.
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (d) {
        setState(() => _dragging = false);
        store.addPaths([for (final f in d.files) f.path]);
      },
      child: Stack(children: [
        body,
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: C.blue.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: C.blue, width: 2),
                ),
                child: const Center(
                  child: Text('Suelta aquí para añadir', style: TextStyle(color: C.blue, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _content(BuildContext context) {
    final th = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title, style: th.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(height: 4),
              Text(_subtitle, style: const TextStyle(color: C.muted, fontSize: 15)),
              const SizedBox(height: 20),
              GradientButton(label: _cta, icon: Icons.add_rounded, onTap: _pick),
              if (widget.kind == Kind.video && Platform.isAndroid)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => openHeavyVideos(context),
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: const Text('Buscar los videos más pesados del teléfono'),
                  ),
                )
              else
                const SizedBox(height: 12),
              Expanded(child: items.isEmpty ? _empty() : _list()),
              if (items.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => showPresetSheet(context, widget.kind, List.of(items)),
                      icon: const Icon(Icons.layers_outlined),
                      label: Text('Comprimir los ${items.length} juntos'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: C.blue.withValues(alpha: .08), shape: BoxShape.circle),
              child: Icon(_icon, size: 38, color: C.blue),
            ),
            const SizedBox(height: 14),
            Text(Tools.isPc ? 'Elige o arrastra tus archivos aquí.' : 'Aquí aparecerán tus archivos.',
                style: const TextStyle(color: C.muted, fontSize: 15)),
          ],
        ),
      );

  Widget _list() => ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: C.line),
        itemBuilder: (_, i) {
          final it = items[i];
          return InkWell(
            onTap: () => showPresetSheet(context, widget.kind, [it]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  _thumb(it),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text('${fmtBytes(it.bytes)}  ·  toca para elegir cómo comprimir',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: C.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.close_rounded, color: C.muted),
                    onPressed: () => store.remove(widget.kind, it),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _thumb(Item it) {
    final fallback = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: C.blue.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
      child: Icon(it.isPdf ? Icons.picture_as_pdf_outlined : _icon, color: C.blue),
    );
    if (widget.kind != Kind.photo) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(File(it.path),
          width: 52, height: 52, fit: BoxFit.cover, cacheWidth: 104, errorBuilder: (_, __, ___) => fallback),
    );
  }
}
