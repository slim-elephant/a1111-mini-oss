import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/generation_backend.dart';
import 'api_models.dart';
import 'comfy_builtin_workflows.dart';
import 'comfy_catalog.dart';
import 'connection_retry.dart';

class ComfyPromptResult {
  final String promptId;
  final int number;

  const ComfyPromptResult({required this.promptId, required this.number});
}

class ComfyQueueStatus {
  final bool running;
  final int pending;

  const ComfyQueueStatus({required this.running, required this.pending});
}

/// HTTP client for a ComfyUI server (default port 8188).
class ComfyUiClient {
  final Dio _dio;
  final String _baseUrl;
  final String clientId = kA1111MiniComfyClientId;

  String get baseUrl => _baseUrl;

  ComfyUiClient({
    required String host,
    required int port,
    String? authToken,
    String? backendHeader,
    Duration receiveTimeout = const Duration(minutes: 15),
  })  : _baseUrl = _buildUrl(host, port),
        _dio = Dio(BaseOptions(
          baseUrl: _buildUrl(host, port),
          connectTimeout: Duration(
            seconds: (authToken != null && authToken.isNotEmpty) ? 25 : 10,
          ),
          receiveTimeout: receiveTimeout,
          sendTimeout: const Duration(minutes: 5),
          headers: _clientHeaders(authToken, backendHeader ?? 'comfyui'),
        ));

