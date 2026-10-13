import 'generation_options.dart';

// ════════════════════════════════════════════════════════════════
// Generation requests
// ════════════════════════════════════════════════════════════════

class Txt2ImgRequest {
  final String prompt;
  final String negativePrompt;
  final int steps;
  final double cfgScale;
  final double? distilledCfgScale; // Forge / Flux
  final int width;
  final int height;
  final String samplerName;
  final String? scheduler;
  final int seed;
  final int batchSize;
  final int nIter;
  final bool restoreFaces;
  final bool tiling;
  final List<String> styles;
  final HiresFixConfig? hires;
  final RefinerConfig? refiner;
  final List<ControlNetUnit> controlNet;
  final Map<String, dynamic>? overrideSettings;

  const Txt2ImgRequest({
    required this.prompt,
    this.negativePrompt = '',
    this.steps = 20,
    this.cfgScale = 7.0,
    this.distilledCfgScale,
    this.width = 512,
    this.height = 512,
    this.samplerName = 'Euler a',
    this.scheduler,
    this.seed = -1,
    this.batchSize = 1,
    this.nIter = 1,
    this.restoreFaces = false,
    this.tiling = false,
    this.styles = const [],
    this.hires,
    this.refiner,
    this.controlNet = const [],
    this.overrideSettings,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'steps': steps,
      'cfg_scale': cfgScale,
      'width': width,
      'height': height,
      'sampler_name': samplerName,
      'seed': seed,
      'batch_size': batchSize,
      'n_iter': nIter,
      'restore_faces': restoreFaces,
      'tiling': tiling,
      'send_images': true,
      'save_images': false,
    };
    if (distilledCfgScale != null) {
      json['distilled_cfg_scale'] = distilledCfgScale;
    }
    if (scheduler != null && scheduler!.isNotEmpty) {
      json['scheduler'] = scheduler;
    }
    if (styles.isNotEmpty) json['styles'] = styles;

    if (hires != null && hires!.enabled) {
      json['enable_hr'] = true;
      json['hr_scale'] = hires!.scale;
      json['hr_upscaler'] = hires!.upscaler;
      json['hr_second_pass_steps'] = hires!.steps;
      json['denoising_strength'] = hires!.denoisingStrength;
      if (distilledCfgScale != null) {
        json['hr_distilled_cfg'] = distilledCfgScale;
      }
    }

    if (refiner != null && refiner!.checkpoint != null) {
      json['refiner_checkpoint'] = refiner!.checkpoint;
      json['refiner_switch_at'] = refiner!.switchAt;
    }

    final enabledCn = controlNet.where((u) => u.enabled).toList();
    if (enabledCn.isNotEmpty) {
      json['alwayson_scripts'] = {
        'ControlNet': {
          'args': enabledCn.map((u) => u.toApiArg()).toList(),
        },
      };
    }

    if (overrideSettings != null) {
      json['override_settings'] = overrideSettings;
      json['override_settings_restore_afterwards'] = true;
    }
    return json;
  }
}

class Img2ImgRequest {
  final String prompt;
  final String negativePrompt;
  final List<String> initImagesBase64;
  final String? maskBase64;
  final double denoisingStrength;
  final int steps;
  final double cfgScale;
  final double? distilledCfgScale;
  final int width;
  final int height;
  final String samplerName;
  final String? scheduler;
  final int seed;
  final int batchSize;
  final int nIter;
  final bool restoreFaces;
  final List<String> styles;
  final List<ControlNetUnit> controlNet;
  final int? maskBlur;
  final int? inpaintingFill;
  final bool? inpaintFullRes;
  final int? inpaintFullResPadding;
  final int? inpaintingMaskInvert;
  final int resizeMode;
  final Map<String, dynamic>? overrideSettings;

