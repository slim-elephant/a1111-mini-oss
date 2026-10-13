import 'package:flutter_test/flutter_test.dart';
import 'package:a1111_mini/core/api/comfy_builtin_workflows.dart';
import 'package:a1111_mini/core/api/comfy_catalog.dart';
import 'package:a1111_mini/core/api/comfyui_workflow.dart';

void main() {
  test('built-in graph accepts prompt, negative, size, checkpoint, vae, lora', () {
    final graph = ComfyWorkflowGraph.fromWorkflow(builtinSdCheckpointGraph());
    graph.applyGenerationOptions(
      prompt: 'a cat',
      negativePrompt: 'blurry',
      steps: 28,
      cfgScale: 5.5,
      width: 1024,
      height: 768,
      seed: 42,
      batchSize: 2,
      samplerName: 'Euler a',
      scheduler: 'karras',
      checkpoint: 'sdxl.safetensors',
      vae: 'vae.safetensors',
    );
    graph.applyLoras([(name: 'detail.safetensors', weight: 0.8)]);

    final prompt = graph.prompt;
    expect(prompt['6']['inputs']['text'], 'a cat');
    expect(prompt['7']['inputs']['text'], 'blurry');
    expect(prompt['5']['inputs']['width'], 1024);
    expect(prompt['5']['inputs']['height'], 768);
    expect(prompt['5']['inputs']['batch_size'], 2);
    expect(prompt['4']['inputs']['ckpt_name'], 'sdxl.safetensors');
    expect(prompt['3']['inputs']['sampler_name'], 'euler_ancestral');
    expect(prompt['3']['inputs']['scheduler'], 'karras');
    expect(prompt['3']['inputs']['seed'], 42);

    final lora = prompt.values.cast<Map>().firstWhere(
          (node) => node['class_type'] == 'LoraLoader',
        );
    expect(lora['inputs']['lora_name'], 'detail.safetensors');
    expect(lora['inputs']['strength_model'], 0.8);
    expect(prompt['3']['inputs']['model'][0], isNot('4'));
    expect(prompt['6']['inputs']['clip'][0], isNot('4'));
    expect(prompt['8']['inputs']['vae'][0], isNot('4'));

    final vae = prompt.values.cast<Map>().firstWhere(
          (node) => node['class_type'] == 'VAELoader',
        );
    expect(vae['inputs']['vae_name'], 'vae.safetensors');
    expect(prompt['8']['inputs']['vae'][0], isNot('4'));
  });

  test('synthetic workflow path helpers', () {
    expect(isComfyBuiltinSdWorkflowPath(null), isTrue);
    expect(isComfyBuiltinSdWorkflowPath(''), isTrue);
    expect(isComfyBuiltinSdWorkflowPath(kComfyBuiltinSdWorkflowPath), isTrue);
    expect(isComfyLastRunWorkflowPath(kComfyLastRunWorkflowPath), isTrue);
    expect(isComfyLastRunWorkflowPath(kComfyBuiltinSdWorkflowPath), isFalse);
  });

  test('parseComfyHistory prefers newest prompt graph', () {
    final graphs = parseComfyHistory({
      'old': {
        'prompt': [
          1,
          'old',
          {
            '1': {
              'class_type': 'CheckpointLoaderSimple',
              'inputs': {'ckpt_name': 'old.safetensors'},
            },
          },
        ],
      },
      'new': {
        'prompt': [
          9,
          'new',
          {
            '1': {
              'class_type': 'CheckpointLoaderSimple',
              'inputs': {'ckpt_name': 'new.safetensors'},
            },
          },
        ],
      },
    });
    expect(graphs, hasLength(2));
    expect(graphs.first.promptId, 'new');
    expect(graphs.first.loaderLabel, 'new.safetensors');
  });

  test('weight filename filter skips yaml configs', () {
    expect(isComfyWeightFilename('model.safetensors'), isTrue);
    expect(isComfyWeightFilename('v1-inference.yaml'), isFalse);
  });

  test('readDefaults pulls unet sampler seed steps cfg vae size and prompts', () {
    final graph = ComfyWorkflowGraph.fromWorkflow({
      '1': {
        'class_type': 'UNETLoader',
        'inputs': {'unet_name': 'z_image_turbo_bf16.safetensors'},
      },
      '2': {
        'class_type': 'VAELoader',
        'inputs': {'vae_name': 'ae.safetensors'},
      },
      '3': {
        'class_type': 'EmptySD3LatentImage',
        'inputs': {'width': 1024, 'height': 768, 'batch_size': 1},
      },
      '4': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': 'a cat in sunlight', 'clip': ['1', 0]},
      },
      '5': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': 'blurry, lowres', 'clip': ['1', 0]},
      },
      '6': {
        'class_type': 'LoraLoaderModelOnly',
        'inputs': {
          'model': ['1', 0],
          'lora_name': 'detail.safetensors',
          'strength_model': 0.7,
        },
      },
      '7': {
        'class_type': 'KSampler',
        'inputs': {
          'seed': 12345,
          'steps': 8,
          'cfg': 1.0,
          'sampler_name': 'euler',
          'scheduler': 'simple',
          'denoise': 1.0,
          'model': ['6', 0],
          'positive': ['4', 0],
          'negative': ['5', 0],
          'latent_image': ['3', 0],
        },
      },
    });

    final defaults = graph.readDefaults();
    expect(defaults.model, 'z_image_turbo_bf16.safetensors');
    expect(defaults.usesUnet, isTrue);
    expect(defaults.vae, 'ae.safetensors');
    expect(defaults.sampler, 'euler');
    expect(defaults.scheduler, 'simple');
    expect(defaults.seed, 12345);
    expect(defaults.steps, 8);
    expect(defaults.cfg, 1.0);
    expect(defaults.width, 1024);
    expect(defaults.height, 768);
    expect(defaults.positivePrompt, 'a cat in sunlight');
    expect(defaults.negativePrompt, 'blurry, lowres');
    expect(defaults.loras, hasLength(1));
    expect(defaults.loras.first.name, 'detail.safetensors');
    expect(defaults.loras.first.weight, 0.7);
    expect(
      defaults.fields.map((field) => field.name),
      contains('denoise'),
    );

    graph.applyGenerationOptions(
      prompt: 'new prompt',
      negativePrompt: 'new neg',
      steps: 9,
      cfgScale: 1.2,
      width: 1280,
      height: 720,
      seed: 99,
      batchSize: 1,
      samplerName: 'euler',
      scheduler: 'simple',
      checkpoint: 'z_image_turbo_bf16.safetensors',
    );
    expect(graph.prompt['1']['inputs']['unet_name'], 'z_image_turbo_bf16.safetensors');
    expect(graph.prompt['7']['inputs']['steps'], 9);
    graph.applyFields([
      defaults.fields.firstWhere((field) => field.name == 'denoise').copyWith(
            value: 0.45,
          ),
    ]);
    expect(graph.prompt['7']['inputs']['denoise'], 0.45);
  });

  test('readDefaults follows SamplerCustomAdvanced helper nodes', () {
    final graph = ComfyWorkflowGraph.fromWorkflow({
      '1': {
        'class_type': 'UNETLoader',
        'inputs': {'unet_name': 'flux1.safetensors'},
      },
      '2': {
        'class_type': 'RandomNoise',
        'inputs': {'noise_seed': 42},
      },
      '3': {
        'class_type': 'KSamplerSelect',
        'inputs': {'sampler_name': 'euler'},
      },
      '4': {
        'class_type': 'BasicScheduler',
        'inputs': {'scheduler': 'simple', 'steps': 4, 'denoise': 1.0},
      },
      '5': {
        'class_type': 'CFGGuider',
        'inputs': {
          'cfg': 3.5,
          'positive': ['8', 0],
          'negative': ['9', 0],
        },
      },
      '8': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': 'pos'},
      },
      '9': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': 'neg'},
      },
    });
    final defaults = graph.readDefaults();
    expect(defaults.unet, 'flux1.safetensors');
    expect(defaults.sampler, 'euler');
    expect(defaults.scheduler, 'simple');
    expect(defaults.steps, 4);
    expect(defaults.cfg, 3.5);
    expect(defaults.seed, 42);
    expect(defaults.positivePrompt, 'pos');
    expect(defaults.negativePrompt, 'neg');
  });

  test('readDefaults follows PrimitiveInt links for size', () {
    final graph = ComfyWorkflowGraph.fromWorkflow({
      'w': {
        'class_type': 'PrimitiveInt',
        'inputs': {'value': 1024},
      },
      '4': {
        'class_type': 'EmptySD3LatentImage',
        'inputs': {
          'width': ['w', 0],
          'height': 1024,
          'batch_size': 1,
        },
      },
    });
    expect(graph.readDefaults().width, 1024);
    expect(graph.readDefaults().height, 1024);
  });

  test('overlay keeps last-run Z-Image 1024 CFG 1 res_multistep over A1111 UI', () {
    final graph = ComfyWorkflowGraph.fromWorkflow(_zImageLastRun());
    final defaults = graph.readDefaults();
    expect(defaults.unet, 'z_image_turbo_bf16.safetensors');
    expect(defaults.width, 1024);
    expect(defaults.cfg, 1.0);
    expect(defaults.sampler, 'res_multistep');
    expect(defaults.scheduler, 'simple');
    expect(defaults.steps, 8);

    final steps = ComfyUiGraphMerge.pickInt(20, defaults.steps, 20);
    final cfg = ComfyUiGraphMerge.pickDouble(7.0, defaults.cfg, 7.0);
    final width = ComfyUiGraphMerge.pickInt(512, defaults.width, 512);
    final height = ComfyUiGraphMerge.pickInt(512, defaults.height, 512);
    final sampler = ComfyUiGraphMerge.pickSampler(
      'Euler a',
      defaults.sampler,
      'Euler a',
    );
    final scheduler = ComfyUiGraphMerge.pickScheduler(
      'normal',
      defaults.scheduler,
      null,
    );
    final model = ComfyUiGraphMerge.pickModel(
      graph: defaults,
      uiCheckpoint: 'sd_xl_turbo_1.0_fp16.safetensors',
    );

    graph.applyGenerationOptions(
      prompt: 'beautiful cat',
      steps: steps,
      cfgScale: cfg,
      width: width,
      height: height,
      seed: 42,
      batchSize: 1,
      samplerName: sampler,
      scheduler: scheduler,
      checkpoint: model,
    );

    expect(graph.prompt['1']['inputs']['unet_name'], 'z_image_turbo_bf16.safetensors');
    expect(graph.prompt['3']['inputs']['type'], 'lumina2');
    expect(graph.prompt['3']['inputs']['clip_name'], 'qwen_3_4b.safetensors');
    expect(graph.prompt['7']['inputs']['shift'], 3);
    expect(graph.prompt['4']['inputs']['width'], 1024);
    expect(graph.prompt['4']['inputs']['height'], 1024);
    expect(graph.prompt['8']['inputs']['cfg'], 1.0);
    expect(graph.prompt['8']['inputs']['steps'], 8);
    expect(graph.prompt['8']['inputs']['sampler_name'], 'res_multistep');
    expect(graph.prompt['8']['inputs']['scheduler'], 'simple');
    expect(graph.prompt['5']['inputs']['text'], 'beautiful cat');
  });

  test('does not write a checkpoint filename onto a UNET-only graph', () {
    final graph = ComfyWorkflowGraph.fromWorkflow(_zImageLastRun());
    graph.applyGenerationOptions(
      prompt: 'x',
      steps: 8,
      cfgScale: 1,
      width: 1024,
      height: 1024,
      seed: 1,
      batchSize: 1,
      samplerName: 'res_multistep',
      checkpoint: 'sd_xl_turbo_1.0_fp16.safetensors',
    );
    expect(graph.prompt['1']['inputs']['unet_name'], 'z_image_turbo_bf16.safetensors');
  });

  test('pickLastRunGraph skips phone client_id and 512/CFG7 overlay', () {
    final graphs = parseComfyHistory({
      'desktop': {
        'prompt': [
          1,
          'desktop',
          _zImageLastRun(),
          {'client_id': 'comfy-desktop'},
        ],
      },
      'phone': {
        'prompt': [
          9,
          'phone',
          _zImageLastRun(
            width: 512,
            height: 512,
            cfg: 7.0,
            sampler: 'euler_ancestral',
            scheduler: 'normal',
          ),
          {'client_id': kA1111MiniComfyClientId},
        ],
      },
    });
    final last = pickLastRunGraph(graphs);
    expect(last, isNotNull);
    expect(last!.promptId, 'desktop');
    expect(last.loaderLabel, 'z_image_turbo_bf16.safetensors');
    expect(firstComfyNumeric(last.graph, 'width'), 1024);
  });
}

