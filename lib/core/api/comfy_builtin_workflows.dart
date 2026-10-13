import '../models/generation_backend.dart';

/// Built-in CheckpointLoaderSimple graph (SD 1.5 / SDXL).
const kComfyBuiltinSdWorkflowPath = '__a1111mini_comfy_sd_checkpoint__';

/// Most recent `/history` graph from the connected ComfyUI server.
const kComfyLastRunWorkflowPath = '__a1111mini_comfy_last_run__';

bool isComfyBuiltinSdWorkflowPath(String? path) {
  final value = path?.trim() ?? '';
  return value.isEmpty ||
      value == kComfyBuiltinSdWorkflowPath ||
      value == '__lmmini_comfy_sd_checkpoint__' ||
      value == '__lmmini_default_comfyui_workflow__';
}

bool isComfyLastRunWorkflowPath(String? path) {
  final value = path?.trim() ?? '';
  return value == kComfyLastRunWorkflowPath ||
      value == '__lmmini_comfy_last_run__' ||
      value.startsWith('__lmmini_comfy_history__:') ||
      value.startsWith('__a1111mini_comfy_history__:');
}

bool isComfySyntheticWorkflowPath(String? path) {
  return isComfyBuiltinSdWorkflowPath(path) || isComfyLastRunWorkflowPath(path);
}

List<ComfyWorkflowInfo> builtinComfyWorkflows() => const [
      ComfyWorkflowInfo(
        path: kComfyBuiltinSdWorkflowPath,
        name: 'Built-in SD 1.5 / SDXL',
        builtin: true,
      ),
    ];

/// Fresh API-format graph so callers can mutate it without sharing state.
Map<String, dynamic> builtinSdCheckpointGraph() => {
      '4': {
        'class_type': 'CheckpointLoaderSimple',
        'inputs': {'ckpt_name': ''},
        '_meta': {'title': 'Load Checkpoint'},
      },
      '6': {
        'class_type': 'CLIPTextEncode',
        'inputs': {
          'text': '',
          'clip': ['4', 1],
        },
        '_meta': {'title': 'Positive Prompt'},
      },
      '7': {
        'class_type': 'CLIPTextEncode',
        'inputs': {
          'text': '',
          'clip': ['4', 1],
        },
        '_meta': {'title': 'Negative Prompt'},
      },
      '5': {
        'class_type': 'EmptyLatentImage',
        'inputs': {
          'width': 512,
          'height': 512,
          'batch_size': 1,
        },
      },
      '3': {
        'class_type': 'KSampler',
        'inputs': {
          'seed': 0,
          'steps': 20,
          'cfg': 7.0,
          'sampler_name': 'euler',
          'scheduler': 'normal',
          'denoise': 1.0,
          'model': ['4', 0],
          'positive': ['6', 0],
          'negative': ['7', 0],
          'latent_image': ['5', 0],
        },
      },
      '8': {
        'class_type': 'VAEDecode',
        'inputs': {
          'samples': ['3', 0],
          'vae': ['4', 2],
        },
      },
      '9': {
        'class_type': 'SaveImage',
        'inputs': {
          'filename_prefix': 'A1111Mini',
          'images': ['8', 0],
        },
      },
    };
