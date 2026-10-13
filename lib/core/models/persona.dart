import 'dart:convert';
import '../api/generation_options.dart';

class LoraConfig {
  final String name;
  final double weight;

  const LoraConfig({required this.name, this.weight = 1.0});

  String toPromptTag() => '<lora:$name:$weight>';

  Map<String, dynamic> toMap() => {'name': name, 'weight': weight};

  factory LoraConfig.fromMap(Map<String, dynamic> map) => LoraConfig(
        name: map['name'] as String,
        weight: (map['weight'] as num).toDouble(),
      );

  static List<LoraConfig> fromJsonString(String json) {
    final list = jsonDecode(json) as List;
    return list.map((e) => LoraConfig.fromMap(e as Map<String, dynamic>)).toList();
  }

  static String toJsonString(List<LoraConfig> configs) =>
      jsonEncode(configs.map((e) => e.toMap()).toList());
}

class Persona {
  final String id;
  final String name;
  final String description;
  final String? avatarPath;
  final String? profileId;
  final String? modelName;
  final List<LoraConfig> loraConfigs;
  final List<String> styleNames;
  final String? scheduler;
  final double distilledCfgScale;
  final String vae;
  final int? clipSkip;
  final String samplerName;
  final int steps;
  final double cfgScale;
  final int seed;
  final int width;
  final int height;
  final bool restoreFaces;
  final bool hiresFix;
  final double hiresScale;
  final int hiresSteps;
  final double hiresDenoising;
  final String hiresUpscaler;
  final List<ControlNetUnit> controlNetUnits;
  final double denoisingStrength;
  final DateTime createdAt;

  const Persona({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarPath,
    this.profileId,
    this.modelName,
    this.loraConfigs = const [],
    this.styleNames = const [],
    this.scheduler,
    this.distilledCfgScale = 3.5,
    this.vae = 'Automatic',
    this.clipSkip,
    this.samplerName = 'Euler a',
    this.steps = 20,
    this.cfgScale = 7.0,
    this.seed = -1,
    this.width = 512,
    this.height = 512,
    this.restoreFaces = false,
    this.hiresFix = false,
    this.hiresScale = 1.5,
    this.hiresSteps = 0,
    this.hiresDenoising = 0.5,
    this.hiresUpscaler = 'Latent',
    this.controlNetUnits = const [],
    this.denoisingStrength = 0.7,
    required this.createdAt,
  });

  String get loraPromptSuffix =>
      loraConfigs.map((l) => l.toPromptTag()).join(' ');

  Persona copyWith({
    String? name,
    String? description,
    String? avatarPath,
    String? profileId,
    String? modelName,
    List<LoraConfig>? loraConfigs,
    List<String>? styleNames,
    String? scheduler,
    double? distilledCfgScale,
    String? vae,
    int? clipSkip,
    String? samplerName,
    int? steps,
    double? cfgScale,
    int? seed,
    int? width,
    int? height,
    bool? restoreFaces,
    bool? hiresFix,
    double? hiresScale,
    int? hiresSteps,
    double? hiresDenoising,
    String? hiresUpscaler,
    List<ControlNetUnit>? controlNetUnits,
    double? denoisingStrength,
  }) =>
      Persona(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        avatarPath: avatarPath ?? this.avatarPath,
        profileId: profileId ?? this.profileId,
        modelName: modelName ?? this.modelName,
        loraConfigs: loraConfigs ?? this.loraConfigs,
        styleNames: styleNames ?? this.styleNames,
        scheduler: scheduler ?? this.scheduler,
        distilledCfgScale: distilledCfgScale ?? this.distilledCfgScale,
        vae: vae ?? this.vae,
        clipSkip: clipSkip ?? this.clipSkip,
        samplerName: samplerName ?? this.samplerName,
        steps: steps ?? this.steps,
        cfgScale: cfgScale ?? this.cfgScale,
        seed: seed ?? this.seed,
        width: width ?? this.width,
        height: height ?? this.height,
        restoreFaces: restoreFaces ?? this.restoreFaces,
        hiresFix: hiresFix ?? this.hiresFix,
        hiresScale: hiresScale ?? this.hiresScale,
        hiresSteps: hiresSteps ?? this.hiresSteps,
        hiresDenoising: hiresDenoising ?? this.hiresDenoising,
        hiresUpscaler: hiresUpscaler ?? this.hiresUpscaler,
        controlNetUnits: controlNetUnits ?? this.controlNetUnits,
        denoisingStrength: denoisingStrength ?? this.denoisingStrength,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'avatar_path': avatarPath,
        'profile_id': profileId,
        'model_name': modelName,
        'lora_configs': LoraConfig.toJsonString(loraConfigs),
        'style_names': jsonEncode(styleNames),
        'scheduler': scheduler,
        'distilled_cfg_scale': distilledCfgScale,
        'vae': vae,
        'clip_skip': clipSkip,
        'sampler_name': samplerName,
        'steps': steps,
        'cfg_scale': cfgScale,
        'seed': seed,
        'width': width,
        'height': height,
        'restore_faces': restoreFaces ? 1 : 0,
        'hires_fix': hiresFix ? 1 : 0,
        'hires_scale': hiresScale,
        'hires_steps': hiresSteps,
        'hires_denoising': hiresDenoising,
        'hires_upscaler': hiresUpscaler,
        'controlnet_units': jsonEncode(controlNetUnits.map((u) => u.toApiArg()).toList()),
        'denoising_strength': denoisingStrength,
        'created_at': createdAt.toIso8601String(),
      };