  const Img2ImgRequest({
    required this.prompt,
    this.negativePrompt = '',
    required this.initImagesBase64,
    this.maskBase64,
    this.denoisingStrength = 0.75,
    this.steps = 20,
    this.cfgScale = 7.0,
    this.distilledCfgScale,
    this.width = 512,
    this.height = 512,
    this.samplerName = 'Euler a',
    this.scheduler,
    this.seed = -1,
    this.batchSize = 1,
    this.nIter = 1,
    this.restoreFaces = false,
    this.styles = const [],
    this.controlNet = const [],
    this.maskBlur,
    this.inpaintingFill,
    this.inpaintFullRes,
    this.inpaintFullResPadding,
    this.inpaintingMaskInvert,
    this.resizeMode = 0,
    this.overrideSettings,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'init_images': initImagesBase64,
      'denoising_strength': denoisingStrength,
      'steps': steps,
      'cfg_scale': cfgScale,
      'width': width,
      'height': height,
      'sampler_name': samplerName,
      'seed': seed,
      'batch_size': batchSize,
      'n_iter': nIter,
      'restore_faces': restoreFaces,
      'resize_mode': resizeMode,
      'send_images': true,
      'save_images': false,
    };
    if (distilledCfgScale != null) {
      json['distilled_cfg_scale'] = distilledCfgScale;
    }
    if (scheduler != null && scheduler!.isNotEmpty) {
      json['scheduler'] = scheduler;
    }
    if (styles.isNotEmpty) json['styles'] = styles;

    if (maskBase64 != null) {
      json['mask'] = maskBase64;
      if (maskBlur != null) json['mask_blur'] = maskBlur;
      if (inpaintingFill != null) json['inpainting_fill'] = inpaintingFill;
      if (inpaintFullRes != null) json['inpaint_full_res'] = inpaintFullRes;
      if (inpaintFullResPadding != null) {
        json['inpaint_full_res_padding'] = inpaintFullResPadding;
      }
      if (inpaintingMaskInvert != null) {
        json['inpainting_mask_invert'] = inpaintingMaskInvert;
      }
    }

    final enabledCn = controlNet.where((u) => u.enabled).toList();
    if (enabledCn.isNotEmpty) {
      json['alwayson_scripts'] = {
        'ControlNet': {
          'args': enabledCn.map((u) => u.toApiArg()).toList(),
        },
      };
    }

    if (overrideSettings != null) {
      json['override_settings'] = overrideSettings;
      json['override_settings_restore_afterwards'] = true;
    }
    return json;
  }
}

class ExtrasSingleRequest {
  final String imageBase64;
  final int resizeMode;
  final double upscalingResize;
  final int upscalingResizeW;
  final int upscalingResizeH;
  final bool upscalingCrop;
  final String upscaler1;
  final String upscaler2;
  final double upscaler2Visibility;
  final double gfpganVisibility;
  final double codeformerVisibility;
  final double codeformerWeight;
  final bool upscaleFirst;

  const ExtrasSingleRequest({
    required this.imageBase64,
    this.resizeMode = 0,
    this.upscalingResize = 2.0,
    this.upscalingResizeW = 512,
    this.upscalingResizeH = 512,
    this.upscalingCrop = true,
    this.upscaler1 = 'None',
    this.upscaler2 = 'None',
    this.upscaler2Visibility = 0.0,
    this.gfpganVisibility = 0.0,
    this.codeformerVisibility = 0.0,
    this.codeformerWeight = 0.0,
    this.upscaleFirst = false,
  });

  Map<String, dynamic> toJson() => {
        'image': imageBase64,
        'resize_mode': resizeMode,
        'upscaling_resize': upscalingResize,
        'upscaling_resize_w': upscalingResizeW,
        'upscaling_resize_h': upscalingResizeH,
        'upscaling_crop': upscalingCrop,
        'upscaler_1': upscaler1,
        'upscaler_2': upscaler2,
        'extras_upscaler_2_visibility': upscaler2Visibility,
        'gfpgan_visibility': gfpganVisibility,
        'codeformer_visibility': codeformerVisibility,
        'codeformer_weight': codeformerWeight,
        'upscale_first': upscaleFirst,
        'show_extras_results': true,
      };
}

class ExtrasSingleResponse {
  final String? imageBase64;
  final String htmlInfo;

  const ExtrasSingleResponse({this.imageBase64, this.htmlInfo = ''});

  factory ExtrasSingleResponse.fromJson(Map<String, dynamic> j) =>
      ExtrasSingleResponse(
        imageBase64: j['image'] as String?,
        htmlInfo: j['html_info'] as String? ?? '',
      );
}

class PngInfoResponse {
  final String info;
  final Map<String, dynamic> parameters;
  final Map<String, dynamic> items;

  const PngInfoResponse({
    this.info = '',
    this.parameters = const {},
    this.items = const {},
  });

  factory PngInfoResponse.fromJson(Map<String, dynamic> j) => PngInfoResponse(
        info: j['info'] as String? ?? '',
        parameters: (j['parameters'] as Map?)?.cast<String, dynamic>() ?? {},
        items: (j['items'] as Map?)?.cast<String, dynamic>() ?? {},
      );
}

