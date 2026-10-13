import 'generation_backend.dart';

class Server {
  final String id;
  final String name;
  final String host;
  final int port;
  final GenerationBackend provider;
  final String? authToken;
  final bool isActive;
  final DateTime? lastConnectedAt;
  final DateTime createdAt;

  const Server({
    required this.id,
    required this.name,
    required this.host,
    this.port = 7860,
    this.provider = GenerationBackend.a1111,
    this.authToken,
    this.isActive = false,
    this.lastConnectedAt,
    required this.createdAt,
  });

  /// True when this server is reached through LM Mini Connect / the relay.
  bool get isRemote {
    final token = authToken?.trim() ?? '';
    if (token.isNotEmpty) return true;
    return host.contains('/s/');
  }

  String get displayAddress {
    if (isRemote) {
      final uri = Uri.tryParse(baseUrl);
      return uri?.host.isNotEmpty == true ? uri!.host : baseUrl;
    }
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return baseUrl;
    }
    return '$host:$port';
  }

  /// Build the base URL. If [host] already starts with http(s)://, use it
  /// as-is (stripping trailing slash). Otherwise fall back to http://$host:$port.
  String get baseUrl {
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    }
    return 'http://$host:$port';
  }

  Map<String, String> get clientHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = authToken?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['X-LM-Mini-Token'] = token;
      headers['X-LM-Mini-Backend'] = provider.id;
    }
    return headers;
  }

  Server copyWith({
    String? name,
    String? host,
    int? port,
    GenerationBackend? provider,
    String? authToken,
    bool? isActive,
    DateTime? lastConnectedAt,
  }) =>
      Server(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        provider: provider ?? this.provider,
        authToken: authToken ?? this.authToken,
        isActive: isActive ?? this.isActive,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'provider': provider.id,
        'auth_token': authToken,
        'is_active': isActive ? 1 : 0,
        'last_connected_at': lastConnectedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory Server.fromMap(Map<String, dynamic> map) {
    final token = map['auth_token'] as String?;
    return Server(
      id: map['id'] as String,
      name: map['name'] as String,
      host: map['host'] as String,
      port: map['port'] as int,
      provider: GenerationBackend.fromId(map['provider'] as String?),
      authToken: (token == null || token.isEmpty) ? null : token,
      isActive: (map['is_active'] as int) == 1,
      lastConnectedAt: map['last_connected_at'] != null
          ? DateTime.parse(map['last_connected_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
