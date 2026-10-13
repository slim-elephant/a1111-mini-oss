/// Built-in looks for on-device SDXL. These chips are always on the generation
/// screen, even before the local database has finished seeding personas.
class OnDeviceLook {
  final String personaId;
  final String profileId;
  final String label;
  final int steps;
  final double cfg;
  final int width;
  final int height;
  final String sampler;
  final String positivePrompt;
  final String negativePrompt;

  const OnDeviceLook({
    required this.personaId,
    required this.profileId,
    required this.label,
    required this.steps,
    required this.cfg,
    required this.width,
    required this.height,
    required this.sampler,
    required this.positivePrompt,
    required this.negativePrompt,
  });
}

const onDeviceLooks = <OnDeviceLook>[
  OnDeviceLook(
    personaId: 'preset_on_device_photo',
    profileId: 'preset_photorealistic',
    label: 'Photo',
    steps: 30,
    cfg: 5,
    width: 768,
    height: 768,
    sampler: 'DPM-Solver++',
    positivePrompt:
        'photorealistic, hyperdetailed, 8k uhd, dslr, high quality, film grain',
    negativePrompt:
        'cartoon, anime, drawing, painting, sketch, illustration, low quality, blurry, deformed',
  ),
  OnDeviceLook(
    personaId: 'preset_on_device_cinema',
    profileId: 'preset_cinematic',
    label: 'Cinema',
    steps: 30,
    cfg: 5,
    width: 768,
    height: 768,
    sampler: 'DPM-Solver++',
    positivePrompt:
        'cinematic still, dramatic lighting, shallow depth of field, film grain, detailed, 35mm',
    negativePrompt:
        'cartoon, anime, low quality, blurry, deformed, watermark, text',
  ),
  OnDeviceLook(
    personaId: 'preset_on_device_anime',
    profileId: 'preset_anime',
    label: 'Anime',
    steps: 28,
    cfg: 6,
    width: 768,
    height: 768,
    sampler: 'DPM-Solver++',
    positivePrompt:
        'masterpiece, best quality, anime style, detailed, vibrant colors',
    negativePrompt:
        'photorealistic, 3d render, low quality, worst quality, blurry, watermark',
  ),
];

OnDeviceLook? onDeviceLookById(String? personaId) {
  if (personaId == null) return null;
  for (final look in onDeviceLooks) {
    if (look.personaId == personaId) return look;
  }
  return null;
}
