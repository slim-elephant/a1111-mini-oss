import 'api_models.dart';

/// Abstract interface for A1111 / Forge communication.
abstract class IA1111Client {
  String get baseUrl;

  // Connection
  Future<ConnectionStatus> testConnection();

  // Generation
  Future<GenerationResponse> txt2img(Txt2ImgRequest request);
  Future<GenerationResponse> img2img(Img2ImgRequest request);
  Future<ExtrasSingleResponse> extraSingle(ExtrasSingleRequest request);
  Future<PngInfoResponse> pngInfo(String imageBase64);

  // Listings
  Future<List<SdModel>> getModels();
  Future<List<SdSampler>> getSamplers();
  Future<List<SdScheduler>> getSchedulers();
  Future<List<SdLora>> getLoras();
  Future<List<SdVae>> getVaes();
  Future<List<SdUpscaler>> getUpscalers();
  Future<List<SdPromptStyle>> getPromptStyles();

  // ControlNet
  Future<Map<String, dynamic>> controlNetTypes();
  Future<List<String>> controlNetModels();
  Future<List<String>> controlNetModules();

  // Settings
  Future<void> setModel(String modelTitle);
  Future<void> setVae(String vaeName);
  Future<Map<String, dynamic>> getOptions();

  // Progress
  Future<GenerationProgress> getProgress({bool skipCurrentImage = true});
  Future<void> interrupt();

  // Refresh listings (server-side)
  Future<void> refreshLoras();
  Future<void> refreshCheckpoints();
  Future<void> refreshVae();

  void dispose();
}
