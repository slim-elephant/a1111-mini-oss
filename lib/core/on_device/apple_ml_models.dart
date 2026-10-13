/// Hugging Face Core ML packages that run through Apple's StableDiffusion Swift
/// pipeline (`apple/ml-stable-diffusion`).
enum AppleMlPipelineKind { sd15, sdxl }

class AppleMlCatalogModel {
  final String id;
  final String name;
  final String subtitle;
  final String hfRepo;
  final String treePrefix;
  final AppleMlPipelineKind pipeline;
  final int recommendedWidth;
  final int recommendedHeight;
  final int recommendedSteps;
  final double recommendedCfg;
  final int minIosMajor;
  final int minIosMinor;
  final int approxBytes;
  final String licenseNote;

  const AppleMlCatalogModel({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.hfRepo,
    required this.treePrefix,
    required this.pipeline,
    required this.recommendedWidth,
    required this.recommendedHeight,
    required this.recommendedSteps,
    required this.recommendedCfg,
    required this.minIosMajor,
    this.minIosMinor = 0,
    required this.approxBytes,
    this.licenseNote = 'Weights from Hugging Face under each repo’s license.',
  });

  String get sizeLabel {
    final gb = approxBytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  String get sizeHint =>
      '$recommendedWidth×$recommendedHeight · $recommendedSteps steps';

  bool get isSdxl => pipeline == AppleMlPipelineKind.sdxl;
}

class AppleMlCatalog {
  static const models = <AppleMlCatalogModel>[
    AppleMlCatalogModel(
      id: 'sd15-ane',
      name: 'Stable Diffusion 1.5',
      subtitle: 'Neural Engine, 512×512. Smallest on-device option.',
      hfRepo: 'apple/coreml-stable-diffusion-v1-5',
      treePrefix: 'split_einsum/compiled',
      pipeline: AppleMlPipelineKind.sd15,
      recommendedWidth: 512,
      recommendedHeight: 512,
      recommendedSteps: 20,
      recommendedCfg: 7.0,
      minIosMajor: 16,
      minIosMinor: 2,
      approxBytes: 2300000000,
    ),
    AppleMlCatalogModel(
      id: 'sdxl-ios',
      name: 'Stable Diffusion XL (iOS)',
      subtitle: 'Apple’s 768×768 iOS package. Needs iOS 17+ and more RAM.',
      hfRepo: 'apple/coreml-stable-diffusion-xl-base-ios',
      treePrefix: 'coreml-stable-diffusion-xl-base-ios_split_einsum_compiled',
      pipeline: AppleMlPipelineKind.sdxl,
      recommendedWidth: 768,
      recommendedHeight: 768,
      recommendedSteps: 30,
      recommendedCfg: 5.0,
      minIosMajor: 17,
      approxBytes: 3100000000,
    ),
  ];

  static AppleMlCatalogModel? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

class HfRemoteFile {
  final String path;
  final int size;

  const HfRemoteFile({required this.path, required this.size});
}

/// Skip SafetyChecker, the unsplit Unet (chunks are used instead), VAEEncoder
/// (txt2img only), zip bundles, and docs/images.
bool appleMlShouldSkipRemotePath(String path) {
  final lower = path.replaceAll('\\', '/').toLowerCase();
  if (lower.endsWith('.zip') ||
      lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.md') ||
      lower.endsWith('.gitattributes')) {
    return true;
  }
  if (lower.contains('safetychecker')) return true;
  if (lower.contains('vaeencoder')) return true;
  if (lower.contains('unetrefiner')) return true;
  if (lower.contains('/unet.mlmodelc') && !lower.contains('unetchunk')) {
    return true;
  }
  return false;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
