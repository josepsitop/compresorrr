import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'compressor.dart';
import 'history.dart';
import 'models.dart';
import 'presets.dart';

/// Menú del clic derecho de Windows ("Comprimir con Squeeze"), solo para el usuario actual.
class WinContext {
  static const _key = r'HKCU\Software\Classes\*\shell\Squeeze';

  static Future<bool> installed() async {
    try {
      return (await Process.run('reg', ['query', _key])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> install() async {
    final exe = Platform.resolvedExecutable;
    await Process.run('reg', ['add', _key, '/ve', '/d', 'Comprimir con Squeeze', '/f']);
    await Process.run('reg', ['add', _key, '/v', 'Icon', '/d', exe, '/f']);
    await Process.run('reg', ['add', '$_key\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
  }

  static Future<void> remove() async {
    await Process.run('reg', ['delete', _key, '/f']);
  }
}

/// Carpeta vigilada: todo video (y foto, si se activa) que caiga en la carpeta se
/// comprime solo y el resultado va a la subcarpeta "Squeeze".
class FolderWatcher extends ChangeNotifier {
  bool running = false;
  String? folder;
  String videoPresetId = 'balanced';
  bool photos = true;
  final log = <String>[];

  StreamSubscription<FileSystemEvent>? _sub;
  final _queue = <String>[];
  final _seen = <String>{};
  bool _busy = false;
  Compressor? _comp;

  void _log(String s) {
    log.insert(0, s);
    if (log.length > 30) log.removeLast();
    notifyListeners();
  }

  Future<void> start(String dir) async {
    await stop();
    folder = dir;
    running = true;
    _comp = Compressor();
    _sub = Directory(dir)
        .watch(events: FileSystemEvent.create | FileSystemEvent.modify | FileSystemEvent.move)
        .listen(_onEvent);
    _log('Vigilando $dir');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _queue.clear();
    if (running) {
      running = false;
      await _comp?.cancel();
      _log('Detenido');
    }
  }

  void _onEvent(FileSystemEvent e) {
    if (e.isDirectory || e is FileSystemDeleteEvent) return;
    final path = e.path;
    final name = p.basename(path);
    if (name.contains('_squeeze') || name.contains('_muestra')) return;
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    final ok = videoExts.contains(ext) || (photos && imageExts.contains(ext));
    if (!ok || !_seen.add(path)) return;
    _queue.add(path);
    _pump();
  }

  Future<bool> _stable(String path) async {
    var last = -1;
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final s = await File(path).length();
        if (s > 0 && s == last) {
          final raf = await File(path).open();
          await raf.close();
          return true;
        }
        last = s;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    while (_queue.isNotEmpty && running) {
      final path = _queue.removeAt(0);
      final name = p.basename(path);
      try {
        if (!await _stable(path)) {
          _log('No pude leer $name (¿sigue copiándose?)');
          continue;
        }
        final it = Item(path, name, await File(path).length());
        final kind = it.guessKind;
        final preset = kind == Kind.video
            ? kAllPresets.firstWhere((x) => x.kind == Kind.video && x.id == videoPresetId)
            : kAllPresets.firstWhere((x) => x.id == 'p_bal');
        final out = p.join(folder!, 'Squeeze');
        await Directory(out).create(recursive: true);
        _log('Comprimiendo $name…');
        final r = await _comp!.run(it, Options(preset), outDirOverride: out);
        if (r.ok) {
          _log('Listo: $name  −${(r.saved * 100).round()} %');
          await history.add(r, preset.name, kind);
        } else {
          _log('$name: ${r.error ?? r.note ?? 'sin cambios'}');
        }
      } catch (e) {
        _log('Error con $name: $e');
      }
    }
    _busy = false;
  }
}

final watcher = FolderWatcher();