// ════════════════════════════════════════════════════════════════
// Responses
// ════════════════════════════════════════════════════════════════

class GenerationResponse {
  final List<String> images;
  final Map<String, dynamic> parameters;
  final String info;

  const GenerationResponse({
    required this.images,
    required this.parameters,
    required this.info,
  });

  factory GenerationResponse.fromJson(Map<String, dynamic> json) =>
      GenerationResponse(
        images: (json['images'] as List?)?.cast<String>() ?? <String>[],
        parameters: json['parameters'] as Map<String, dynamic>? ?? {},
        info: json['info'] as String? ?? '',
      );
}

// ════════════════════════════════════════════════════════════════
// Server data — listings
// ════════════════════════════════════════════════════════════════

class SdModel {
  final String title;
  final String modelName;
  final String? hash;
  final String? sha256;
  final String filename;

  const SdModel({
    required this.title,
    required this.modelName,
    this.hash,
    this.sha256,
    required this.filename,
  });

  factory SdModel.fromJson(Map<String, dynamic> json) => SdModel(
        title: json['title'] as String? ?? '',
        modelName: json['model_name'] as String? ?? '',
        hash: json['hash'] as String?,
        sha256: json['sha256'] as String?,
        filename: json['filename'] as String? ?? '',
      );
}

class SdSampler {
  final String name;
  final List<String> aliases;

  const SdSampler({required this.name, this.aliases = const []});

  factory SdSampler.fromJson(Map<String, dynamic> json) => SdSampler(
        name: json['name'] as String? ?? '',
        aliases: (json['aliases'] as List?)?.cast<String>() ?? [],
      );
}

class SdScheduler {
  final String name;
  final String label;

  const SdScheduler({required this.name, required this.label});

  factory SdScheduler.fromJson(Map<String, dynamic> json) => SdScheduler(
        name: json['name'] as String? ?? '',
        label: json['label'] as String? ?? json['name'] as String? ?? '',
      );
}

class SdLora {
  final String name;
  final String? alias;
  final String path;

  const SdLora({required this.name, this.alias, required this.path});

  factory SdLora.fromJson(Map<String, dynamic> json) => SdLora(
        name: json['name'] as String? ?? '',
        alias: json['alias'] as String?,
        path: json['path'] as String? ?? '',
      );
}

class SdVae {
  final String modelName;
  final String filename;

  const SdVae({required this.modelName, required this.filename});

  factory SdVae.fromJson(Map<String, dynamic> json) => SdVae(
        modelName: json['model_name'] as String? ?? '',
        filename: json['filename'] as String? ?? '',
      );
}

class SdUpscaler {
  final String name;
  final String? modelName;
  final double? scale;

  const SdUpscaler({required this.name, this.modelName, this.scale});

  factory SdUpscaler.fromJson(Map<String, dynamic> json) => SdUpscaler(
        name: json['name'] as String? ?? '',
        modelName: json['model_name'] as String?,
        scale: (json['scale'] as num?)?.toDouble(),
      );
}

class SdPromptStyle {
  final String name;
  final String prompt;
  final String negativePrompt;

  const SdPromptStyle({
    required this.name,
    this.prompt = '',
    this.negativePrompt = '',
  });

  factory SdPromptStyle.fromJson(Map<String, dynamic> json) => SdPromptStyle(
        name: json['name'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        negativePrompt: json['negative_prompt'] as String? ?? '',
      );
}

// ════════════════════════════════════════════════════════════════
// Progress & connection
// ════════════════════════════════════════════════════════════════

class GenerationProgress {
  final double progress;
  final double etaRelative;
  final Map<String, dynamic>? state;
  final String? currentImage; // base64

  const GenerationProgress({
    required this.progress,
    required this.etaRelative,
    this.state,
    this.currentImage,
  });

  factory GenerationProgress.fromJson(Map<String, dynamic> json) =>
      GenerationProgress(
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        etaRelative: (json['eta_relative'] as num?)?.toDouble() ?? 0.0,
        state: json['state'] as Map<String, dynamic>?,
        currentImage: json['current_image'] as String?,
      );
}

class ConnectionStatus {
  final bool connected;
  final String? currentModel;
  final String? error;

  /// Reachable but not usable as-is (e.g. no models installed).
  final String? warning;

  const ConnectionStatus({
    required this.connected,
    this.currentModel,
    this.error,
    this.warning,
  });
}