Map<String, dynamic> _zImageLastRun({
  int width = 1024,
  int height = 1024,
  double cfg = 1.0,
  int steps = 8,
  String sampler = 'res_multistep',
  String scheduler = 'simple',
}) {
  return {
    '1': {
      'class_type': 'UNETLoader',
      'inputs': {'unet_name': 'z_image_turbo_bf16.safetensors'},
    },
    '2': {
      'class_type': 'VAELoader',
      'inputs': {'vae_name': 'ae.safetensors'},
    },
    '3': {
      'class_type': 'CLIPLoader',
      'inputs': {'clip_name': 'qwen_3_4b.safetensors', 'type': 'lumina2'},
    },
    '4': {
      'class_type': 'EmptySD3LatentImage',
      'inputs': {'width': width, 'height': height, 'batch_size': 1},
    },
    '5': {
      'class_type': 'CLIPTextEncode',
      'inputs': {
        'text': 'beautiful cat',
        'clip': ['3', 0],
      },
    },
    '6': {
      'class_type': 'CLIPTextEncode',
      'inputs': {
        'text': '',
        'clip': ['3', 0],
      },
    },
    '7': {
      'class_type': 'ModelSamplingAuraFlow',
      'inputs': {
        'shift': 3,
        'model': ['1', 0],
      },
    },
    '8': {
      'class_type': 'KSampler',
      'inputs': {
        'seed': 1,
        'steps': steps,
        'cfg': cfg,
        'sampler_name': sampler,
        'scheduler': scheduler,
        'denoise': 1.0,
        'model': ['7', 0],
        'positive': ['5', 0],
        'negative': ['6', 0],
        'latent_image': ['4', 0],
      },
    },
    '9': {
      'class_type': 'VAEDecode',
      'inputs': {
        'samples': ['8', 0],
        'vae': ['2', 0],
      },
    },
    '10': {
      'class_type': 'SaveImage',
      'inputs': {
        'images': ['9', 0],
        'filename_prefix': 'ComfyUI',
      },
    },
  };
}
