import 'dart:convert';

class Session {
  final String id;
  final String title;
  final String? serverId;
  final String? personaId;
  final String? folderId;
  final String? thumbnailPath;
  final int generationCount;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Session({
    required this.id,
    required this.title,
    this.serverId,
    this.personaId,
    this.folderId,
    this.thumbnailPath,
    this.generationCount = 0,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Session copyWith({
    String? title,
    String? serverId,
    String? personaId,
    String? folderId,
    String? thumbnailPath,
    int? generationCount,
    bool? isFavorite,
    DateTime? updatedAt,
  }) =>
      Session(
        id: id,
        title: title ?? this.title,
        serverId: serverId ?? this.serverId,
        personaId: personaId ?? this.personaId,
        folderId: folderId ?? this.folderId,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        generationCount: generationCount ?? this.generationCount,
        isFavorite: isFavorite ?? this.isFavorite,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'server_id': serverId,
        'persona_id': personaId,
        'folder_id': folderId,
        'thumbnail_path': thumbnailPath,
        'generation_count': generationCount,
        'is_favorite': isFavorite ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Session.fromMap(Map<String, dynamic> map) => Session(
        id: map['id'] as String,
        title: map['title'] as String,
        serverId: map['server_id'] as String?,
        personaId: map['persona_id'] as String?,
        folderId: map['folder_id'] as String?,
        thumbnailPath: map['thumbnail_path'] as String?,
        generationCount: map['generation_count'] as int? ?? 0,
        isFavorite: (map['is_favorite'] as int?) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

enum MessageRole { user, assistant }

class SessionMessage {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String prompt;
  final String negativePrompt;
  final Map<String, dynamic> parameters;
  final List<String> imagePaths;
  final int? seed;
  final String? modelName;
  final DateTime createdAt;

  const SessionMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    this.prompt = '',
    this.negativePrompt = '',
    this.parameters = const {},
    this.imagePaths = const [],
    this.seed,
    this.modelName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'role': role.name,
        'prompt': prompt,
        'negative_prompt': negativePrompt,
        'parameters': jsonEncode(parameters),
        'image_paths': jsonEncode(imagePaths),
        'seed': seed,
        'model_name': modelName,
        'created_at': createdAt.toIso8601String(),
      };

  factory SessionMessage.fromMap(Map<String, dynamic> map) => SessionMessage(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        role: MessageRole.values.byName(map['role'] as String),
        prompt: map['prompt'] as String? ?? '',
        negativePrompt: map['negative_prompt'] as String? ?? '',
        parameters: map['parameters'] != null
            ? jsonDecode(map['parameters'] as String) as Map<String, dynamic>
            : {},
        imagePaths: map['image_paths'] != null
            ? (jsonDecode(map['image_paths'] as String) as List).cast<String>()
            : [],
        seed: map['seed'] as int?,
        modelName: map['model_name'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class GeneratedImage {
  final String id;
  final String sessionId;
  final String messageId;
  final String filePath;
  final String? thumbnailPath;
  final String prompt;
  final String negativePrompt;
  final String? modelName;
  final String loraConfigs;
  final String? samplerName;
  final int? steps;
  final double? cfgScale;
  final int? seed;
  final int? width;
  final int? height;
  final bool isFavorite;
  final String? folderId;
  final DateTime createdAt;

  const GeneratedImage({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.filePath,
    this.thumbnailPath,
    this.prompt = '',
    this.negativePrompt = '',
    this.modelName,
    this.loraConfigs = '[]',
    this.samplerName,
    this.steps,
    this.cfgScale,
    this.seed,
    this.width,
    this.height,
    this.isFavorite = false,
    this.folderId,
    required this.createdAt,
  });

  GeneratedImage copyWith({
    bool? isFavorite,
    String? folderId,
  }) =>
      GeneratedImage(
        id: id,
        sessionId: sessionId,
        messageId: messageId,
        filePath: filePath,
        thumbnailPath: thumbnailPath,
        prompt: prompt,
        negativePrompt: negativePrompt,
        modelName: modelName,
        loraConfigs: loraConfigs,
        samplerName: samplerName,
        steps: steps,
        cfgScale: cfgScale,
        seed: seed,
        width: width,
        height: height,
        isFavorite: isFavorite ?? this.isFavorite,
        folderId: folderId ?? this.folderId,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'message_id': messageId,
        'file_path': filePath,
        'thumbnail_path': thumbnailPath,
        'prompt': prompt,
        'negative_prompt': negativePrompt,
        'model_name': modelName,
        'lora_configs': loraConfigs,
        'sampler_name': samplerName,
        'steps': steps,
        'cfg_scale': cfgScale,
        'seed': seed,
        'width': width,
        'height': height,
        'is_favorite': isFavorite ? 1 : 0,
        'folder_id': folderId,
        'created_at': createdAt.toIso8601String(),
      };

  factory GeneratedImage.fromMap(Map<String, dynamic> map) => GeneratedImage(
        id: map['id'] as String,
        sessionId: map['session_id'] as String,
        messageId: map['message_id'] as String,
        filePath: map['file_path'] as String,
        thumbnailPath: map['thumbnail_path'] as String?,
        prompt: map['prompt'] as String? ?? '',
        negativePrompt: map['negative_prompt'] as String? ?? '',
        modelName: map['model_name'] as String?,
        loraConfigs: map['lora_configs'] as String? ?? '[]',
        samplerName: map['sampler_name'] as String?,
        steps: map['steps'] as int?,
        cfgScale: (map['cfg_scale'] as num?)?.toDouble(),
        seed: map['seed'] as int?,
        width: map['width'] as int?,
        height: map['height'] as int?,
        isFavorite: (map['is_favorite'] as int?) == 1,
        folderId: map['folder_id'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class Folder {
  final String id;
  final String name;
  final String? parentId;
  final String icon;
  final int color;
  final DateTime createdAt;

  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.icon = 'folder',
    this.color = 0xFF3B82F6,
    required this.createdAt,
  });

  Folder copyWith({
    String? name,
    String? parentId,
    String? icon,
    int? color,
  }) =>
      Folder(
        id: id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'parent_id': parentId,
        'icon': icon,
        'color': color,
        'created_at': createdAt.toIso8601String(),
      };

  factory Folder.fromMap(Map<String, dynamic> map) => Folder(
        id: map['id'] as String,
        name: map['name'] as String,
        parentId: map['parent_id'] as String?,
        icon: map['icon'] as String? ?? 'folder',
        color: map['color'] as int? ?? 0xFF3B82F6,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
