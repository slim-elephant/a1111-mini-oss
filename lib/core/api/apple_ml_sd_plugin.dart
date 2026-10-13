import 'dart:io';
import 'package:flutter/services.dart';

class AppleMlProgress {
  final String stage;
  final int step;
  final int stepCount;
  final String? message;

  const AppleMlProgress({
    required this.stage,
    this.step = 0,
    this.stepCount = 0,
    this.message,
  });

  double get fraction {
    if (stage == 'loading') return 0.02;
    if (stepCount <= 0) return 0;
    return (step / stepCount).clamp(0.0, 0.99);
  }

  factory AppleMlProgress.fromMap(dynamic raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return AppleMlProgress(
      stage: map['stage'] as String? ?? 'generating',
      step: (map['step'] as num?)?.toInt() ?? 0,
      stepCount: (map['stepCount'] as num?)?.toInt() ?? 0,
      message: map['message'] as String?,
    );
  }
}

double appleMlFraction(AppleMlProgress event) {
  if (event.stage == 'loading') {
    if (event.stepCount <= 0) return 0.02;
    return (event.step / event.stepCount * 0.25).clamp(0.02, 0.25);
  }
  return (0.25 + event.fraction * 0.75).clamp(0.0, 0.99);
}

class AppleMlGenerateResult {
  final String path;
  final int seed;
  final int width;
  final int height;

  const AppleMlGenerateResult({
    required this.path,
    required this.seed,
    required this.width,
    required this.height,
  });
}

class AppleMlSdPlugin {
  static const _channel = MethodChannel('net.neuro9.a1111mini/apple_ml_sd');
  static const _events = EventChannel('net.neuro9.a1111mini/apple_ml_sd_progress');

  static Stream<AppleMlProgress> progress() {
    return _events.receiveBroadcastStream().map(AppleMlProgress.fromMap);
  }

  static Future<bool> isAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String> osVersion() async {
    if (!Platform.isIOS) return '';
    try {
      return await _channel.invokeMethod<String>('osVersion') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  static Future<bool> isCompiled(String resourcesPath) async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isCompiled', {
        'resourcesPath': resourcesPath,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> install({
    required String resourcesPath,
    required String variant,
    required String displayName,
  }) async {
    await _channel.invokeMethod<void>('install', {
      'resourcesPath': resourcesPath,
      'variant': variant,
      'displayName': displayName,
    });
  }

  static Future<void> load({
    required String resourcesPath,
    required String variant,
  }) async {
    await _channel.invokeMethod<void>('load', {
      'resourcesPath': resourcesPath,
      'variant': variant,
    });
  }

  static Future<AppleMlGenerateResult> generate({
    required String prompt,
    String negativePrompt = '',
    required int steps,
    required double cfgScale,
    required int seed,
    String scheduler = 'dpmSolver',
    int originalSize = 512,
  }) async {
    final raw = await _channel.invokeMethod<dynamic>('generate', {
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'steps': steps,
      'cfgScale': cfgScale,
      'seed': seed,
      'scheduler': scheduler,
      'originalSize': originalSize,
    });
    final map = Map<String, dynamic>.from(raw as Map);
    return AppleMlGenerateResult(
      path: map['path'] as String,
      seed: (map['seed'] as num?)?.toInt() ?? seed,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> interrupt() async {
    try {
      await _channel.invokeMethod<void>('interrupt');
    } on MissingPluginException {
      // Plugin absent on Android / tests.
    } on PlatformException {
      // Ignore — generation may already have finished.
    }
  }

  static Future<void> unload() async {
    try {
      await _channel.invokeMethod<void>('unload');
    } on MissingPluginException {
      // Plugin absent on Android / tests.
    }
  }
}
