/// Converts a ComfyUI UI-format workflow into the `/prompt` API graph and
/// injects the same generation options the A1111 chat UI already exposes.
class ComfyWorkflowGraph {
  ComfyWorkflowGraph._(this.prompt);

  final Map<String, dynamic> prompt;

  static const _seedControls = {
    'fixed',
    'randomize',
    'increment',
    'decrement',
  };

  static const _widgetTypes = {
    'INT',
    'FLOAT',
    'STRING',
    'BOOLEAN',
    'COMBO',
  };

  static ComfyWorkflowGraph fromWorkflow(
    Map<String, dynamic> workflow, {
    Map<String, dynamic>? objectInfo,
  }) {
    if (_isApiFormat(workflow)) {
      return ComfyWorkflowGraph._(
        workflow.map((k, v) => MapEntry(k, v is Map ? Map<String, dynamic>.from(v) : v)),
      );
    }
    return ComfyWorkflowGraph._(_uiToApi(workflow, objectInfo ?? const {}));
  }

  static bool isApiFormat(Map<String, dynamic> workflow) =>
      _isApiFormat(workflow);

  static bool _isApiFormat(Map<String, dynamic> workflow) {
    if (workflow.containsKey('nodes') || workflow.containsKey('links')) {
      return false;
    }
    if (workflow.isEmpty) return false;
    for (final value in workflow.values) {
      if (value is Map && value['class_type'] != null) return true;
    }
    return false;
  }

  static Map<String, dynamic> _uiToApi(
    Map<String, dynamic> workflow,
    Map<String, dynamic> objectInfo,
  ) {
    final nodes = workflow['nodes'];
    final links = workflow['links'];
    if (nodes is! List) {
      throw Exception('Workflow has no nodes');
    }

    final linkById = <int, List<dynamic>>{};
    if (links is List) {
      for (final link in links) {
        if (link is List && link.isNotEmpty) {
          final id = _asInt(link[0]);
          if (id != null) linkById[id] = link;
        }
      }
    }

    final api = <String, dynamic>{};
    for (final raw in nodes) {
      if (raw is! Map) continue;
      final node = Map<String, dynamic>.from(raw);
      if (node['mode'] == 2 || node['mode'] == 4) continue; // muted / bypassed
      final id = node['id']?.toString();
      final type = node['type']?.toString();
      if (id == null || type == null || type == 'Note' || type == 'Reroute') {
        continue;
      }

      final inputs = <String, dynamic>{};
      final widgetValues = (node['widgets_values'] as List?) ?? const [];
      final widgetNames = _widgetInputNames(objectInfo[type]);
      _applyWidgetValues(inputs, widgetNames, widgetValues);

      final nodeInputs = node['inputs'];
      if (nodeInputs is List) {
        for (final input in nodeInputs) {
          if (input is! Map) continue;
          final name = input['name']?.toString();
          final linkId = _asInt(input['link']);
          if (name == null || linkId == null) continue;
          final link = linkById[linkId];
          if (link == null || link.length < 3) continue;
          inputs[name] = [link[1].toString(), link[2]];
        }
      }

      api[id] = {
        'class_type': type,
        'inputs': inputs,
        if (node['title'] != null) '_meta': {'title': node['title']},
      };
    }
    return api;
  }

  static List<String> _widgetInputNames(dynamic info) {
    if (info is! Map) return const [];
    final input = info['input'];
    if (input is! Map) return const [];
    final names = <String>[];
    for (final section in ['required', 'optional']) {
      final block = input[section];
      if (block is! Map) continue;
      for (final entry in block.entries) {
        if (_isWidgetSpec(entry.value)) {
          names.add(entry.key.toString());
        }
      }
    }
    return names;
  }

  static bool _isWidgetSpec(dynamic spec) {
    if (spec is! List || spec.isEmpty) return false;
    final type = spec.first;
    if (type is List) return true;
    if (type is String) return _widgetTypes.contains(type.toUpperCase());
    return false;
  }

