enum GenerationBackend {
  a1111,
  comfyui,
  appleMl;

  String get id => name;

  String get label {
    switch (this) {
      case GenerationBackend.a1111:
        return 'A1111';
      case GenerationBackend.comfyui:
        return 'ComfyUI';
      case GenerationBackend.appleMl:
        return 'Apple ML';
    }
  }

  String get subtitle {
    switch (this) {
      case GenerationBackend.a1111:
        return 'Automatic1111 / Forge';
      case GenerationBackend.comfyui:
        return 'Node workflows';
      case GenerationBackend.appleMl:
        return 'On-device Core ML';
    }
  }

  int get defaultPort {
    switch (this) {
      case GenerationBackend.a1111:
        return 7860;
      case GenerationBackend.comfyui:
        return 8188;
      case GenerationBackend.appleMl:
        return 0;
    }
  }

  bool get requiresRemoteServer {
    switch (this) {
      case GenerationBackend.a1111:
      case GenerationBackend.comfyui:
        return true;
      case GenerationBackend.appleMl:
        return false;
    }
  }

  static GenerationBackend fromId(String? id) {
    return GenerationBackend.values.firstWhere(
      (e) => e.id == id,
      orElse: () => GenerationBackend.a1111,
    );
  }
}

class ComfyWorkflowInfo {
  final String path;
  final String name;
  final int? size;
  final DateTime? modifiedAt;
  final bool builtin;

  const ComfyWorkflowInfo({
    required this.path,
    required this.name,
    this.size,
    this.modifiedAt,
    this.builtin = false,
  });

  String get displayName {
    final trimmed = name.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    return trimmed.isEmpty ? name : trimmed;
  }
}
