import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'apple_ml_models.dart';

/// Native background URLSession + Live Activity bridge for Apple ML downloads.
class AppleMlDownloadPlatform {
  AppleMlDownloadPlatform._();
  static final AppleMlDownloadPlatform instance = AppleMlDownloadPlatform._();

  static const _channel = MethodChannel('net.neuro9.a1111mini/model_download');

  final Map<String, _ActiveJob> _active = {};
  _PendingNativeEvent? _pending;
  bool _handlerReady = false;

  bool get isSupported => !kIsWeb && Platform.isIOS;

  void ensureInitialized() {
    if (_handlerReady) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map
          ? Map<String, dynamic>.from(call.arguments as Map)
          : <String, dynamic>{
              if (call.arguments is String) 'jobId': call.arguments,
            };
      _dispatch(call.method, args);
    });
  }

  void _dispatch(String method, Map<String, dynamic> args) {
    final jobId = args['jobId'] as String?;
    if (jobId == null) return;
    final job = _active[jobId];
    if (job == null) {
      if (method != 'onProgress') {
        _pending = _PendingNativeEvent(method: method, args: args);
      }
      return;
    }
    switch (method) {
      case 'onProgress':
        job.onProgress(args);
        break;
      case 'onComplete':
        _active.remove(jobId)?.complete(args['destRoot'] as String?);
        break;
      case 'onError':
        _active.remove(jobId)?.completeError(
              args['message'] as String? ?? 'Download failed',
            );
        break;
      case 'onCancelled':
        _active.remove(jobId)?.completeError('cancelled');
        break;
    }
  }

  Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> activeJob() async {
    if (!isSupported) return null;
    ensureInitialized();
    try {
      final raw = await _channel.invokeMethod<dynamic>('activeJob');
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (_) {}
    return null;
  }

  Future<String> downloadJob({
    required String jobId,
    required String displayName,
    required String destRoot,
    required List<Map<String, dynamic>> files,
    required void Function(Map<String, dynamic> payload) onProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Background downloads are iOS-only');
    }
    ensureInitialized();
    final completer = Completer<String>();
    _active[jobId] = _ActiveJob(
      completer: completer,
      onProgress: onProgress,
    );
    try {
      await _channel.invokeMethod('startJob', {
        'jobId': jobId,
        'displayName': displayName,
        'destRoot': destRoot,
        'files': files,
      });
      return await completer.future;
    } finally {
      _active.remove(jobId);
    }
  }

  Future<String> attachJob({
    required String jobId,
    required void Function(Map<String, dynamic> payload) onProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Background downloads are iOS-only');
    }
    ensureInitialized();
    final pending = _pending;
    if (pending != null && pending.args['jobId'] == jobId) {
      _pending = null;
      if (pending.method == 'onComplete') {
        return pending.args['destRoot'] as String? ?? '';
      }
      if (pending.method == 'onCancelled') {
        throw Exception('cancelled');
      }
      throw Exception(pending.args['message'] as String? ?? 'Download failed');
    }
    final completer = Completer<String>();
    _active[jobId] = _ActiveJob(
      completer: completer,
      onProgress: onProgress,
    );
    try {
      return await completer.future;
    } finally {
      _active.remove(jobId);
    }
  }

  Future<void> cancel(String jobId) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('cancelJob', {'jobId': jobId});
    } catch (_) {}
    _active.remove(jobId)?.completeError('cancelled');
  }
}

class _PendingNativeEvent {
  final String method;
  final Map<String, dynamic> args;

  _PendingNativeEvent({required this.method, required this.args});
}

class _ActiveJob {
  final Completer<String> completer;
  final void Function(Map<String, dynamic> payload) onProgress;

  _ActiveJob({
    required this.completer,
    required this.onProgress,
  });

  void complete(String? destRoot) {
    if (!completer.isCompleted) {
      completer.complete(destRoot ?? '');
    }
  }

  void completeError(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }
}

List<Map<String, dynamic>> appleMlNativeDownloadFiles({
  required String hfRepo,
  required List<HfRemoteFile> files,
}) {
  return [
    for (final file in files)
      {
        'url':
            'https://huggingface.co/$hfRepo/resolve/main/${file.path}?download=true',
        'relativePath': file.path,
        'size': file.size,
      },
  ];
}
