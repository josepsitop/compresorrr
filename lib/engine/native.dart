import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.is64,
    required this.ramMb,
    required this.cores,
    required this.sdk,
    required this.hevcHw,
    required this.h264Hw,
    required this.model,
  });
  final bool is64;
  final int ramMb;
  final int cores;
  final int sdk;
  final bool hevcHw;
  final bool h264Hw;
  final String model;

  /// Celular justo: 32 bits, poca memoria o pocos núcleos.
  bool get weak => !is64 || ramMb < 3000 || cores <= 4;

  String get bitsText => is64 ? '64 bits' : '32 bits';

  /// Aviso corto para un modo de video, o null si no hay nada que advertir.
  String? noteFor(Preset p, String codec, Probe? pr) {
    final software = p.id != 'hw' || (codec == 'hevc' ? !hevcHw : !h264Hw);
    if (p.id == 'hw') {
      if (codec == 'hevc' && !hevcHw) {
        return 'Este celular no tiene HEVC por hardware: usará el modo de respaldo, que es lento.';
      }
      if (codec == 'h264' && !h264Hw) {
        return 'Este celular no tiene H.264 por hardware: usará el modo de respaldo.';
      }
      return null;
    }
    if (software && pr != null && pr.height >= 2000 && ramMb < 4500) {
      return 'Video 4K y poca memoria: la app podría cerrarse. Baja la resolución a 1080p.';
    }
    if (codec == 'hevc' && weak && (p.id == 'visual' || p.id == 'max' || p.id == 'balanced')) {
      final why = !is64 ? 'Este celular es de 32 bits' : 'Este celular es modesto';
      return '$why: HEVC por software puede tardar muchísimo. Mejor Rápido por hardware o Compatible.';
    }
    return null;
  }
}

/// Puente con el código nativo de Android (MainActivity.kt). En PC no hace nada.
class Native {
  static const _share = MethodChannel('squeeze/share');
  static const _sys = MethodChannel('squeeze/system');
  static DeviceInfo? device;

  static bool get on => Platform.isAndroid;

  static Future<void> init(void Function(List<String> paths) onShared) async {
    if (!on) return;
    _share.setMethodCallHandler((call) async {
      if (call.method == 'shared') onShared(List<String>.from(call.arguments as List));
    });
    try {
      final first = await _share.invokeMethod<List<dynamic>>('initial');
      if (first != null && first.isNotEmpty) onShared(first.cast<String>());
    } catch (_) {}
  }

  static Future<DeviceInfo?> loadDevice() async {
    if (!on) return null;
    if (device != null) return device;
    try {
      final m = await _sys.invokeMapMethod<String, dynamic>('device');
      if (m == null) return null;
      device = DeviceInfo(
        is64: m['is64'] == true,
        ramMb: (m['ramMb'] as num?)?.toInt() ?? 0,
        cores: (m['cores'] as num?)?.toInt() ?? 8,
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        hevcHw: m['hevcHw'] == true,
        h264Hw: m['h264Hw'] == true,
        model: '${m['model'] ?? ''}',
      );
    } catch (_) {}
    return device;
  }

  static Future<bool> charging() async {
    if (!on) return true;
    try {
      return await _sys.invokeMethod<bool>('charging') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> serviceStart(String text) => _service('serviceStart', text, -1);
  static Future<void> serviceUpdate(String text, int pct) => _service('serviceUpdate', text, pct);

  static Future<void> _service(String m, String text, int pct) async {
    if (!on) return;
    try {
      await _sys.invokeMethod(m, {'text': text, 'progress': pct});
    } catch (_) {}
  }

  static Future<void> serviceStop() async {
    if (!on) return;
    try {
      await _sys.invokeMethod('serviceStop');
    } catch (_) {}
  }

  static Future<bool> videoPermission() async {
    if (!on) return false;
    try {
      return await _sys.invokeMethod<bool>('videoPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<dynamic, dynamic>>> heaviest({int limit = 40}) async {
    if (!on) return [];
    try {
      return await _sys.invokeListMethod<Map<dynamic, dynamic>>('heaviest', {'limit': limit}) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<String?> copyUri(String uri) async {
    if (!on) return null;
    try {
      return await _sys.invokeMethod<String>('copyUri', {'uri': uri});
    } catch (_) {
      return null;
    }
  }
}