  static void _applyWidgetValues(
    Map<String, dynamic> inputs,
    List<String> names,
    List<dynamic> values,
  ) {
    if (names.isEmpty) {
      return;
    }
    var vi = 0;
    for (final name in names) {
      if (vi >= values.length) break;
      var value = values[vi];
      if (_seedControls.contains(value.toString())) {
        vi++;
        if (vi >= values.length) break;
        value = values[vi];
      }
      inputs[name] = value;
      vi++;
    }
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void applyGenerationOptions({
    required String prompt,
    String negativePrompt = '',
    required int steps,
    required double cfgScale,
    required int width,
    required int height,
    required int seed,
    required int batchSize,
    required String samplerName,
    String? scheduler,
    String? checkpoint,
    String? vae,
    double? denoise,
    String? initImageName,
  }) {
    _setTextOnConditioning('positive', prompt);
    _setTextOnConditioning('negative', negativePrompt);
    _setOnTypes(const {
      'KSampler',
      'KSamplerAdvanced',
      'SamplerCustom',
      'SamplerCustomAdvanced',
    }, {
      'steps': steps,
      'cfg': cfgScale,
      if (seed >= 0) 'seed': seed,
      if (seed >= 0) 'noise_seed': seed,
      'sampler_name': _mapSampler(samplerName),
      if (scheduler != null && scheduler.isNotEmpty) 'scheduler': scheduler,
      if (denoise != null) 'denoise': denoise,
    });
    _setOnTypes(
      const {'KSamplerSelect'},
      {'sampler_name': _mapSampler(samplerName)},
      force: true,
    );
    _setOnTypes(const {
      'BasicScheduler',
      'SDTurboScheduler',
    }, {
      'steps': steps,
      if (scheduler != null && scheduler.isNotEmpty) 'scheduler': scheduler,
      if (denoise != null) 'denoise': denoise,
    });
    if (seed >= 0) {
      _setOnTypes(
        const {'RandomNoise'},
        {'noise_seed': seed},
        force: true,
      );
    }
    _setOnTypes(const {'CFGGuider', 'DualCFGGuider'}, {'cfg': cfgScale});
    _setOnTypes(
      const {'FluxGuidance'},
      {'guidance': cfgScale, 'cfg': cfgScale},
    );
    _setOnTypes(
      const {
        'EmptyLatentImage',
        'EmptySD3LatentImage',
        'EmptyHunyuanLatentVideo',
      },
      {
        'width': width,
        'height': height,
        'batch_size': batchSize,
      },
      force: true,
    );
    if (checkpoint != null && checkpoint.isNotEmpty) {
      final hasCkpt = _firstNode(const {
            'CheckpointLoaderSimple',
            'CheckpointLoader',
            'ImageOnlyCheckpointLoader',
          }) !=
          null;
      final hasUnet =
          _firstNode(const {'UNETLoader', 'UnetLoaderGGUF'}) != null;
      if (hasCkpt) {
        _setOnTypes(
          const {
            'CheckpointLoaderSimple',
            'CheckpointLoader',
            'ImageOnlyCheckpointLoader',
          },
          {'ckpt_name': checkpoint},
          force: true,
        );
      }
      // UNET graphs (Z-Image, Flux) keep their loader unless the caller
      // passes the same unet filename. Chat dropdown checkpoints must not
      // overwrite z_image_turbo with sd_xl_turbo.
      if (hasUnet && !hasCkpt) {
        final current = _firstScalarString(
          const {'UNETLoader', 'UnetLoaderGGUF'},
          const ['unet_name'],
        );
        if (current == null || current.isEmpty || current == checkpoint) {
          _setOnTypes(
            const {'UNETLoader', 'UnetLoaderGGUF'},
            {'unet_name': checkpoint},
            force: true,
          );
        }
      }
    }
    if (vae != null && vae.isNotEmpty && vae != 'Automatic' && vae != 'None') {
      applyVae(vae);
    }
    if (initImageName != null && initImageName.isNotEmpty) {
      _setOnTypes(const {'LoadImage'}, {'image': initImageName}, force: true);
    }
  }

  ComfyWorkflowDefaults readDefaults() {
    const samplerNodes = {
      'KSampler',
      'KSamplerAdvanced',
      'SamplerCustom',
      'SamplerCustomAdvanced',
      'KSamplerSelect',
    };
    const schedulerNodes = {
      'KSampler',
      'KSamplerAdvanced',
      'BasicScheduler',
      'SDTurboScheduler',
    };
    const seedNodes = {
      'KSampler',
      'KSamplerAdvanced',
      'SamplerCustom',
      'RandomNoise',
    };
    const cfgNodes = {
      'KSampler',
      'KSamplerAdvanced',
      'CFGGuider',
      'DualCFGGuider',
      'FluxGuidance',
    };
    const conditionNodes = {
      'KSampler',
      'KSamplerAdvanced',
      'SamplerCustom',
      'CFGGuider',
      'DualCFGGuider',
    };
    const latents = {
      'EmptyLatentImage',
      'EmptySD3LatentImage',
      'EmptyHunyuanLatentVideo',
    };
    final loras = <({String name, double weight})>[];
    for (final node in _nodesOfType(const {
      'LoraLoader',
      'LoraLoaderModelOnly',
    })) {
      final name = _scalarString(node.inputs['lora_name']);
      if (name == null || name.isEmpty) continue;
      final weight = _asDouble(node.inputs['strength_model']) ?? 1.0;
      loras.add((name: name, weight: weight));
    }

    String? textOn(String role) {
      for (final node in _nodesOfType(conditionNodes)) {
        final ref = node.inputs[role];
        if (ref is List && ref.isNotEmpty) {
          final text = _textFromNode(prompt[ref.first.toString()]);
          if (text != null) return text;
        }
      }
      return null;
    }

    return ComfyWorkflowDefaults(
      checkpoint: _firstScalarString(const {
        'CheckpointLoaderSimple',
        'CheckpointLoader',
        'ImageOnlyCheckpointLoader',
      }, const [
        'ckpt_name',
      ]),
      unet: _firstScalarString(const {
        'UNETLoader',
        'UnetLoaderGGUF',
      }, const [
        'unet_name',
      ]),
      vae: _firstScalarString(const {'VAELoader'}, const ['vae_name']),
      sampler: _firstScalarString(samplerNodes, const ['sampler_name']),
      scheduler: _firstScalarString(schedulerNodes, const ['scheduler']),
      seed: _asInt(_firstScalar(seedNodes, const ['noise_seed', 'seed'])),
      steps: _asInt(_firstScalar(schedulerNodes, const ['steps'])),
      cfg: _asDouble(_firstScalar(cfgNodes, const ['cfg', 'guidance'])),
      denoise: _asDouble(_firstScalar(const {
        'KSampler',
        'KSamplerAdvanced',
        'SamplerCustom',
      }, const [
        'denoise',
      ])),
      width: _asInt(_firstScalar(latents, const ['width'])),
      height: _asInt(_firstScalar(latents, const ['height'])),
      batchSize: _asInt(_firstScalar(latents, const ['batch_size'])),
      positivePrompt: textOn('positive'),
      negativePrompt: textOn('negative'),
      loras: loras,
      fields: _readExtraFields(),
    );
  }

  /// Scalar widgets that already have their own filter controls.
  static const _dedicatedInputs = {
    'text',
    'text_g',
    'text_l',
    'prompt',
    'positive_prompt',
    'negative_prompt',
    'filename_prefix',
    'control_after_generate',
    'steps',
    'cfg',
    'guidance',
    'sampler_name',
    'sampler',
    'scheduler',
    'seed',
    'noise_seed',
    'width',
    'height',
    'batch_size',
    'ckpt_name',
    'unet_name',
    'vae_name',
    'lora_name',
    'strength_model',
    'strength_clip',
    'image',
  };

  List<ComfyWorkflowField> _readExtraFields() {
    final fields = <ComfyWorkflowField>[];
    for (final entry in prompt.entries) {
      final node = entry.value;
      if (node is! Map) continue;
      final inputs = node['inputs'];
      if (inputs is! Map) continue;
      final classType = node['class_type']?.toString() ?? '';
      if (classType.isEmpty) continue;
      for (final input in inputs.entries) {
        final name = input.key.toString();
        if (_dedicatedInputs.contains(name)) continue;
        final value = input.value;
        if (value is List || value is Map) continue;
        if (value is! num && value is! String && value is! bool) continue;
        if (value is String && value.length > 180) continue;
        fields.add(
          ComfyWorkflowField(
            nodeId: entry.key.toString(),
            classType: classType,
            name: name,
            value: value,
          ),
        );
      }
    }
    return fields;
  }

  /// Writes edited extra widgets back onto the nodes they came from.
  /// Wires are left alone.
  void applyFields(List<ComfyWorkflowField> fields) {
    for (final field in fields) {
      final node = prompt[field.nodeId];
      if (node is! Map) continue;
      final inputs = node['inputs'];
      if (inputs is! Map || !inputs.containsKey(field.name)) continue;
      final current = inputs[field.name];
      if (current is List || current is Map) continue;
      inputs[field.name] = field.value;
    }
  }

  /// Overwrites existing LoraLoader nodes, or inserts a chain after the
  /// checkpoint / UNET loader when the graph has none.
  void applyLoras(List<({String name, double weight})> loras) {
    final selected = loras.where((l) => l.name.trim().isNotEmpty).toList();
    if (selected.isEmpty) return;

    final existing = _nodesOfType(const {'LoraLoader', 'LoraLoaderModelOnly'});
    if (existing.isNotEmpty) {
      for (var i = 0; i < existing.length && i < selected.length; i++) {
        existing[i].inputs['lora_name'] = selected[i].name;
        existing[i].inputs['strength_model'] = selected[i].weight;
        if (existing[i].node['class_type'] != 'LoraLoaderModelOnly') {
          existing[i].inputs['strength_clip'] = selected[i].weight;
        }
      }
      return;
    }

    final ckpt = _firstNode(const {
      'CheckpointLoaderSimple',
      'CheckpointLoader',
    });
    if (ckpt != null) {
      _insertLoraChain(ckpt.id, selected, includeClip: true);
      return;
    }
    final unet = _firstNode(const {'UNETLoader'});
    if (unet != null) {
      _insertLoraChain(unet.id, selected, includeClip: false);
    }
  }

  void applyVae(String vaeName) {
    final existing = _nodesOfType(const {'VAELoader'});
    if (existing.isNotEmpty) {
      for (final node in existing) {
        node.inputs['vae_name'] = vaeName;
      }
      return;
    }
    final decodeNodes = _nodesOfType(const {'VAEDecode', 'VAEDecodeTiled'});
    if (decodeNodes.isEmpty) return;
    final id = _nextNodeId().toString();
    prompt[id] = {
      'class_type': 'VAELoader',
      'inputs': {'vae_name': vaeName},
    };
    for (final decode in decodeNodes) {
      decode.inputs['vae'] = [id, 0];
    }
  }

  void _insertLoraChain(
    String sourceId,
    List<({String name, double weight})> loras, {
    required bool includeClip,
  }) {
    var modelRef = <dynamic>[sourceId, 0];
    var clipRef = <dynamic>[sourceId, 1];
    final created = <String>{};
    var nextId = _nextNodeId();
    for (final lora in loras) {
      final id = nextId.toString();
      nextId++;
      created.add(id);
      if (includeClip) {
        prompt[id] = {
          'class_type': 'LoraLoader',
          'inputs': {
            'model': modelRef,
            'clip': clipRef,
            'lora_name': lora.name,
            'strength_model': lora.weight,
            'strength_clip': lora.weight,
          },
        };
        modelRef = [id, 0];
        clipRef = [id, 1];
      } else {
        prompt[id] = {
          'class_type': 'LoraLoaderModelOnly',
          'inputs': {
            'model': modelRef,
            'lora_name': lora.name,
            'strength_model': lora.weight,
          },
        };
        modelRef = [id, 0];
      }
    }

    prompt.forEach((id, raw) {
      if (created.contains(id) || id == sourceId || raw is! Map) return;
      final inputs = raw['inputs'];
      if (inputs is! Map) return;
      _replaceLink(inputs, sourceId, 0, modelRef);
      if (includeClip) {
        _replaceLink(inputs, sourceId, 1, clipRef);
      }
    });
  }

  void _replaceLink(
    Map inputs,
    String fromId,
    int fromSlot,
    List target,
  ) {
    for (final key in inputs.keys.toList()) {
      final value = inputs[key];
      if (value is List &&
          value.length >= 2 &&
          value[0].toString() == fromId &&
          value[1] == fromSlot) {
        inputs[key] = [target[0], target[1]];
      }
    }
  }

  int _nextNodeId() {
    var max = 0;
    for (final key in prompt.keys) {
      final parsed = int.tryParse(key.toString());
      if (parsed != null && parsed > max) max = parsed;
    }
    return max + 1;
  }

  void _setTextOnConditioning(String role, String text) {
    final sampler = _firstNode(const {
      'KSampler',
      'KSamplerAdvanced',
      'SamplerCustom',
      'SamplerCustomAdvanced',
    });
    if (sampler != null) {
      final ref = sampler.inputs[role];
      if (ref is List && ref.isNotEmpty) {
        final node = prompt[ref.first.toString()];
        if (node is Map && node['inputs'] is Map) {
          _applyText(node['inputs'] as Map, text);
          return;
        }
      }
    }

    final encodes = _nodesOfType(const {'CLIPTextEncode', 'CLIPTextEncodeSDXL'});
    if (encodes.isEmpty) return;
    if (role == 'negative') {
      final titled = encodes.where((n) {
        final title = (n.node['_meta'] is Map)
            ? n.node['_meta']['title']?.toString().toLowerCase() ?? ''
            : '';
        return title.contains('neg');
      });
      final target = titled.isNotEmpty ? titled.first : encodes.last;
      _applyText(target.inputs, text);
    } else {
      _applyText(encodes.first.inputs, text);
    }
  }

  void _applyText(Map inputs, String text) {
    if (inputs.containsKey('text')) inputs['text'] = text;
    if (inputs.containsKey('text_g')) inputs['text_g'] = text;
    if (inputs.containsKey('text_l')) inputs['text_l'] = text;
    if (inputs.containsKey('clip_l')) inputs['clip_l'] = text;
    if (inputs.containsKey('t5xxl')) inputs['t5xxl'] = text;
    if (!inputs.containsKey('text') &&
        !inputs.containsKey('text_g') &&
        !inputs.containsKey('clip_l') &&
        !inputs.containsKey('t5xxl')) {
      inputs['text'] = text;
    }
  }

  void _setOnTypes(
    Set<String> types,
    Map<String, dynamic> values, {
    bool force = false,
  }) {
    for (final node in _nodesOfType(types)) {
      for (final entry in values.entries) {
        if (force || node.inputs.containsKey(entry.key)) {
          _writeInput(node.inputs, entry.key, entry.value, force: force);
        }
      }
    }
  }

  void _writeInput(
    Map<String, dynamic> inputs,
    String key,
    dynamic value, {
    bool force = false,
  }) {
    if (!force && !inputs.containsKey(key)) return;
    final current = inputs[key];
    if (current is List && current.isNotEmpty) {
      if (_writePrimitive(current.first.toString(), value)) return;
    }
    inputs[key] = value;
  }

  bool _writePrimitive(String id, dynamic value) {
    final node = prompt[id];
    if (node is! Map || node['inputs'] is! Map) return false;
    final inputs = node['inputs'] as Map;
    const keys = ['value', 'int', 'float', 'number', 'string'];
    for (final key in keys) {
      if (inputs.containsKey(key)) {
        inputs[key] = value;
        return true;
      }
    }
    inputs['value'] = value;
    return true;
  }

  static String mapSampler(String name) => _mapSampler(name);

  dynamic _resolvedScalar(dynamic value, [int depth = 0]) {
    if (value == null || depth > 8) return null;
    if (value is List && value.isNotEmpty) {
      final node = prompt[value.first.toString()];
      if (node is Map && node['inputs'] is Map) {
        final inputs = node['inputs'] as Map;
        return _resolvedScalar(
          inputs['value'] ??
              inputs['int'] ??
              inputs['float'] ??
              inputs['number'] ??
              inputs['string'],
          depth + 1,
        );
      }
      return null;
    }
    return value;
  }

  dynamic _firstScalar(Set<String> types, List<String> keys) {
    for (final node in _nodesOfType(types)) {
      for (final key in keys) {
        final value = _resolvedScalar(node.inputs[key]);
        if (value == null || value is List) continue;
        return value;
      }
    }
    return null;
  }

  String? _firstScalarString(Set<String> types, List<String> keys) {
    return _scalarString(_firstScalar(types, keys));
  }

  static String? _scalarString(dynamic value) {
    if (value == null || value is List) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String? _textFromNode(dynamic raw) {
    if (raw is! Map || raw['inputs'] is! Map) return null;
    final inputs = raw['inputs'] as Map;
    final text = inputs['text'] ??
        inputs['text_g'] ??
        inputs['text_l'] ??
        inputs['clip_l'] ??
        inputs['t5xxl'];
    return text is String ? text : null;
  }

  _ApiNode? _firstNode(Set<String> types) {
    final nodes = _nodesOfType(types);
    return nodes.isEmpty ? null : nodes.first;
  }

  List<_ApiNode> _nodesOfType(Set<String> types) {
    final result = <_ApiNode>[];
    prompt.forEach((id, raw) {
      if (raw is! Map) return;
      final type = raw['class_type']?.toString();
      if (type == null || !types.contains(type)) return;
      final inputs = raw['inputs'];
      if (inputs is! Map) return;
      result.add(_ApiNode(id, raw, Map<String, dynamic>.from(inputs)));
      raw['inputs'] = result.last.inputs;
    });
    return result;
  }

  static String _mapSampler(String name) {
    const map = {
      'Euler a': 'euler_ancestral',
      'Euler': 'euler',
      'LMS': 'lms',
      'Heun': 'heun',
      'DPM2': 'dpm_2',
      'DPM2 a': 'dpm_2_ancestral',
      'DPM++ 2S a': 'dpmpp_2s_ancestral',
      'DPM++ 2M': 'dpmpp_2m',
      'DPM++ SDE': 'dpmpp_sde',
      'DPM++ 2M SDE': 'dpmpp_2m_sde',
      'DPM++ 3M SDE': 'dpmpp_3m_sde',
      'DPM fast': 'dpm_fast',
      'DPM adaptive': 'dpm_adaptive',
      'DDIM': 'ddim',
      'UniPC': 'uni_pc',
      'LCM': 'lcm',
    };
    return map[name] ?? name;
  }
}

class _ApiNode {
  final String id;
  final Map node;
  final Map<String, dynamic> inputs;

  _ApiNode(this.id, this.node, this.inputs);
}

/// One editable widget value taken from a Comfy graph.
class ComfyWorkflowField {
  final String nodeId;
  final String classType;
  final String name;
  final Object value;

  const ComfyWorkflowField({
    required this.nodeId,
    required this.classType,
    required this.name,
    required this.value,
  });

  String get label => name.replaceAll('_', ' ');

  ComfyWorkflowField copyWith({Object? value}) {
    return ComfyWorkflowField(
      nodeId: nodeId,
      classType: classType,
      name: name,
      value: value ?? this.value,
    );
  }
}

class ComfyWorkflowDefaults {
  final String? checkpoint;
  final String? unet;
  final String? vae;
  final String? sampler;
  final String? scheduler;
  final int? seed;
  final int? steps;
  final double? cfg;
  final double? denoise;
  final int? width;
  final int? height;
  final int? batchSize;
  final String? positivePrompt;
  final String? negativePrompt;
  final List<({String name, double weight})> loras;
  final List<ComfyWorkflowField> fields;

  const ComfyWorkflowDefaults({
    this.checkpoint,
    this.unet,
    this.vae,
    this.sampler,
    this.scheduler,
    this.seed,
    this.steps,
    this.cfg,
    this.denoise,
    this.width,
    this.height,
    this.batchSize,
    this.positivePrompt,
    this.negativePrompt,
    this.loras = const [],
    this.fields = const [],
  });

  String? get model {
    final u = unet?.trim();
    if (u != null && u.isNotEmpty) return u;
    final c = checkpoint?.trim();
    if (c != null && c.isNotEmpty) return c;
    return null;
  }

  bool get usesUnet {
    final u = unet?.trim();
    return u != null && u.isNotEmpty;
  }
}

/// When the chat UI still shows A1111 global defaults (512, CFG 7, Euler a)
/// keep the Comfy graph's own sampler / size / CFG instead of smashing a
/// last-run Z-Image (1024, CFG 1, res_multistep) into a 512 blur.
class ComfyUiGraphMerge {
  static const genericSamplers = {
    'euler',
    'euler_ancestral',
  };

  static int pickInt(int ui, int? graph, int globalDefault) {
    if (graph != null && ui == globalDefault && graph != ui) return graph;
    return ui;
  }

  static double pickDouble(
    double ui,
    double? graph,
    double globalDefault, {
    double epsilon = 0.051,
  }) {
    if (graph == null) return ui;
    if ((ui - globalDefault).abs() < epsilon && (graph - ui).abs() > epsilon) {
      return graph;
    }
    return ui;
  }

  static String pickSampler(String ui, String? graph, String globalDefault) {
    if (graph == null || graph.isEmpty) return ui;
    final mappedUi = ComfyWorkflowGraph.mapSampler(ui);
    final mappedGlobal = ComfyWorkflowGraph.mapSampler(globalDefault);
    final mappedGraph = ComfyWorkflowGraph.mapSampler(graph);
    if (mappedUi == mappedGraph) return ui;
    final uiLooksGlobal = mappedUi == mappedGlobal ||
        (genericSamplers.contains(mappedUi) &&
            genericSamplers.contains(mappedGlobal));
    if (uiLooksGlobal) return graph;
    return ui;
  }

  static String? pickScheduler(String? ui, String? graph, String? globalDefault) {
    if (graph == null || graph.isEmpty) return ui;
    if (ui == graph) return ui;
    if (ui == null ||
        ui.isEmpty ||
        ui == 'normal' ||
        (globalDefault != null && ui == globalDefault)) {
      return graph;
    }
    return ui;
  }

  static String? pickModel({
    required ComfyWorkflowDefaults graph,
    String? uiCheckpoint,
  }) {
    if (graph.usesUnet) return graph.unet;
    return uiCheckpoint ?? graph.checkpoint;
  }
}
