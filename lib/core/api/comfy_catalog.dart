/// Weight files Comfy can load. Checkpoint folders also contain SD config
/// YAML next to models — those are not loadable weights.
bool isComfyWeightFilename(String name) {
  final base = name.trim().split('/').last.split('\\').last.toLowerCase();
  if (base.isEmpty || !base.contains('.')) return false;
  const configs = ['.yaml', '.yml', '.json', '.txt', '.md', '.csv'];
  if (configs.any(base.endsWith)) return false;
  const weights = [
    '.safetensors',
    '.ckpt',
    '.pt',
    '.pth',
    '.bin',
    '.gguf',
    '.sft',
    '.onnx',
  ];
  return weights.any(base.endsWith);
}

/// Stable id so last-run can skip graphs the phone queued.
const kA1111MiniComfyClientId = 'a1111-mini';

class ComfyHistoryGraph {
  final String promptId;
  final Map<String, dynamic> graph;
  final String? clientId;

  const ComfyHistoryGraph({
    required this.promptId,
    required this.graph,
    this.clientId,
  });

  String? get loaderLabel {
    final unet = firstComfyInputValue(graph, 'unet_name');
    if (unet != null && unet.isNotEmpty) return unet;
    return firstComfyInputValue(graph, 'ckpt_name');
  }
}

/// Newest-first graphs from `GET /history`.
List<ComfyHistoryGraph> parseComfyHistory(Object? decoded) {
  if (decoded is! Map) return const [];
  final entries = <({int order, ComfyHistoryGraph graph})>[];
  decoded.forEach((key, value) {
    if (value is! Map) return;
    final graph = extractComfyPromptGraph(value);
    if (graph == null || graph.isEmpty) return;
    var order = 0;
    final prompt = value['prompt'];
    if (prompt is List && prompt.isNotEmpty && prompt.first is num) {
      order = (prompt.first as num).toInt();
    }
    entries.add((
      order: order,
      graph: ComfyHistoryGraph(
        promptId: key.toString(),
        graph: graph,
        clientId: extractComfyClientId(value),
      ),
    ));
  });
  entries.sort((a, b) => b.order.compareTo(a.order));
  return [for (final e in entries) e.graph];
}

/// Newest desktop graph, skipping phone-injected A1111-default overlays.
ComfyHistoryGraph? pickLastRunGraph(List<ComfyHistoryGraph> graphs) {
  if (graphs.isEmpty) return null;
  final notOurs = graphs
      .where((g) => g.clientId != kA1111MiniComfyClientId)
      .toList();
  final pool = notOurs.isNotEmpty ? notOurs : graphs;
  final notOverlay =
      pool.where((g) => !looksLikeA1111DefaultOverlay(g.graph)).toList();
  return (notOverlay.isNotEmpty ? notOverlay : pool).first;
}

String? extractComfyClientId(Map value) {
  Object? extra;
  final prompt = value['prompt'];
  if (prompt is List && prompt.length > 3) extra = prompt[3];
  extra ??= value['extra_data'];
  extra ??= value['meta'];
  if (extra is Map) {
    final id = extra['client_id'] ?? extra['clientId'];
    if (id != null && id.toString().trim().isNotEmpty) {
      return id.toString();
    }
  }
  final top = value['client_id'] ?? value['clientId'];
  if (top != null && top.toString().trim().isNotEmpty) {
    return top.toString();
  }
  return null;
}

/// Phone gens used to rewrite last-run Z-Image to 512 / CFG 7 / Euler.
bool looksLikeA1111DefaultOverlay(Map<String, dynamic> graph) {
  final width = firstComfyNumeric(graph, 'width');
  final cfg = firstComfyNumeric(graph, 'cfg');
  final sampler = firstComfyInputValue(graph, 'sampler_name');
  if (width != 512) return false;
  if (cfg == null || (cfg - 7.0).abs() > 0.051) return false;
  return sampler == 'euler' || sampler == 'euler_ancestral';
}

num? firstComfyNumeric(Map<String, dynamic> graph, String inputName) {
  for (final value in graph.values) {
    if (value is! Map) continue;
    final inputs = value['inputs'];
    if (inputs is! Map) continue;
    final raw = inputs[inputName];
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw);
  }
  return null;
}

Map<String, dynamic>? extractComfyPromptGraph(Object? historyEntry) {
  if (historyEntry is! Map) return null;
  final prompt = historyEntry['prompt'];
  if (prompt is List && prompt.length > 2 && prompt[2] is Map) {
    return _stringKeyMap(prompt[2] as Map);
  }
  if (prompt is Map) {
    final nested = prompt['prompt'];
    if (nested is Map) return _stringKeyMap(nested);
    final asGraph = _stringKeyMap(prompt);
    if (_looksLikePromptGraph(asGraph)) return asGraph;
  }
  final workflow = historyEntry['workflow'];
  if (workflow is Map) {
    final asGraph = _stringKeyMap(workflow);
    if (_looksLikePromptGraph(asGraph)) return asGraph;
  }
  return null;
}

String? firstComfyInputValue(Map<String, dynamic> graph, String inputName) {
  for (final value in graph.values) {
    if (value is! Map) continue;
    final inputs = value['inputs'];
    if (inputs is! Map) continue;
    final raw = inputs[inputName];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  }
  return null;
}

bool _looksLikePromptGraph(Map<String, dynamic> workflow) {
  return workflow.values.any(
    (value) => value is Map && value['class_type'] is String,
  );
}

Map<String, dynamic> _stringKeyMap(Map map) {
  return {
    for (final entry in map.entries) entry.key.toString(): entry.value,
  };
}
