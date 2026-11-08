import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

class OpenRequest {
  OpenRequest(this.kind, this.items);
  final Kind kind;
  final List<Item> items;
}

/// Estado compartido: listas de cada pestaña, pestaña activa y peticiones
/// de abrir la hoja de compresión (desde "Compartir", clic derecho, etc.).
class Store extends ChangeNotifier {
  final Map<Kind, List<Item>> items = {Kind.photo: [], Kind.video: [], Kind.file: []};
  int tab = 1;
  OpenRequest? request;

  static int tabOf(Kind k) => switch (k) { Kind.photo => 0, Kind.video => 1, Kind.file => 2 };

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void remove(Kind k, Item it) {
    items[k]!.remove(it);
    notifyListeners();
  }

  void clearAll() {
    for (final l in items.values) {
      l.clear();
    }
    notifyListeners();
  }

  void addItems(Kind k, List<Item> list) {
    for (final it in list) {
      if (!items[k]!.any((e) => e.path == it.path)) items[k]!.add(it);
    }
    notifyListeners();
  }

  Future<void> addPaths(List<String> paths, {bool open = false}) async {
    final added = <Kind, List<Item>>{};
    for (final path in paths) {
      try {
        final f = File(path);
        if (!await f.exists()) continue;
        final it = Item(path, p.basename(path), await f.length());
        final k = it.guessKind;
        if (items[k]!.any((e) => e.path == path)) continue;
        items[k]!.add(it);
        (added[k] ??= []).add(it);
      } catch (_) {}
    }
    if (added.isNotEmpty) {
      final k = added.keys.first;
      tab = tabOf(k);
      if (open) request = OpenRequest(k, added[k]!);
    }
    notifyListeners();
  }
}

final store = Store();