  static Map<String, String> _clientHeaders(String? authToken, String backend) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = authToken?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['X-LM-Mini-Token'] = token;
      headers['X-LM-Mini-Backend'] = backend;
    }
    return headers;
  }

  static String _buildUrl(String host, int port) {
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    }
    return 'http://$host:$port';
  }

  Future<ConnectionStatus> testConnection() {
    return withConnectionRetries(_testConnectionOnce);
  }

  Future<ConnectionStatus> _testConnectionOnce() async {
    try {
      final response = await _dio.get('/system_stats', options: probeOptions());
      if (response.data is! Map) {
        return ConnectionStatus(
          connected: false,
          error: unexpectedResponseMessage('ComfyUI'),
        );
      }
      // /system_stats only names the GPU; the checkpoint comes from the
      // workflow, so currentModel stays null here.
      return ConnectionStatus(
        connected: true,
        warning: noModelsWarning([
          await _probeModelCount('checkpoints'),
          await _probeModelCount('unet', missingIsEmpty: true),
          await _probeModelCount('diffusion_models', missingIsEmpty: true),
        ]),
      );
    } on DioException catch (e) {
      if (isNotFound(e) && await _looksLikeA1111()) {
        return ConnectionStatus(
          connected: false,
          error: wrongBackendMessage(found: 'A1111', expected: 'ComfyUI'),
        );
      }
      return ConnectionStatus(connected: false, error: _humanizeError(e));
    } catch (e) {
      return ConnectionStatus(connected: false, error: e.toString());
    }
  }

  /// Weight files in a model folder, or null when listing failed. A 404 on
  /// checkpoints means a build without /models, so we can't tell; a 404 on
  /// an optional folder (older builds lack diffusion_models) counts as empty.
  Future<int?> _probeModelCount(
    String folder, {
    bool missingIsEmpty = false,
  }) async {
    try {
      final r = await _dio.get('/models/$folder', options: probeOptions());
      final data = r.data;
      if (data is! List) return null;
      return data.map((e) => e.toString()).where(isComfyWeightFilename).length;
    } on DioException catch (e) {
      return missingIsEmpty && isNotFound(e) ? 0 : null;
    } catch (_) {
      return null;
    }
  }

  /// Cheap check for an A1111/Forge answering on the configured ComfyUI port.
  Future<bool> _looksLikeA1111() async {
    try {
      final r = await _dio.get('/sdapi/v1/options', options: probeOptions());
      return r.data is Map &&
          (r.data as Map).containsKey('sd_model_checkpoint');
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> objectInfo() async {
    final response = await _dio.get('/object_info');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<String>> _listModels(String folder) async {
    try {
      final response = await _dio.get('/models/$folder');
      final data = response.data;
      if (data is List) {
        return data.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<SdModel>> getCheckpoints() async {
    var names = (await _listModels('checkpoints'))
        .where(isComfyWeightFilename)
        .toList();
    if (names.isEmpty) {
      try {
        final info = await _dio.get('/object_info/CheckpointLoaderSimple');
        names = _comboOptions(
          info.data,
          'CheckpointLoaderSimple',
          'ckpt_name',
        ).where(isComfyWeightFilename).toList();
      } catch (_) {}
    }
    return names
        .map((n) => SdModel(title: n, modelName: n, filename: n))
        .toList();
  }

  Future<List<SdModel>> getModels() async {
    final seen = <String>{};
    final models = <SdModel>[];
    void addNames(Iterable<String> names) {
      for (final name in names) {
        if (seen.add(name)) {
          models.add(SdModel(title: name, modelName: name, filename: name));
        }
      }
    }

    addNames((await _listModels('checkpoints')).where(isComfyWeightFilename));
    addNames((await _listModels('unet')).where(isComfyWeightFilename));
    addNames((await _listModels('diffusion_models')).where(isComfyWeightFilename));
    if (models.isEmpty) {
      addNames((await getCheckpoints()).map((m) => m.title));
    }
    return models;
  }

  Future<List<SdSampler>> getSamplers() async {
    try {
      final info = await _dio.get('/object_info/KSampler');
      return _comboOptions(info.data, 'KSampler', 'sampler_name')
          .map((n) => SdSampler(name: n))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SdScheduler>> getSchedulers() async {
    try {
      final info = await _dio.get('/object_info/KSampler');
      return _comboOptions(info.data, 'KSampler', 'scheduler')
          .map((n) => SdScheduler(name: n, label: n))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SdLora>> getLoras() async {
    final names = (await _listModels('loras')).where(isComfyWeightFilename);
    return names.map((n) => SdLora(name: n, path: n)).toList();
  }

  Future<List<SdVae>> getVaes() async {
    final names = await _listModels('vae');
    return [
      const SdVae(modelName: 'Automatic', filename: 'Automatic'),
      ...names.map((n) => SdVae(modelName: n, filename: n)),
    ];
  }

  Future<List<SdUpscaler>> getUpscalers() async {
    final names = await _listModels('upscale_models');
    return names.map((n) => SdUpscaler(name: n, modelName: n)).toList();
  }

  List<String> _comboOptions(dynamic data, String node, String input) {
    final root = data is Map ? data[node] ?? data : null;
    if (root is! Map) return const [];
    final required = root['input'] is Map ? root['input']['required'] : null;
    final optional = root['input'] is Map ? root['input']['optional'] : null;
    dynamic spec;
    if (required is Map && required[input] != null) spec = required[input];
    if (spec == null && optional is Map) spec = optional[input];
    if (spec is List && spec.isNotEmpty && spec.first is List) {
      return (spec.first as List).map((e) => e.toString()).toList();
    }
    return const [];
  }

  Future<List<ComfyWorkflowInfo>> listWorkflows() async {
    final found = <String, ComfyWorkflowInfo>{};
    for (final dir in const ['workflows', 'user/default/workflows']) {
      for (final item in await _listUserdataWorkflows(dir)) {
        found[item.path] = item;
      }
    }
    final items = found.values.toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return items;
  }

  Future<List<ComfyWorkflowInfo>> _listUserdataWorkflows(
    String dir, {
    int depth = 0,
  }) async {
    final workflows = <ComfyWorkflowInfo>[];
    try {
      for (final path in const ['/v2/userdata', '/api/v2/userdata']) {
        try {
          final response = await _dio.get(
            path,
            queryParameters: {'path': dir},
          );
          if (response.statusCode == 200 && response.data is List) {
            for (final entry in response.data as List) {
              if (entry is! Map) continue;
              final type = entry['type']?.toString();
              final itemPath =
                  (entry['path'] ?? entry['name'])?.toString() ?? '';
              if (itemPath.isEmpty) continue;
              if (type == 'directory') {
                if (itemPath == dir || depth >= 2) continue;
                workflows.addAll(
                  await _listUserdataWorkflows(itemPath, depth: depth + 1),
                );
                continue;
              }
              if (type != null && type != 'file') continue;
              final info = _parseWorkflowEntry(entry, fallbackDir: dir);
              if (info != null) workflows.add(info);
            }
            if (workflows.isNotEmpty) return workflows;
          }
        } catch (_) {}
      }

      for (final path in const ['/userdata', '/api/userdata']) {
        try {
          final response = await _dio.get(
            path,
            queryParameters: {'dir': dir, 'recurse': 'true'},
          );
          if (response.statusCode != 200 || response.data is! List) continue;
          for (final entry in response.data as List) {
            final info = _parseWorkflowEntry(entry, fallbackDir: dir);
            if (info != null) workflows.add(info);
          }
          if (workflows.isNotEmpty) return workflows;
        } catch (_) {}
      }
    } catch (_) {}
    return workflows;
  }

  ComfyWorkflowInfo? _parseWorkflowEntry(
    dynamic entry, {
    required String fallbackDir,
  }) {
    String? rel;
    int? size;
    DateTime? modified;
    if (entry is String) {
      rel = entry;
    } else if (entry is List && entry.isNotEmpty) {
      rel = entry.first.toString();
    } else if (entry is Map) {
      rel = (entry['path'] ?? entry['name'] ?? entry['file'])?.toString();
      size = (entry['size'] as num?)?.toInt();
      final modifiedRaw = entry['modified'];
      if (modifiedRaw is num) {
        final ms = modifiedRaw > 20000000000 ? modifiedRaw : modifiedRaw * 1000;
        modified = DateTime.fromMillisecondsSinceEpoch(ms.round());
      }
    }
    if (rel == null || rel.isEmpty) return null;
    final normalized = rel.replaceAll('\\', '/');
    if (!normalized.toLowerCase().endsWith('.json')) return null;
    final path = normalized.contains('/')
        ? normalized
        : '$fallbackDir/$normalized';
    return ComfyWorkflowInfo(
      path: path,
      name: path.split('/').last,
      size: size,
      modifiedAt: modified,
    );
  }

  Future<ComfyHistoryGraph?> fetchLastRun() async {
    try {
      final response = await _dio.get('/history');
      final graphs = parseComfyHistory(response.data);
      return pickLastRunGraph(graphs);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getWorkflow(String path) async {
    if (isComfyLastRunWorkflowPath(path)) {
      final last = await fetchLastRun();
      if (last == null) {
        throw Exception(
          'ComfyUI has not run a graph yet. Run one in Comfy Desktop, then refresh workflows.',
        );
      }
      return last.graph;
    }
    if (isComfyBuiltinSdWorkflowPath(path)) {
      return builtinSdCheckpointGraph();
    }

    final encoded = Uri.encodeComponent(path);
    final attempts = <String>[
      '/api/userdata/$encoded',
      '/userdata/$encoded',
      '/api/v2/userdata',
      '/v2/userdata',
    ];
    DioException? last;
    for (final url in attempts) {
      try {
        final response = url.endsWith('userdata')
            ? await _dio.get(url, queryParameters: {'path': path})
            : await _dio.get(url);
        return _asWorkflowMap(response.data);
      } on DioException catch (e) {
        last = e;
      } catch (_) {}
    }
    throw last ?? Exception('Could not load workflow $path');
  }

  Map<String, dynamic> _asWorkflowMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw Exception('Workflow file was not valid JSON');
  }

  Future<ComfyPromptResult> queuePrompt(Map<String, dynamic> prompt) async {
    final response = await _dio.post('/prompt', data: {
      'prompt': prompt,
      'client_id': clientId,
    });
    final data = response.data as Map;
    final id = data['prompt_id']?.toString();
    if (id == null || id.isEmpty) {
      throw Exception('ComfyUI did not return a prompt id');
    }
    return ComfyPromptResult(
      promptId: id,
      number: (data['number'] as num?)?.toInt() ?? 0,
    );
  }

  Future<ComfyQueueStatus> queueStatus({String? promptId}) async {
    final response = await _dio.get('/queue');
    final data = response.data as Map;
    final running = data['queue_running'] as List? ?? const [];
    final pending = data['queue_pending'] as List? ?? const [];
    var isRunning = running.isNotEmpty;
    if (promptId != null) {
      isRunning = running.any((item) {
        if (item is List && item.length > 1) return item[1]?.toString() == promptId;
        return false;
      });
    }
    return ComfyQueueStatus(running: isRunning, pending: pending.length);
  }

  Future<Map<String, dynamic>?> history(String promptId) async {
    final response = await _dio.get('/history/$promptId');
    final data = response.data;
    if (data is Map && data[promptId] is Map) {
      return Map<String, dynamic>.from(data[promptId] as Map);
    }
    return null;
  }

  Future<List<String>> downloadHistoryImages(Map<String, dynamic> history) async {
    final outputs = history['outputs'];
    if (outputs is! Map) return const [];
    final images = <String>[];
    for (final nodeOut in outputs.values) {
      if (nodeOut is! Map) continue;
      final files = nodeOut['images'];
      if (files is! List) continue;
      for (final file in files) {
        if (file is! Map) continue;
        final filename = file['filename']?.toString();
        if (filename == null || filename.isEmpty) continue;
        final bytes = await viewImage(
          filename: filename,
          subfolder: file['subfolder']?.toString() ?? '',
          type: file['type']?.toString() ?? 'output',
        );
        images.add(base64Encode(bytes));
      }
    }
    return images;
  }

  Future<List<int>> viewImage({
    required String filename,
    String subfolder = '',
    String type = 'output',
  }) async {
    final response = await _dio.get<List<int>>(
      '/view',
      queryParameters: {
        'filename': filename,
        'subfolder': subfolder,
        'type': type,
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<String> uploadImage(List<int> bytes, String filename) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(bytes, filename: filename),
      'overwrite': 'true',
    });
    final response = await _dio.post(
      '/upload/image',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = response.data as Map;
    return data['name']?.toString() ?? filename;
  }

  Future<void> interrupt() async {
    try {
      await _dio.post('/interrupt');
    } catch (_) {}
  }

  void dispose() => _dio.close();

  String _humanizeError(DioException e) =>
      humanizeStatusCode(e, unreachable: 'ComfyUI');
}
