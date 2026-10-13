import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../api/api_models.dart';
import '../api/apple_ml_sd_plugin.dart';
import '../api/comfy_builtin_workflows.dart';
import '../api/comfyui_workflow.dart';
import '../api/generation_options.dart';
import '../models/generation_backend.dart';
import '../models/session.dart';
import '../on_device/apple_ml_downloader.dart';
import '../on_device/apple_ml_models.dart';
import '../premium/entitlements.dart';
import '../utils/image_storage.dart';
import 'core_providers.dart';
import '../../features/gallery/presentation/gallery_screen.dart';

const _uuid = Uuid();

/// Tracks the state of a single generation job.
class GenerationJob {
  final String sessionId;
  final String prompt;
  final String negativePrompt;
  final Map<String, dynamic> parameters;
  final double progress;
  final double etaRelative;
  final String? previewImageBase64;
  final bool isComplete;
  final bool hasFailed;
  final String? error;
  final String? statusText;
  /// When this job is regenerating into an existing assistant message,
  /// this holds that message's id so the UI can render the progress
  /// overlay inside the original bubble instead of in a new placeholder.
  final String? targetMessageId;

  const GenerationJob({
    required this.sessionId,
    required this.prompt,
    this.negativePrompt = '',
    this.parameters = const {},
    this.progress = 0.0,
    this.etaRelative = 0.0,
    this.previewImageBase64,
    this.isComplete = false,
    this.hasFailed = false,
    this.error,
    this.statusText,
    this.targetMessageId,
  });

  GenerationJob copyWith({
    double? progress,
    double? etaRelative,
    String? previewImageBase64,
    bool clearPreview = false,
    bool? isComplete,
    bool? hasFailed,
    String? error,
    String? statusText,
  }) =>
      GenerationJob(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: parameters,
        progress: progress ?? this.progress,
        etaRelative: etaRelative ?? this.etaRelative,
        previewImageBase64: clearPreview
            ? null
            : (previewImageBase64 ?? this.previewImageBase64),
        isComplete: isComplete ?? this.isComplete,
        hasFailed: hasFailed ?? this.hasFailed,
        error: error ?? this.error,
        statusText: statusText ?? this.statusText,
        targetMessageId: targetMessageId,
      );
}

/// Manages all active and recent generation jobs.
class GenerationServiceNotifier extends StateNotifier<Map<String, GenerationJob>> {
  final Ref _ref;
  final Map<String, Timer> _progressTimers = {};

  GenerationServiceNotifier(this._ref) : super({});

