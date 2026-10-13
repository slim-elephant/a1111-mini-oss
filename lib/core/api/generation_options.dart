// ─── LoRA selection ────────────────────────────────────────────────
class LoraSelection {
  final String name;
  final double weight;

  const LoraSelection({required this.name, this.weight = 1.0});

  Map<String, dynamic> toJson() => {'name': name, 'weight': weight};
  factory LoraSelection.fromJson(Map<String, dynamic> j) => LoraSelection(
        name: j['name'] as String,
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
      );

  /// `<lora:name:weight>` token to inject into the prompt.
  String toPromptToken() =>
      '<lora:$name:${weight.toStringAsFixed(2)}>';
}

// ─── Hires Fix ─────────────────────────────────────────────────────
class HiresFixConfig {
  final bool enabled;
  final double scale;
  final int steps; // 0 = same as base
  final double denoisingStrength;
  final String upscaler;

  const HiresFixConfig({
    this.enabled = false,
    this.scale = 1.5,
    this.steps = 0,
    this.denoisingStrength = 0.5,
    this.upscaler = 'Latent',
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'scale': scale,
        'steps': steps,
        'denoising_strength': denoisingStrength,
        'upscaler': upscaler,
      };
  factory HiresFixConfig.fromJson(Map<String, dynamic> j) => HiresFixConfig(
        enabled: j['enabled'] as bool? ?? false,
        scale: (j['scale'] as num?)?.toDouble() ?? 1.5,
        steps: j['steps'] as int? ?? 0,
        denoisingStrength:
            (j['denoising_strength'] as num?)?.toDouble() ?? 0.5,
        upscaler: j['upscaler'] as String? ?? 'Latent',
      );

  HiresFixConfig copyWith({
    bool? enabled,
    double? scale,
    int? steps,
    double? denoisingStrength,
    String? upscaler,
  }) =>
      HiresFixConfig(
        enabled: enabled ?? this.enabled,
        scale: scale ?? this.scale,
        steps: steps ?? this.steps,
        denoisingStrength: denoisingStrength ?? this.denoisingStrength,
        upscaler: upscaler ?? this.upscaler,
      );
}

// ─── Refiner ───────────────────────────────────────────────────────
class RefinerConfig {
  final String? checkpoint;
  final double switchAt;

  const RefinerConfig({this.checkpoint, this.switchAt = 0.8});

  Map<String, dynamic> toJson() => {
        'checkpoint': checkpoint,
        'switch_at': switchAt,
      };
  factory RefinerConfig.fromJson(Map<String, dynamic> j) => RefinerConfig(
        checkpoint: j['checkpoint'] as String?,
        switchAt: (j['switch_at'] as num?)?.toDouble() ?? 0.8,
      );
}

// ─── ControlNet unit ───────────────────────────────────────────────
class ControlNetUnit {
  final bool enabled;
  final String? module; // preprocessor, e.g. "canny"
  final String? model;  // e.g. "control_v11p_sd15_canny [d14c016b]"
  final String? imageBase64; // raw base64 (no data: prefix)
  final double weight;
  final double guidanceStart;
  final double guidanceEnd;
  final int processorRes;
  final int controlMode; // 0=balanced, 1=prompt, 2=controlnet
  final int resizeMode;  // 0,1,2

  const ControlNetUnit({
    this.enabled = true,
    this.module,
    this.model,
    this.imageBase64,
    this.weight = 1.0,
    this.guidanceStart = 0.0,
    this.guidanceEnd = 1.0,
    this.processorRes = 512,
    this.controlMode = 0,
    this.resizeMode = 1,
  });

  ControlNetUnit copyWith({
    bool? enabled,
    String? module,
    String? model,
    String? imageBase64,
    double? weight,
    double? guidanceStart,
    double? guidanceEnd,
    int? processorRes,
    int? controlMode,
    int? resizeMode,
  }) =>
      ControlNetUnit(
        enabled: enabled ?? this.enabled,
        module: module ?? this.module,
        model: model ?? this.model,
        imageBase64: imageBase64 ?? this.imageBase64,
        weight: weight ?? this.weight,
        guidanceStart: guidanceStart ?? this.guidanceStart,
        guidanceEnd: guidanceEnd ?? this.guidanceEnd,
        processorRes: processorRes ?? this.processorRes,
        controlMode: controlMode ?? this.controlMode,
        resizeMode: resizeMode ?? this.resizeMode,
      );

  /// Serialized for `alwayson_scripts.ControlNet.args[i]`.
  Map<String, dynamic> toApiArg() => {
        'enabled': enabled,
        'image': imageBase64,
        'module': module ?? 'none',
        'model': model ?? 'None',
        'weight': weight,
        'guidance_start': guidanceStart,
        'guidance_end': guidanceEnd,
        'processor_res': processorRes,
        'control_mode': controlMode,
        'resize_mode': resizeMode,
        'pixel_perfect': true,
      };

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'module': module,
        'model': model,
        'image_base64': imageBase64,
        'weight': weight,
        'guidance_start': guidanceStart,
        'guidance_end': guidanceEnd,
        'processor_res': processorRes,
        'control_mode': controlMode,
        'resize_mode': resizeMode,
      };
  factory ControlNetUnit.fromJson(Map<String, dynamic> j) => ControlNetUnit(
        enabled: j['enabled'] as bool? ?? true,
        module: j['module'] as String?,
        model: j['model'] as String?,
        imageBase64: j['image_base64'] as String?,
        weight: (j['weight'] as num?)?.toDouble() ?? 1.0,
        guidanceStart: (j['guidance_start'] as num?)?.toDouble() ?? 0.0,
        guidanceEnd: (j['guidance_end'] as num?)?.toDouble() ?? 1.0,
        processorRes: j['processor_res'] as int? ?? 512,
        controlMode: j['control_mode'] as int? ?? 0,
        resizeMode: j['resize_mode'] as int? ?? 1,
      );
}
