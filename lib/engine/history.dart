import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class HistoryEntry {
  HistoryEntry(this.name, this.kind, this.mode, this.inBytes, this.outBytes, this.at);
  final String name, mode;
  final int kind, inBytes, outBytes, at;

  Map<String, dynamic> toJson() =>
      {'n': name, 'k': kind, 'm': mode, 'i': inBytes, 'o': outBytes, 't': at};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
      '${j['n']}', (j['k'] as num).toInt(), '${j['m']}', (j['i'] as num).toInt(), (j['o'] as num).toInt(), (j['t'] as num).toInt());
}

class History extends ChangeNotifier {
  final entries = <HistoryEntry>[]; // la más reciente primero
  bool _loaded = false;

  int get saved => entries.fold(0, (a, e) => a + max(0, e.inBytes - e.outBytes));

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'historial.json'));

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        entries.addAll(list.map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map))));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await (await _file()).writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> add(Outcome r, String mode, Kind kind) async {
    if (!r.ok) return;
    await load();
    entries.insert(0, HistoryEntry(r.item.name, kind.index, mode, r.inBytes, r.outBytes, DateTime.now().millisecondsSinceEpoch));
    if (entries.length > 200) entries.removeRange(200, entries.length);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    entries.clear();
    notifyListeners();
    await _save();
  }
}

final history = History();