  /// Start a new generation for a session. Persists the session and user message
  /// to DB immediately, then runs the API call in the background.
  Future<void> startGeneration({
    required String sessionId,
    required String prompt,
    required String negativePrompt,
    required String samplerName,
    required int steps,
    required double cfgScale,
    required int width,
    required int height,
    required int seed,
    required int batchSize,
    required bool restoreFaces,
    // ── New (Phase 4) ─────────────────────────────────
    String mode = 'txt2img', // 'txt2img' | 'img2img' | 'inpaint'
    String? scheduler,
    double? distilledCfgScale,
    List<String> styles = const [],
    List<LoraSelection> loras = const [],
    HiresFixConfig? hires,
    RefinerConfig? refiner,
    List<ControlNetUnit> controlNet = const [],
    String? initImagePath,
    String? maskImagePath,
    double denoisingStrength = 0.75,
    int? clipSkip,
    String? vaeOverride,
    int? maskBlur,
    int? inpaintingFill,
    bool? inpaintFullRes,
    String? appendToAssistantMessageId,
    bool persistUserMessage = true,
    String? checkpointOverride,
    List<ComfyWorkflowField> comfyFields = const [],
  }) async {
    // Personas or older sessions may carry more units than the free tier allows.
    if (!_ref.read(hasFeatureProvider(PremiumFeature.extraControlNetUnits))) {
      controlNet = controlNet
          .where((u) => u.enabled)
          .take(kFreeControlNetUnits)
          .toList();
    }
    if (!_ref.read(hasFeatureProvider(PremiumFeature.largeBatch))) {
      batchSize = batchSize.clamp(1, kFreeMaxBatch);
    }
    final backend = _ref.read(activeProviderProvider);
    if (backend == GenerationBackend.appleMl) {
      await _startAppleMlGeneration(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        samplerName: samplerName,
        steps: steps,
        cfgScale: cfgScale,
        width: width,
        height: height,
        seed: seed,
        appendToAssistantMessageId: appendToAssistantMessageId,
        persistUserMessage: persistUserMessage,
      );
      return;
    }
    if (backend == GenerationBackend.comfyui) {
      await _startComfyGeneration(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        samplerName: samplerName,
        steps: steps,
        cfgScale: cfgScale,
        width: width,
        height: height,
        seed: seed,
        batchSize: batchSize,
        restoreFaces: restoreFaces,
        mode: mode,
        scheduler: scheduler,
        distilledCfgScale: distilledCfgScale,
        styles: styles,
        loras: loras,
        hires: hires,
        refiner: refiner,
        controlNet: controlNet,
        initImagePath: initImagePath,
        maskImagePath: maskImagePath,
        denoisingStrength: denoisingStrength,
        clipSkip: clipSkip,
        vaeOverride: vaeOverride,
        appendToAssistantMessageId: appendToAssistantMessageId,
        persistUserMessage: persistUserMessage,
        checkpointOverride: checkpointOverride,
        comfyFields: comfyFields,
      );
      return;
    }

    final client = _ref.read(a1111ClientProvider);
    if (client == null) return;

    final db = await _ref.read(databaseProvider.future);

    // Ensure session is persisted
    final existing = await db.query('sessions',
        where: 'id = ?', whereArgs: [sessionId]);
    if (existing.isEmpty) {
      final title = prompt.length <= 40 ? prompt : '${prompt.substring(0, 40)}...';
      final now = DateTime.now();
      final session = Session(
        id: sessionId,
        title: title,
        serverId: _ref.read(activeServerProvider)?.id,
        createdAt: now,
        updatedAt: now,
      );
      await db.insert('sessions', session.toMap());
      _ref.invalidate(sessionsProvider);
    }

    // Build the effective prompt (append LoRA tokens server expects)
    final loraTokens =
        loras.where((l) => l.name.isNotEmpty).map((l) => l.toPromptToken()).join(' ');
    final effectivePrompt =
        loraTokens.isEmpty ? prompt : '$prompt $loraTokens'.trim();

    final paramSnapshot = <String, dynamic>{
      'mode': mode,
      'sampler_name': samplerName,
      if (scheduler != null && scheduler.isNotEmpty) 'scheduler': scheduler,
      'steps': steps,
      'cfg_scale': cfgScale,
      if (distilledCfgScale != null) 'distilled_cfg_scale': distilledCfgScale,
      'width': width,
      'height': height,
      'seed': seed,
      'restore_faces': restoreFaces,
      'batch_size': batchSize,
      if (styles.isNotEmpty) 'styles': styles,
      if (loras.isNotEmpty)
        'loras': loras
            .map((l) => {'name': l.name, 'weight': l.weight})
            .toList(),
      if (hires != null && hires.enabled) 'hires': hires.toJson(),
      if (refiner != null && refiner.checkpoint != null)
        'refiner': {
          'checkpoint': refiner.checkpoint,
          'switch_at': refiner.switchAt,
        },
      if (controlNet.any((u) => u.enabled))
        'controlnet': controlNet
            .where((u) => u.enabled)
            .map((u) => {
                  'module': u.module,
                  'model': u.model,
                  'weight': u.weight,
                })
            .toList(),
      if (initImagePath != null) 'init_image_path': initImagePath,
      if (maskImagePath != null) 'mask_image_path': maskImagePath,
      if (mode != 'txt2img') 'denoising_strength': denoisingStrength,
      if (clipSkip != null) 'clip_skip': clipSkip,
      if (vaeOverride != null && vaeOverride != 'Automatic')
        'vae': vaeOverride,
    };

    if (persistUserMessage) {
      final userMsgId = _uuid.v4();
      final userMsg = SessionMessage(
        id: userMsgId,
        sessionId: sessionId,
        role: MessageRole.user,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: paramSnapshot,
        createdAt: DateTime.now(),
      );
      await db.insert('session_messages', userMsg.toMap());
    }

    // Track job
    state = {
      ...state,
      sessionId: GenerationJob(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: paramSnapshot,
        targetMessageId: appendToAssistantMessageId,
      ),
    };

    // Poll progress (with live preview)
    _progressTimers[sessionId]?.cancel();
    _progressTimers[sessionId] = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) async {
        try {
          final wantPreview = _ref.read(livePreviewEnabledProvider);
          final progress =
              await client.getProgress(skipCurrentImage: !wantPreview);
          if (state.containsKey(sessionId) && !state[sessionId]!.isComplete) {
            state = {
              ...state,
              sessionId: state[sessionId]!.copyWith(
                progress: progress.progress,
                etaRelative: progress.etaRelative,
                previewImageBase64: progress.currentImage,
              ),
            };
          }
        } catch (_) {}
      },
    );

    // Build override settings
    final overrideSettings = <String, dynamic>{};
    if (clipSkip != null) overrideSettings['CLIP_stop_at_last_layers'] = clipSkip;
    if (vaeOverride != null && vaeOverride != 'Automatic') {
      overrideSettings['sd_vae'] = vaeOverride;
    }

    // Resolve init/mask base64 if needed
    String? initBase64;
    String? maskBase64;
    if (mode != 'txt2img' && initImagePath != null) {
      try {
        final bytes = await File(initImagePath).readAsBytes();
        initBase64 = base64Encode(bytes);
      } catch (_) {}
    }
    if (maskImagePath != null) {
      try {
        final bytes = await File(maskImagePath).readAsBytes();
        maskBase64 = base64Encode(bytes);
      } catch (_) {}
    }

    // Run generation in background
    try {
      final GenerationResponse response;
      if (mode == 'txt2img' || initBase64 == null) {
        final request = Txt2ImgRequest(
          prompt: effectivePrompt,
          negativePrompt: negativePrompt,
          steps: steps,
          cfgScale: cfgScale,
          distilledCfgScale: distilledCfgScale,
          width: width,
          height: height,
          samplerName: samplerName,
          scheduler: scheduler,
          seed: seed,
          batchSize: batchSize,
          restoreFaces: restoreFaces,
          styles: styles,
          hires: hires,
          refiner: refiner,
          controlNet: controlNet,
          overrideSettings:
              overrideSettings.isEmpty ? null : overrideSettings,
        );
        response = await client.txt2img(request);
      } else {
        final request = Img2ImgRequest(
          prompt: effectivePrompt,
          negativePrompt: negativePrompt,
          initImagesBase64: [initBase64],
          maskBase64: maskBase64,
          denoisingStrength: denoisingStrength,
          steps: steps,
          cfgScale: cfgScale,
          distilledCfgScale: distilledCfgScale,
          width: width,
          height: height,
          samplerName: samplerName,
          scheduler: scheduler,
          seed: seed,
          batchSize: batchSize,
          restoreFaces: restoreFaces,
          styles: styles,
          controlNet: controlNet,
          maskBlur: maskBlur,
          inpaintingFill: inpaintingFill,
          inpaintFullRes: inpaintFullRes,
          overrideSettings:
              overrideSettings.isEmpty ? null : overrideSettings,
        );
        response = await client.img2img(request);
      }
      _progressTimers[sessionId]?.cancel();

      // Save images
      final imagePaths = await ImageStorage.saveBase64Images(
        response.images,
        sessionId: sessionId,
      );

      // Parse seed and the checkpoint A1111 actually ran with
      int? resultSeed;
      String? runModel;
      try {
        final info = jsonDecode(response.info) as Map<String, dynamic>;
        resultSeed = info['seed'] as int?;
        runModel = info['sd_model_name'] as String?;
      } catch (_) {}
      runModel ??= _ref.read(connectionStatusProvider).valueOrNull?.currentModel;

      // Save assistant message, or append to an existing one for regenerate.
      String targetMessageId;
      if (appendToAssistantMessageId != null) {
        final existingRows = await db.query(
          'session_messages',
          where: 'id = ? AND session_id = ? AND role = ?',
          whereArgs: [appendToAssistantMessageId, sessionId, MessageRole.assistant.name],
          limit: 1,
        );

        if (existingRows.isNotEmpty) {
          final existing = SessionMessage.fromMap(existingRows.first);
          final mergedPaths = [...existing.imagePaths, ...imagePaths];
          final mergedParams = {
            ...existing.parameters,
            ...paramSnapshot,
            'seed': resultSeed,
            'regeneration_count':
                ((existing.parameters['regeneration_count'] as int?) ?? 0) + 1,
          };
          await db.update(
            'session_messages',
            {
              'image_paths': jsonEncode(mergedPaths),
              'seed': resultSeed,
              'parameters': jsonEncode(mergedParams),
            },
            where: 'id = ?',
            whereArgs: [existing.id],
          );
          targetMessageId = existing.id;
        } else {
          final assistantMsg = SessionMessage(
            id: _uuid.v4(),
            sessionId: sessionId,
            role: MessageRole.assistant,
            prompt: prompt,
            negativePrompt: negativePrompt,
            imagePaths: imagePaths,
            seed: resultSeed,
            modelName: runModel,
            parameters: {
              ...paramSnapshot,
              'seed': resultSeed,
            },
            createdAt: DateTime.now(),
          );
          await db.insert('session_messages', assistantMsg.toMap());
          targetMessageId = assistantMsg.id;
        }
      } else {
        final assistantMsg = SessionMessage(
          id: _uuid.v4(),
          sessionId: sessionId,
          role: MessageRole.assistant,
          prompt: prompt,
          negativePrompt: negativePrompt,
          imagePaths: imagePaths,
          seed: resultSeed,
          modelName: runModel,
          parameters: {
            ...paramSnapshot,
            'seed': resultSeed,
          },
          createdAt: DateTime.now(),
        );
        await db.insert('session_messages', assistantMsg.toMap());
        targetMessageId = assistantMsg.id;
      }

      // Save generated images
      for (final path in imagePaths) {
        await db.insert('generated_images', {
          'id': _uuid.v4(),
          'session_id': sessionId,
          'message_id': targetMessageId,
          'file_path': path,
          'prompt': prompt,
          'negative_prompt': negativePrompt,
          'model_name': runModel,
          'sampler_name': samplerName,
          'steps': steps,
          'cfg_scale': cfgScale,
          'seed': resultSeed,
          'width': width,
          'height': height,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Count assistant messages for generation_count
      final msgCount = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM session_messages WHERE session_id = ? AND role = 'assistant'",
        [sessionId],
      );
      final genCount = (msgCount.first['c'] as num?)?.toInt() ?? 1;

      // Update session with thumbnail
      await db.update(
        'sessions',
        {
          'thumbnail_path': imagePaths.isNotEmpty ? imagePaths.first : null,
          'generation_count': genCount,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );

      // Mark complete
      state = {
        ...state,
        sessionId: state[sessionId]!.copyWith(
          progress: 1.0,
          isComplete: true,
          clearPreview: true,
        ),
      };

      _ref.invalidate(sessionsProvider);
      _ref.invalidate(galleryImagesProvider);
    } catch (e) {
      _progressTimers[sessionId]?.cancel();
      _refreshStatusAfterNetworkError(e);
      state = {
        ...state,
        sessionId: state[sessionId]!.copyWith(
          hasFailed: true,
          isComplete: true,
          error: e.toString(),
        ),
      };
    }
  }

  Future<void> _startAppleMlGeneration({
    required String sessionId,
    required String prompt,
    required String negativePrompt,
    required String samplerName,
    required int steps,
    required double cfgScale,
    required int width,
    required int height,
    required int seed,
    String? appendToAssistantMessageId,
    bool persistUserMessage = true,
  }) async {
    if (!Platform.isIOS) {
      state = {
        ...state,
        sessionId: GenerationJob(
          sessionId: sessionId,
          prompt: prompt,
          hasFailed: true,
          isComplete: true,
          error: 'On-device Apple ML is available on iOS only',
        ),
      };
      return;
    }

    final modelId = _ref.read(selectedAppleMlModelIdProvider);
    final model = AppleMlCatalog.byId(modelId);
    if (model == null) {
      state = {
        ...state,
        sessionId: GenerationJob(
          sessionId: sessionId,
          prompt: prompt,
          hasFailed: true,
          isComplete: true,
          error: 'Download a Core ML model in Settings → Apple ML',
        ),
      };
      return;
    }
    final downloader = AppleMlDownloader();
    final info = await downloader.installInfo(model);
    if (info == null || !await downloader.isInstalled(model)) {
      state = {
        ...state,
        sessionId: GenerationJob(
          sessionId: sessionId,
          prompt: prompt,
          hasFailed: true,
          isComplete: true,
          error: 'Download ${model.name} before generating on device',
        ),
      };
      return;
    }

    final db = await _ref.read(databaseProvider.future);
    final existing = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    if (existing.isEmpty) {
      final title =
          prompt.length <= 40 ? prompt : '${prompt.substring(0, 40)}...';
      final now = DateTime.now();
      await db.insert(
        'sessions',
        Session(
          id: sessionId,
          title: title,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      _ref.invalidate(sessionsProvider);
    }

    final actualSeed = seed < 0 ? Random().nextInt(0x7fffffff) : seed;
    final paramSnapshot = <String, dynamic>{
      'mode': 'txt2img',
      'provider': GenerationBackend.appleMl.id,
      'model': model.id,
      'sampler_name': 'DPM-Solver++',
      'steps': steps,
      'cfg_scale': cfgScale,
      'width': model.recommendedWidth,
      'height': model.recommendedHeight,
      'seed': actualSeed,
    };

    if (persistUserMessage) {
      final userMsg = SessionMessage(
        id: _uuid.v4(),
        sessionId: sessionId,
        role: MessageRole.user,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: paramSnapshot,
        createdAt: DateTime.now(),
      );
      await db.insert('session_messages', userMsg.toMap());
    }

    state = {
      ...state,
      sessionId: GenerationJob(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: paramSnapshot,
        targetMessageId: appendToAssistantMessageId,
      ),
    };

    StreamSubscription<AppleMlProgress>? sub;
    try {
      sub = AppleMlSdPlugin.progress().listen((event) {
        final job = state[sessionId];
        if (job == null || job.isComplete) return;
        state = {
          ...state,
          sessionId: job.copyWith(
            progress: appleMlFraction(event),
            statusText: event.message,
          ),
        };
      });

      await AppleMlSdPlugin.load(
        resourcesPath: info.resourcesPath,
        variant: model.isSdxl ? 'sdxl' : 'sd15',
      );
      if (state[sessionId]?.hasFailed == true) return;

      final result = await AppleMlSdPlugin.generate(
        prompt: prompt,
        negativePrompt: negativePrompt,
        steps: steps,
        cfgScale: cfgScale,
        seed: actualSeed,
        originalSize: model.recommendedWidth,
      );

      final storedPath = await ImageStorage.savePngFile(
        File(result.path),
        sessionId: sessionId,
      );
      try {
        await File(result.path).delete();
      } catch (_) {}

      await _persistGenerationResult(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        samplerName: 'DPM-Solver++',
        steps: steps,
        cfgScale: cfgScale,
        width: result.width == 0 ? model.recommendedWidth : result.width,
        height: result.height == 0 ? model.recommendedHeight : result.height,
        paramSnapshot: paramSnapshot,
        imagePaths: [storedPath],
        resultSeed: result.seed,
        appendToAssistantMessageId: appendToAssistantMessageId,
        modelName: model.name,
      );
    } on PlatformException catch (e) {
      final message = e.message ?? e.code;
      debugPrint('A1111 AppleML generation failed: $message');
      state = {
        ...state,
        sessionId: state[sessionId]?.copyWith(
              hasFailed: true,
              isComplete: true,
              error: e.message ?? e.code,
            ) ??
            GenerationJob(
              sessionId: sessionId,
              prompt: prompt,
              hasFailed: true,
              isComplete: true,
              error: e.message ?? e.code,
            ),
      };
    } catch (e) {
      state = {
        ...state,
        sessionId: state[sessionId]?.copyWith(
              hasFailed: true,
              isComplete: true,
              error: e.toString(),
            ) ??
            GenerationJob(
              sessionId: sessionId,
              prompt: prompt,
              hasFailed: true,
              isComplete: true,
              error: e.toString(),
            ),
      };
    } finally {
      await sub?.cancel();
    }
  }

  Future<void> _startComfyGeneration({
    required String sessionId,
    required String prompt,
    required String negativePrompt,
    required String samplerName,
    required int steps,
    required double cfgScale,
    required int width,
    required int height,
    required int seed,
    required int batchSize,
    required bool restoreFaces,
    required String mode,
    String? scheduler,
    double? distilledCfgScale,
    List<String> styles = const [],
    List<LoraSelection> loras = const [],
    HiresFixConfig? hires,
    RefinerConfig? refiner,
    List<ControlNetUnit> controlNet = const [],
    String? initImagePath,
    String? maskImagePath,
    double denoisingStrength = 0.75,
    int? clipSkip,
    String? vaeOverride,
    String? appendToAssistantMessageId,
    bool persistUserMessage = true,
    String? checkpointOverride,
    List<ComfyWorkflowField> comfyFields = const [],
  }) async {
    final client = _ref.read(comfyuiClientProvider);
    if (client == null) return;
    var workflowPath = _ref.read(selectedComfyWorkflowProvider);
    if (workflowPath == null || workflowPath.trim().isEmpty) {
      workflowPath = kComfyBuiltinSdWorkflowPath;
    }

    final db = await _ref.read(databaseProvider.future);
    final existing = await db.query('sessions',
        where: 'id = ?', whereArgs: [sessionId]);
    if (existing.isEmpty) {
      final title = prompt.length <= 40 ? prompt : '${prompt.substring(0, 40)}...';
      final now = DateTime.now();
      final session = Session(
        id: sessionId,
        title: title,
        serverId: _ref.read(activeServerProvider)?.id,
        createdAt: now,
        updatedAt: now,
      );
      await db.insert('sessions', session.toMap());
      _ref.invalidate(sessionsProvider);
    }

    final actualSeed = seed < 0 ? Random().nextInt(0x7fffffff) : seed;
    var checkpoint = checkpointOverride ??
        _ref.read(selectedCheckpointOverrideProvider);
    if (checkpoint == null || checkpoint.isEmpty) {
      checkpoint =
          _ref.read(comfyWorkflowDefaultsProvider).asData?.value?.model;
    }
    if ((checkpoint == null || checkpoint.isEmpty) &&
        isComfyBuiltinSdWorkflowPath(workflowPath)) {
      final models = _ref.read(serverModelsProvider).asData?.value;
      if (models != null && models.isNotEmpty) {
        checkpoint = models.first.title;
      }
    }

    final paramSnapshot = <String, dynamic>{
      'mode': mode,
      'provider': GenerationBackend.comfyui.id,
      'workflow': workflowPath,
      'sampler_name': samplerName,
      if (scheduler != null && scheduler.isNotEmpty) 'scheduler': scheduler,
      'steps': steps,
      'cfg_scale': cfgScale,
      'width': width,
      'height': height,
      'seed': actualSeed,
      'restore_faces': restoreFaces,
      'batch_size': batchSize,
      if (checkpoint != null) 'checkpoint': checkpoint,
      if (vaeOverride != null && vaeOverride != 'Automatic') 'vae': vaeOverride,
      if (loras.isNotEmpty)
        'loras': loras
            .map((l) => {'name': l.name, 'weight': l.weight})
            .toList(),
      if (mode != 'txt2img') 'denoising_strength': denoisingStrength,
    };

    if (persistUserMessage) {
      final userMsg = SessionMessage(
        id: _uuid.v4(),
        sessionId: sessionId,
        role: MessageRole.user,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: paramSnapshot,
        createdAt: DateTime.now(),
      );
      await db.insert('session_messages', userMsg.toMap());
    }

    state = {
      ...state,
      sessionId: GenerationJob(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        parameters: paramSnapshot,
        targetMessageId: appendToAssistantMessageId,
        progress: 0.05,
      ),
    };

    try {
      Map<String, dynamic>? objectInfo;
      try {
        objectInfo = await client.objectInfo();
      } catch (_) {}

      final rawWorkflow = isComfyLastRunWorkflowPath(workflowPath)
          ? (_ref.read(comfyLastRunGraphProvider) ??
              await client.getWorkflow(workflowPath))
          : await client.getWorkflow(workflowPath);
      final graph = ComfyWorkflowGraph.fromWorkflow(
        rawWorkflow,
        objectInfo: objectInfo,
      );

      String? uploadedInit;
      if (mode != 'txt2img' && initImagePath != null) {
        final bytes = await File(initImagePath).readAsBytes();
        uploadedInit = await client.uploadImage(
          bytes,
          initImagePath.split('/').last,
        );
      }

      if (isComfyBuiltinSdWorkflowPath(workflowPath) &&
          (checkpoint == null || checkpoint.isEmpty)) {
        throw Exception(
          'No checkpoint found on this ComfyUI server. Open ComfyUI and confirm models are loaded.',
        );
      }

      final graphDefaults = graph.readDefaults();
      final global = _ref.read(generationDefaultsProvider);
      final mergedSteps =
          ComfyUiGraphMerge.pickInt(steps, graphDefaults.steps, global.steps);
      final mergedCfg = ComfyUiGraphMerge.pickDouble(
        cfgScale,
        graphDefaults.cfg,
        global.cfgScale,
      );
      final mergedWidth =
          ComfyUiGraphMerge.pickInt(width, graphDefaults.width, global.width);
      final mergedHeight = ComfyUiGraphMerge.pickInt(
        height,
        graphDefaults.height,
        global.height,
      );
      final mergedSampler = ComfyUiGraphMerge.pickSampler(
        samplerName,
        graphDefaults.sampler,
        global.samplerName,
      );
      final mergedScheduler = ComfyUiGraphMerge.pickScheduler(
        scheduler,
        graphDefaults.scheduler,
        global.scheduler,
      );
      final mergedModel = ComfyUiGraphMerge.pickModel(
        graph: graphDefaults,
        uiCheckpoint: checkpoint,
      );

      graph.applyGenerationOptions(
        prompt: prompt,
        negativePrompt: negativePrompt,
        steps: mergedSteps,
        cfgScale: mergedCfg,
        width: mergedWidth,
        height: mergedHeight,
        seed: actualSeed,
        batchSize: batchSize,
        samplerName: mergedSampler,
        scheduler: mergedScheduler,
        checkpoint: mergedModel,
        vae: vaeOverride,
        denoise: mode == 'txt2img' ? 1.0 : denoisingStrength,
        initImageName: uploadedInit,
      );
      graph.applyFields(comfyFields);
      graph.applyLoras([
        for (final lora in loras)
          if (lora.name.trim().isNotEmpty)
            (name: lora.name, weight: lora.weight),
      ]);

      final queued = await client.queuePrompt(graph.prompt);
      _progressTimers[sessionId]?.cancel();
      _progressTimers[sessionId] = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) async {
          try {
            final queue = await client.queueStatus(promptId: queued.promptId);
            if (state.containsKey(sessionId) && !state[sessionId]!.isComplete) {
              final progress = queue.running
                  ? 0.55
                  : (queue.pending > 0 ? 0.2 : 0.75);
              state = {
                ...state,
                sessionId: state[sessionId]!.copyWith(progress: progress),
              };
            }
          } catch (_) {}
        },
      );

      Map<String, dynamic>? history;
      final timeout = Duration(
        minutes: _ref.read(generationTimeoutMinutesProvider),
      );
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (state[sessionId]?.hasFailed == true) return;
        history = await client.history(queued.promptId);
        if (history != null) break;
      }
      _progressTimers[sessionId]?.cancel();
      if (history == null) {
        throw Exception(
          'ComfyUI timed out after ${formatGenerationTimeout(timeout.inMinutes)} waiting for $workflowPath',
        );
      }

      final images = await client.downloadHistoryImages(history);
      if (images.isEmpty) {
        throw Exception('ComfyUI finished but returned no images');
      }

      final imagePaths = await ImageStorage.saveBase64Images(
        images,
        sessionId: sessionId,
      );
      await _persistGenerationResult(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        samplerName: samplerName,
        steps: steps,
        cfgScale: cfgScale,
        width: width,
        height: height,
        paramSnapshot: paramSnapshot,
        imagePaths: imagePaths,
        resultSeed: seed >= 0 ? seed : null,
        appendToAssistantMessageId: appendToAssistantMessageId,
        modelName: mergedModel,
      );
    } catch (e) {
      _progressTimers[sessionId]?.cancel();
      _refreshStatusAfterNetworkError(e);
      state = {
        ...state,
        sessionId: state[sessionId]?.copyWith(
              hasFailed: true,
              isComplete: true,
              error: e.toString(),
            ) ??
            GenerationJob(
              sessionId: sessionId,
              prompt: prompt,
              hasFailed: true,
              isComplete: true,
              error: e.toString(),
            ),
      };
    }
  }

  Future<void> _persistGenerationResult({
    required String sessionId,
    required String prompt,
    required String negativePrompt,
    required String samplerName,
    required int steps,
    required double cfgScale,
    required int width,
    required int height,
    required Map<String, dynamic> paramSnapshot,
    required List<String> imagePaths,
    int? resultSeed,
    String? appendToAssistantMessageId,
    String? modelName,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    String targetMessageId;
    if (appendToAssistantMessageId != null) {
      final existingRows = await db.query(
        'session_messages',
        where: 'id = ? AND session_id = ? AND role = ?',
        whereArgs: [appendToAssistantMessageId, sessionId, MessageRole.assistant.name],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existing = SessionMessage.fromMap(existingRows.first);
        final mergedPaths = [...existing.imagePaths, ...imagePaths];
        final mergedParams = {
          ...existing.parameters,
          ...paramSnapshot,
          'seed': resultSeed,
          'regeneration_count':
              ((existing.parameters['regeneration_count'] as int?) ?? 0) + 1,
        };
        await db.update(
          'session_messages',
          {
            'image_paths': jsonEncode(mergedPaths),
            'seed': resultSeed,
            'parameters': jsonEncode(mergedParams),
          },
          where: 'id = ?',
          whereArgs: [existing.id],
        );
        targetMessageId = existing.id;
      } else {
        targetMessageId = await _insertAssistantMessage(
          sessionId: sessionId,
          prompt: prompt,
          negativePrompt: negativePrompt,
          imagePaths: imagePaths,
          resultSeed: resultSeed,
          paramSnapshot: paramSnapshot,
          modelName: modelName,
        );
      }
    } else {
      targetMessageId = await _insertAssistantMessage(
        sessionId: sessionId,
        prompt: prompt,
        negativePrompt: negativePrompt,
        imagePaths: imagePaths,
        resultSeed: resultSeed,
        paramSnapshot: paramSnapshot,
        modelName: modelName,
      );
    }

    for (final path in imagePaths) {
      await db.insert('generated_images', {
        'id': _uuid.v4(),
        'session_id': sessionId,
        'message_id': targetMessageId,
        'file_path': path,
        'prompt': prompt,
        'negative_prompt': negativePrompt,
        'model_name': modelName,
        'sampler_name': samplerName,
        'steps': steps,
        'cfg_scale': cfgScale,
        'seed': resultSeed,
        'width': width,
        'height': height,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    final msgCount = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM session_messages WHERE session_id = ? AND role = 'assistant'",
      [sessionId],
    );
    final genCount = (msgCount.first['c'] as num?)?.toInt() ?? 1;
    await db.update(
      'sessions',
      {
        'thumbnail_path': imagePaths.isNotEmpty ? imagePaths.first : null,
        'generation_count': genCount,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    state = {
      ...state,
      sessionId: state[sessionId]!.copyWith(
        progress: 1.0,
        isComplete: true,
        clearPreview: true,
      ),
    };
    _ref.invalidate(sessionsProvider);
    _ref.invalidate(galleryImagesProvider);
  }

  Future<String> _insertAssistantMessage({
    required String sessionId,
    required String prompt,
    required String negativePrompt,
    required List<String> imagePaths,
    required int? resultSeed,
    required Map<String, dynamic> paramSnapshot,
    String? modelName,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final assistantMsg = SessionMessage(
      id: _uuid.v4(),
      sessionId: sessionId,
      role: MessageRole.assistant,
      prompt: prompt,
      negativePrompt: negativePrompt,
      imagePaths: imagePaths,
      seed: resultSeed,
      modelName: modelName,
      parameters: {
        ...paramSnapshot,
        'seed': resultSeed,
      },
      createdAt: DateTime.now(),
    );
    await db.insert('session_messages', assistantMsg.toMap());
    return assistantMsg.id;
  }

  /// A failed request means the cached "Connected" may be stale.
  void _refreshStatusAfterNetworkError(Object e) {
    if (e is DioException || e is SocketException) {
      _ref.invalidate(connectionStatusProvider);
    }
  }

  /// Get the active job for a session (if any).
  GenerationJob? jobForSession(String sessionId) => state[sessionId];

  /// Clear a completed/failed job.
  void clearJob(String sessionId) {
    _progressTimers[sessionId]?.cancel();
    _progressTimers.remove(sessionId);
    final newState = Map<String, GenerationJob>.from(state);
    newState.remove(sessionId);
    state = newState;
  }

  /// Interrupt a running job.
  Future<void> interrupt(String sessionId) async {
    await AppleMlSdPlugin.interrupt();
    final a1111 = _ref.read(a1111ClientProvider);
    final comfy = _ref.read(comfyuiClientProvider);
    await a1111?.interrupt();
    await comfy?.interrupt();
    _progressTimers[sessionId]?.cancel();
    state = {
      ...state,
      sessionId: state[sessionId]!.copyWith(
        hasFailed: true,
        isComplete: true,
        error: 'Interrupted',
      ),
    };
  }

  @override
  void dispose() {
    for (final timer in _progressTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

final generationServiceProvider =
    StateNotifierProvider<GenerationServiceNotifier, Map<String, GenerationJob>>((ref) {
  return GenerationServiceNotifier(ref);
});

/// User toggle: stream live preview frames from /sdapi/v1/progress.
final livePreviewEnabledProvider = StateProvider<bool>((_) => true);

/// Convenience: watch the job for a specific session.
final sessionGenerationProvider =
    Provider.family<GenerationJob?, String>((ref, sessionId) {
  final jobs = ref.watch(generationServiceProvider);
  return jobs[sessionId];
});
