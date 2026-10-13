class AiProfile {
  final String id;
  final String name;
  final String icon;
  final int color;
  final String positivePrompt;
  final String negativePrompt;
  final DateTime createdAt;

  const AiProfile({
    required this.id,
    required this.name,
    this.icon = 'auto_awesome',
    this.color = 0xFF3B82F6,
    this.positivePrompt = '',
    this.negativePrompt = '',
    required this.createdAt,
  });

  AiProfile copyWith({
    String? name,
    String? icon,
    int? color,
    String? positivePrompt,
    String? negativePrompt,
  }) =>
      AiProfile(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        positivePrompt: positivePrompt ?? this.positivePrompt,
        negativePrompt: negativePrompt ?? this.negativePrompt,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'positive_prompt': positivePrompt,
        'negative_prompt': negativePrompt,
        'created_at': createdAt.toIso8601String(),
      };

  factory AiProfile.fromMap(Map<String, dynamic> map) => AiProfile(
        id: map['id'] as String,
        name: map['name'] as String,
        icon: map['icon'] as String,
        color: map['color'] as int,
        positivePrompt: map['positive_prompt'] as String,
        negativePrompt: map['negative_prompt'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
