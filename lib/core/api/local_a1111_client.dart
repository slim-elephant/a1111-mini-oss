import 'package:dio/dio.dart';
import 'a1111_client_interface.dart';
import 'api_models.dart';
import 'connection_retry.dart';

class LocalA1111Client implements IA1111Client {
  final Dio _dio;
  final String _baseUrl;

  @override
  String get baseUrl => _baseUrl;

  LocalA1111Client({
    required String host,
    required int port,
    String? authToken,
    String? backendHeader,
    Duration receiveTimeout = const Duration(minutes: 10),
  })  : _baseUrl = _buildUrl(host, port),
        _dio = Dio(BaseOptions(
          baseUrl: _buildUrl(host, port),
          connectTimeout: Duration(
            seconds: (authToken != null && authToken.isNotEmpty) ? 25 : 10,
          ),
          receiveTimeout: receiveTimeout,
          sendTimeout: const Duration(minutes: 5),
          headers: _clientHeaders(authToken, backendHeader ?? 'a1111'),
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

  // ── Connection ────────────────────────────────────────────────
  @override
  Future<ConnectionStatus> testConnection() {
    return withConnectionRetries(_testConnectionOnce);
  }

  Future<ConnectionStatus> _testConnectionOnce() async {
    try {
      final response =
          await _dio.get('/sdapi/v1/options', options: probeOptions());
      final data = response.data;
      if (data is! Map) {
        return ConnectionStatus(
          connected: false,
          error: unexpectedResponseMessage('A1111'),
        );
      }
      return ConnectionStatus(
        connected: true,
        currentModel: data['sd_model_checkpoint'] as String?,
        warning: noModelsWarning([await _probeModelCount()]),
      );
    } on DioException catch (e) {
      if (isNotFound(e) && await _looksLikeComfy()) {
        return ConnectionStatus(
          connected: false,
          error: wrongBackendMessage(found: 'ComfyUI', expected: 'A1111'),
        );
      }
      return ConnectionStatus(connected: false, error: _humanizeError(e));
    } catch (e) {
      return ConnectionStatus(connected: false, error: e.toString());
    }
  }

  /// Number of checkpoints, or null when the listing itself failed.
  Future<int?> _probeModelCount() async {
    try {
      final r = await _dio.get('/sdapi/v1/sd-models', options: probeOptions());
      return r.data is List ? (r.data as List).length : null;
    } catch (_) {
      return null;
    }
  }

  /// Cheap check for a ComfyUI answering on the configured A1111 port.
  Future<bool> _looksLikeComfy() async {
    try {
      final r = await _dio.get('/system_stats', options: probeOptions());
      return r.data is Map && (r.data as Map).containsKey('devices');
    } catch (_) {
      return false;
    }
  }

  // ── Generation ────────────────────────────────────────────────
  @override
  Future<GenerationResponse> txt2img(Txt2ImgRequest request) async {
    final response = await _dio.post(
      '/sdapi/v1/txt2img',
      data: request.toJson(),
    );
    return GenerationResponse.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<GenerationResponse> img2img(Img2ImgRequest request) async {
    final response = await _dio.post(
      '/sdapi/v1/img2img',
      data: request.toJson(),
    );
    return GenerationResponse.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<ExtrasSingleResponse> extraSingle(ExtrasSingleRequest request) async {
    final response = await _dio.post(
      '/sdapi/v1/extra-single-image',
      data: request.toJson(),
    );
    return ExtrasSingleResponse.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<PngInfoResponse> pngInfo(String imageBase64) async {
    // Forge accepts the raw base64; some builds want a data: prefix.
    final payload = imageBase64.startsWith('data:')
        ? imageBase64
        : 'data:image/png;base64,$imageBase64';
    final response = await _dio.post(
      '/sdapi/v1/png-info',
      data: {'image': payload},
    );
    return PngInfoResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Listings ──────────────────────────────────────────────────
  @override
  Future<List<SdModel>> getModels() async {
    final r = await _dio.get('/sdapi/v1/sd-models');
    return (r.data as List)
        .map((e) => SdModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SdSampler>> getSamplers() async {
    final r = await _dio.get('/sdapi/v1/samplers');
    return (r.data as List)
        .map((e) => SdSampler.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SdScheduler>> getSchedulers() async {
    try {
      final r = await _dio.get('/sdapi/v1/schedulers');
      return (r.data as List)
          .map((e) => SdScheduler.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException {
      return const []; // Older A1111 builds don't expose schedulers.
    }
  }

  @override
  Future<List<SdLora>> getLoras() async {
    final r = await _dio.get('/sdapi/v1/loras');
    return (r.data as List)
        .map((e) => SdLora.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SdVae>> getVaes() async {
    try {
      final r = await _dio.get('/sdapi/v1/sd-modules');
      return (r.data as List)
          .map((e) => SdVae.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException {
      return const [];
    }
  }

  @override
  Future<List<SdUpscaler>> getUpscalers() async {
    final r = await _dio.get('/sdapi/v1/upscalers');
    return (r.data as List)
        .map((e) => SdUpscaler.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SdPromptStyle>> getPromptStyles() async {
    try {
      final r = await _dio.get('/sdapi/v1/prompt-styles');
      return (r.data as List)
          .map((e) => SdPromptStyle.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException {
      return const [];
    }
  }

  // ── ControlNet ────────────────────────────────────────────────
  @override
  Future<Map<String, dynamic>> controlNetTypes() async {
    try {
      final r = await _dio.get('/controlnet/control_types');
      final data = r.data;
      if (data is Map<String, dynamic>) {
        // Server returns either a flat map or { "control_types": {...} }
        if (data['control_types'] is Map) {
          return (data['control_types'] as Map).cast<String, dynamic>();
        }
        return data;
      }
      return const {};
    } on DioException {
      return const {};
    }
  }

  @override
  Future<List<String>> controlNetModels() async {
    try {
      final r = await _dio.get('/controlnet/model_list');
      final data = r.data;
      if (data is Map && data['model_list'] is List) {
        return (data['model_list'] as List).cast<String>();
      }
      return const [];
    } on DioException {
      return const [];
    }
  }

  @override
  Future<List<String>> controlNetModules() async {
    try {
      final r = await _dio.get('/controlnet/module_list');
      final data = r.data;
      if (data is Map && data['module_list'] is List) {
        return (data['module_list'] as List).cast<String>();
      }
      return const [];
    } on DioException {
      return const [];
    }
  }

  // ── Settings ──────────────────────────────────────────────────
  @override
  Future<void> setModel(String modelTitle) async {
    await _dio.post(
      '/sdapi/v1/options',
      data: {'sd_model_checkpoint': modelTitle},
    );
  }

  @override
  Future<void> setVae(String vaeName) async {
    await _dio.post(
      '/sdapi/v1/options',
      data: {'sd_vae': vaeName},
    );
  }

  @override
  Future<Map<String, dynamic>> getOptions() async {
    final r = await _dio.get('/sdapi/v1/options');
    return r.data as Map<String, dynamic>;
  }

  // ── Progress ──────────────────────────────────────────────────
  @override
  Future<GenerationProgress> getProgress({bool skipCurrentImage = true}) async {
    final r = await _dio.get(
      '/sdapi/v1/progress',
      queryParameters: {'skip_current_image': skipCurrentImage},
    );
    return GenerationProgress.fromJson(r.data as Map<String, dynamic>);
  }

  @override
  Future<void> interrupt() async {
    await _dio.post('/sdapi/v1/interrupt');
  }

  // ── Refresh ───────────────────────────────────────────────────
  @override
  Future<void> refreshLoras() async {
    try {
      await _dio.post('/sdapi/v1/refresh-loras');
    } on DioException {/* best-effort */}
  }

  @override
  Future<void> refreshCheckpoints() async {
    try {
      await _dio.post('/sdapi/v1/refresh-checkpoints');
    } on DioException {/* best-effort */}
  }

  @override
  Future<void> refreshVae() async {
    try {
      await _dio.post('/sdapi/v1/refresh-vae');
    } on DioException {/* best-effort */}
  }

  @override
  void dispose() {
    _dio.close();
  }

  String _humanizeError(DioException e) {
    if (e.type == DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 502 || code == 503) {
        return humanizeStatusCode(e, unreachable: 'A1111');
      }
      return 'Server responded with error $code. Make sure A1111 was started with --api flag.';
    }
    return humanizeStatusCode(e, unreachable: 'A1111');
  }
}