  factory Persona.fromMap(Map<String, dynamic> map) => Persona(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String? ?? '',
        avatarPath: map['avatar_path'] as String?,
        profileId: map['profile_id'] as String?,
        modelName: map['model_name'] as String?,
        loraConfigs: LoraConfig.fromJsonString(map['lora_configs'] as String? ?? '[]'),
        styleNames: (jsonDecode(map['style_names'] as String? ?? '[]') as List)
          .map((e) => e.toString())
          .toList(),
        scheduler: map['scheduler'] as String?,
        distilledCfgScale:
          (map['distilled_cfg_scale'] as num?)?.toDouble() ?? 3.5,
        vae: map['vae'] as String? ?? 'Automatic',
        clipSkip: map['clip_skip'] as int?,
        samplerName: map['sampler_name'] as String? ?? 'Euler a',
        steps: map['steps'] as int? ?? 20,
        cfgScale: (map['cfg_scale'] as num?)?.toDouble() ?? 7.0,
        seed: map['seed'] as int? ?? -1,
        width: map['width'] as int? ?? 512,
        height: map['height'] as int? ?? 512,
        restoreFaces: (map['restore_faces'] as int?) == 1,
        hiresFix: (map['hires_fix'] as int?) == 1,
        hiresScale: (map['hires_scale'] as num?)?.toDouble() ?? 1.5,
        hiresSteps: map['hires_steps'] as int? ?? 0,
        hiresDenoising: (map['hires_denoising'] as num?)?.toDouble() ?? 0.5,
        hiresUpscaler: map['hires_upscaler'] as String? ?? 'Latent',
        controlNetUnits: _parseControlNetUnits(map['controlnet_units'] as String?),
        denoisingStrength: (map['denoising_strength'] as num?)?.toDouble() ?? 0.7,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  static List<ControlNetUnit> _parseControlNetUnits(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((entry) {
        final map = entry as Map<String, dynamic>;
        return ControlNetUnit(
          enabled: (map['enabled'] as bool?) ?? true,
          module: map['module'] as String? ?? 'none',
          model: map['model'] as String? ?? 'None',
          weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
          guidanceStart: (map['guidance_start'] as num?)?.toDouble() ?? 0.0,
          guidanceEnd: (map['guidance_end'] as num?)?.toDouble() ?? 1.0,
          processorRes: (map['processor_res'] as num?)?.toInt() ?? 512,
          controlMode: (map['control_mode'] as num?)?.toInt() ?? 0,
          resizeMode: (map['resize_mode'] as num?)?.toInt() ?? 1,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
