import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/api/generation_options.dart';
import '../../../core/api/comfyui_workflow.dart';
import '../../../core/api/api_models.dart';
import '../../../core/models/generation_backend.dart';
import '../../../core/on_device/apple_ml_models.dart';
import '../../../core/on_device/apple_ml_providers.dart';
import '../../../core/on_device/on_device_looks.dart';
import '../../../core/models/persona.dart';
import '../../../core/models/session.dart';
import '../../../core/premium/premium.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/image_storage.dart';
import '../../../core/providers/generation_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/platform_icon.dart';
import '../../generation/presentation/comfy_workflow_dropdown.dart';
import '../../gallery/presentation/gallery_screen.dart';
import '../../profiles/presentation/profiles_screen.dart';
import '../../personas/presentation/personas_screen.dart';
import 'image_viewer_screen.dart';
import 'session_chat_extras.dart';


const _uuid = Uuid();

class SessionChatScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final bool embeddedInSplit;

  const SessionChatScreen({
    super.key,
    required this.sessionId,
    this.embeddedInSplit = false,
  });

  @override
  ConsumerState<SessionChatScreen> createState() => _SessionChatScreenState();
}

class _SessionChatScreenState extends ConsumerState<SessionChatScreen> {
  final _promptController = TextEditingController();
  final _negativePromptController = TextEditingController();
  final _scrollController = ScrollController();
  final _seedController = TextEditingController(text: '-1');

  List<SessionMessage> _messages = [];
  Session? _session;
  bool _isPersistedToDB = false;
  bool _showParams = false;

  // Generation parameters — initialized from global defaults
  String _samplerName = 'Euler a';
  String? _scheduler;
  int _steps = 20;
  double _cfgScale = 7.0;
  double _distilledCfg = 3.5;
  int _width = 512;
  int _height = 512;
  bool _restoreFaces = false;
  int _batchSize = 1;
  int? _clipSkip;
  String _vae = 'Automatic';
  bool _loadedDefaults = false;
  // Bumped to reset the checkpoint dropdown after a failed switch.
  int _checkpointPickerResets = 0;
  String? _selectedProfileId;
  String? _selectedPersonaId;
  String? _appliedComfyWorkflowPath;
  List<ComfyWorkflowField> _comfyFields = const [];

  // Phase 4 features
  List<String> _styles = [];
  List<LoraSelection> _loras = [];
  HiresFixConfig _hires = const HiresFixConfig();
  RefinerConfig _refiner = const RefinerConfig();
  List<ControlNetUnit> _controlNet = [];

  // img2img / inpaint state
  String _mode = 'txt2img'; // 'txt2img' | 'img2img' | 'inpaint'
  String? _initImagePath;
  double _denoisingStrength = 0.75;

  Future<void> _saveParamsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final p = {
      'sampler_name': _samplerName,
      if (_scheduler != null) 'scheduler': _scheduler,
      'steps': _steps,
      'cfg_scale': _cfgScale,
      'distilled_cfg_scale': _distilledCfg,
      'width': _width,
      'height': _height,
      'seed': int.tryParse(_seedController.text) ?? -1,
      'negative_prompt': _negativePromptController.text,
      'restore_faces': _restoreFaces,
      'batch_size': _batchSize,
      'vae': _vae,
      'mode': _mode,
      'denoising_strength': _denoisingStrength,
      'styles': _styles,
      'loras': _loras.map((l) => {'name': l.name, 'weight': l.weight}).toList(),
    };
    await prefs.setString('session_${widget.sessionId}_params', jsonEncode(p));
  }

  Future<void> _loadParamsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('session_${widget.sessionId}_params');
    if (str == null) return;
    try {
      final p = jsonDecode(str) as Map<String, dynamic>;
      if (p.containsKey('sampler_name')) _samplerName = p['sampler_name'];
      if (p.containsKey('scheduler')) _scheduler = p['scheduler'];
      if (p.containsKey('steps')) _steps = p['steps'] as int;
      if (p.containsKey('cfg_scale')) _cfgScale = (p['cfg_scale'] as num).toDouble();
      if (p.containsKey('distilled_cfg_scale')) _distilledCfg = (p['distilled_cfg_scale'] as num).toDouble();
      if (p.containsKey('width')) _width = p['width'] as int;
      if (p.containsKey('height')) _height = p['height'] as int;
      if (p.containsKey('seed')) {
        final rawSeed = p['seed'] as int;
        _seedController.text = rawSeed.toString();
      }
      if (p.containsKey('negative_prompt')) {
        _negativePromptController.text = p['negative_prompt'] as String;
      }
      if (p.containsKey('restore_faces')) _restoreFaces = p['restore_faces'] as bool;
      if (p.containsKey('batch_size')) _batchSize = p['batch_size'] as int;
      if (p.containsKey('vae')) _vae = p['vae'] as String;
      if (p.containsKey('mode')) _mode = p['mode'] as String;
      if (p.containsKey('denoising_strength')) _denoisingStrength = (p['denoising_strength'] as num).toDouble();
      if (p.containsKey('styles')) {
        _styles = (p['styles'] as List).cast<String>();
      }
      if (p.containsKey('loras')) {
        final loraList = p['loras'] as List;
        _loras = loraList.map((e) => LoraSelection(
          name: e['name'] as String,
          weight: (e['weight'] as num).toDouble(),
        )).toList();
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadOrCreateSession();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _scrollController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _loadOrCreateSession() async {
    // Load global defaults for new sessions (only once)
    if (!_loadedDefaults) {
      final defaults = ref.read(generationDefaultsProvider);
      _samplerName = defaults.samplerName;
      _scheduler = defaults.scheduler;
      _steps = defaults.steps;
      _cfgScale = defaults.cfgScale;
      _distilledCfg = defaults.distilledCfgScale;
      _width = defaults.width;
      _height = defaults.height;
      _restoreFaces = defaults.restoreFaces;
      _batchSize = defaults.batchSize;
      _vae = defaults.vae;
      _styles = List.of(defaults.promptStyles);
      _hires = HiresFixConfig(
        enabled: defaults.hiresEnabled,
        scale: defaults.hiresScale,
        steps: defaults.hiresSteps,
        denoisingStrength: defaults.hiresDenoising,
        upscaler: defaults.hiresUpscaler,
      );
      _refiner = RefinerConfig(
        checkpoint: defaults.refinerCheckpoint,
        switchAt: defaults.refinerSwitchAt,
      );
      _loadedDefaults = true;
    }

    final db = await ref.read(databaseProvider.future);

    // Try to load existing session
    final results = await db.query('sessions',
        where: 'id = ?', whereArgs: [widget.sessionId]);

    if (results.isEmpty &&
        ref.read(activeProviderProvider) == GenerationBackend.appleMl) {
      final model =
          AppleMlCatalog.byId(ref.read(selectedAppleMlModelIdProvider));
      if (model != null && mounted) {
        setState(() {
          _assignOnDeviceLook(onDeviceLooks.first);
          if (!model.isSdxl) {
            _width = model.recommendedWidth;
            _height = model.recommendedHeight;
            _steps = model.recommendedSteps;
            _cfgScale = model.recommendedCfg;
          }
        });
      }
    }

    if (results.isNotEmpty) {
      _session = Session.fromMap(results.first);
      _isPersistedToDB = true;
      
      await _loadParamsFromPrefs();

      // Fallback: If no prefs saved yet, Load last used settings from DB
      final lastUserMsg = await db.query(
        'session_messages',
        where: 'session_id = ? AND role = ?',
        whereArgs: [widget.sessionId, 'user'],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (lastUserMsg.isNotEmpty) {
        try {
          final msg = SessionMessage.fromMap(lastUserMsg.first);
          final p = msg.parameters;
          if (p.containsKey('sampler_name')) _samplerName = p['sampler_name'];
          if (p.containsKey('scheduler')) _scheduler = p['scheduler'];
          if (p.containsKey('steps')) _steps = (p['steps'] as num).toInt();
          if (p.containsKey('cfg_scale')) _cfgScale = (p['cfg_scale'] as num).toDouble();
          if (p.containsKey('distilled_cfg_scale')) _distilledCfg = (p['distilled_cfg_scale'] as num).toDouble();
          if (p.containsKey('width')) _width = (p['width'] as num).toInt();
          if (p.containsKey('height')) _height = (p['height'] as num).toInt();
          if (p.containsKey('seed')) _seedController.text = (p['seed'] as num?)?.toInt().toString() ?? '-1';
          if (p.containsKey('restore_faces')) _restoreFaces = p['restore_faces'] as bool;
          if (p.containsKey('batch_size')) _batchSize = (p['batch_size'] as num).toInt();
          if (p.containsKey('mode')) _mode = p['mode'] as String;
          if (p.containsKey('denoising_strength')) _denoisingStrength = (p['denoising_strength'] as num).toDouble();
          if (p.containsKey('styles')) {
            _styles = (p['styles'] as List).map((s) => s.toString()).toList();
          } else {
            _styles = [];
          }
          if (p.containsKey('loras')) {
            // parse loras
            final loraList = p['loras'] as List;
            _loras = loraList.map((e) {
              final emap = e as Map<String, dynamic>;
              return LoraSelection(
                name: emap['name'] as String,
                weight: (emap['weight'] as num).toDouble(),
              );
            }).toList();
          } else {
            _loras = [];
          }
        } catch (_) {
          // Ignore parsing errors for fallback params
        }
      }
    } else {
      // Create new session in memory only - will persist on first generation
      final now = DateTime.now();
      _session = Session(
        id: widget.sessionId,
        title: 'New Session',
        serverId: ref.read(activeServerProvider)?.id,
        createdAt: now,
        updatedAt: now,
      );
      _isPersistedToDB = false;

      // Even for new unpersisted sessions, try loading if they changed settings and restarted
      await _loadParamsFromPrefs();
    }

    // Load messages
    final msgs = await db.query('session_messages',
        where: 'session_id = ?',
        whereArgs: [widget.sessionId],
        orderBy: 'created_at ASC');
    setState(() {
      _messages = msgs.map((e) => SessionMessage.fromMap(e)).toList();
    });

    _scrollToBottom();

    if (ref.read(activeProviderProvider) == GenerationBackend.comfyui) {
      _appliedComfyWorkflowPath = null;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Reload messages from DB (after background generation completes).
  Future<void> _reloadMessages() async {
    final db = await ref.read(databaseProvider.future);
    final msgs = await db.query('session_messages',
        where: 'session_id = ?',
        whereArgs: [widget.sessionId],
        orderBy: 'created_at ASC');
    if (mounted) {
      setState(() {
        _messages = msgs.map((e) => SessionMessage.fromMap(e)).toList();
      });
      _scrollToBottom();
    }
    // Also reload session metadata (title / thumbnail may have changed)
    final results = await db.query('sessions',
        where: 'id = ?', whereArgs: [widget.sessionId]);
    if (results.isNotEmpty && mounted) {
      setState(() {
        _session = Session.fromMap(results.first);
      });
    }
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    var styledPrompt = prompt;
    var negative = _negativePromptController.text.trim();
    if (_selectedProfileId != null) {
      final profile = ref
          .read(profilesProvider)
          .valueOrNull
          ?.where((item) => item.id == _selectedProfileId)
          .firstOrNull;
      final look = onDeviceLooks
          .where((item) => item.profileId == _selectedProfileId)
          .firstOrNull;
      final positive = profile?.positivePrompt ?? look?.positivePrompt ?? '';
      final negativeStyle =
          profile?.negativePrompt ?? look?.negativePrompt ?? '';
      if (positive.isNotEmpty && !styledPrompt.contains(positive)) {
        styledPrompt = '$styledPrompt, $positive';
      }
      if (negative.isEmpty) negative = negativeStyle;
    }

    final backend = ref.read(activeProviderProvider);
    if (backend.requiresRemoteServer &&
        ref.read(activeServerProvider) == null) {
      _showError('No server connected. Go to Servers to add one.');
      return;
    }
    if (backend == GenerationBackend.appleMl &&
        AppleMlCatalog.byId(ref.read(selectedAppleMlModelIdProvider)) ==
            null) {
      _showError(
        'Download a Core ML model in Settings to generate on device.',
      );
      return;
    }

    final seed = int.tryParse(_seedController.text) ?? -1;

    // Clear input immediately
    _promptController.clear();

    // Add user message to local list for immediate UI feedback
    final userMsg = SessionMessage(
      id: _uuid.v4(),
      sessionId: widget.sessionId,
      role: MessageRole.user,
      prompt: styledPrompt,
      negativePrompt: negative,
      parameters: {
        'mode': _mode,
        'sampler_name': _samplerName,
        if (_scheduler != null) 'scheduler': _scheduler,
        'steps': _steps,
        'cfg_scale': _cfgScale,
        if (_distilledCfg != 0) 'distilled_cfg_scale': _distilledCfg,
        'width': _width,
        'height': _height,
        'seed': seed,
        'restore_faces': _restoreFaces,
        'batch_size': _batchSize,
        if (_styles.isNotEmpty) 'styles': _styles,
        if (_loras.isNotEmpty)
          'loras': _loras.map((l) => {'name': l.name, 'weight': l.weight}).toList(),
        if (_mode != 'txt2img') 'denoising_strength': _denoisingStrength,
      },
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      if (!_isPersistedToDB) {
        _session = _session?.copyWith(title: _truncateTitle(prompt));
        _isPersistedToDB = true;
      }
    });
    _scrollToBottom();

    // Delegate to background generation service
    ref.read(generationServiceProvider.notifier).startGeneration(
          sessionId: widget.sessionId,
          prompt: styledPrompt,
          negativePrompt: negative,
          checkpointOverride: ref.read(selectedCheckpointOverrideProvider),
          samplerName: _samplerName,
          scheduler: _scheduler,
          steps: _steps,
          cfgScale: _cfgScale,
          distilledCfgScale: _distilledCfg,
          width: _width,
          height: _height,
          seed: seed,
          batchSize: _batchSize,
          restoreFaces: _restoreFaces,
          mode: _mode,
          styles: _styles,
          loras: _loras,
          hires: _hires.enabled ? _hires : null,
          refiner: _refiner.checkpoint != null ? _refiner : null,
          controlNet: _controlNet,
          initImagePath: _initImagePath,
          denoisingStrength: _denoisingStrength,
          clipSkip: _clipSkip,
          vaeOverride: _vae,
          comfyFields: _comfyFields,
        );

    // Save final generated params
    await _saveParamsToPrefs();
  }

  String _truncateTitle(String prompt) {
    if (prompt.length <= 40) return prompt;
    return '${prompt.substring(0, 40)}...';
  }

  Future<void> _regenerate(SessionMessage msg) async {
    final backend = ref.read(activeProviderProvider);
    if (backend.requiresRemoteServer &&
        ref.read(activeServerProvider) == null) {
      _showError('No server connected. Go to Servers to add one.');
      return;
    }
    if (backend == GenerationBackend.appleMl &&
        AppleMlCatalog.byId(ref.read(selectedAppleMlModelIdProvider)) ==
            null) {
      _showError(
        'Download a Core ML model in Settings to generate on device.',
      );
      return;
    }

    // Re-use prompt and generation params from the original assistant message.
    final p = msg.parameters;
    final prompt = msg.prompt;
    final negativePrompt = msg.negativePrompt;
    final seed = int.tryParse(_seedController.text) ?? -1;

    await ref.read(generationServiceProvider.notifier).startGeneration(
          sessionId: widget.sessionId,
          prompt: prompt,
          negativePrompt: negativePrompt,
          checkpointOverride: p['checkpoint'] as String? ??
              ref.read(selectedCheckpointOverrideProvider),
          samplerName: p['sampler_name'] as String? ?? _samplerName,
          scheduler: p['scheduler'] as String?,
          steps: p['steps'] as int? ?? _steps,
          cfgScale: (p['cfg_scale'] as num?)?.toDouble() ?? _cfgScale,
          distilledCfgScale:
              (p['distilled_cfg_scale'] as num?)?.toDouble() ?? _distilledCfg,
          width: p['width'] as int? ?? _width,
          height: p['height'] as int? ?? _height,
          seed: p['seed'] as int? ?? seed,
          batchSize: p['batch_size'] as int? ?? _batchSize,
          restoreFaces: p['restore_faces'] as bool? ?? _restoreFaces,
          mode: p['mode'] as String? ?? 'txt2img',
          denoisingStrength:
              (p['denoising_strength'] as num?)?.toDouble() ?? _denoisingStrength,
          styles: ((p['styles'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
          loras: ((p['loras'] as List?) ?? const [])
              .map((e) => LoraSelection(
                    name: (e as Map<String, dynamic>)['name']?.toString() ?? '',
                    weight: ((e)['weight'] as num?)?.toDouble() ?? 1.0,
                  ))
              .where((l) => l.name.isNotEmpty)
              .toList(),
          hires: p['hires'] is Map<String, dynamic>
              ? HiresFixConfig(
                  enabled: true,
                  scale: ((p['hires'] as Map<String, dynamic>)['scale'] as num?)
                          ?.toDouble() ??
                      1.5,
                  steps: ((p['hires'] as Map<String, dynamic>)['steps'] as num?)
                          ?.toInt() ??
                      0,
                  denoisingStrength:
                      ((p['hires'] as Map<String, dynamic>)['denoising_strength']
                                  as num?)
                              ?.toDouble() ??
                          0.5,
                  upscaler: (p['hires'] as Map<String, dynamic>)['upscaler']
                          ?.toString() ??
                      'Latent',
                )
              : (_hires.enabled ? _hires : null),
          controlNet: const [],
          initImagePath: _initImagePath,
          clipSkip: p['clip_skip'] as int? ?? _clipSkip,
          vaeOverride: p['vae'] as String? ?? _vae,
          appendToAssistantMessageId: msg.id,
          persistUserMessage: false,
          comfyFields: _comfyFields,
        );
  }

  void _assignOnDeviceLook(OnDeviceLook look) {
    _selectedPersonaId = look.personaId;
    _selectedProfileId = look.profileId;
    _steps = look.steps;
    _cfgScale = look.cfg;
    _width = look.width;
    _height = look.height;
    _samplerName = look.sampler;
    final currentNegative = _negativePromptController.text.trim();
    final replacingLook = onDeviceLooks.any(
      (item) => item.negativePrompt == currentNegative,
    );
    if (currentNegative.isEmpty || replacingLook) {
      _negativePromptController.text = look.negativePrompt;
    }
  }

  Future<void> _applyPersona(Persona persona) async {
    _samplerName = persona.samplerName;
    _scheduler = persona.scheduler;
    _steps = persona.steps;
    _cfgScale = persona.cfgScale;
    _distilledCfg = persona.distilledCfgScale;
    _width = persona.width;
    _height = persona.height;
    _restoreFaces = persona.restoreFaces;
    _clipSkip = persona.clipSkip;
    _vae = persona.vae;
    _styles = List.of(persona.styleNames);
    _loras = persona.loraConfigs
        .map((l) => LoraSelection(name: l.name, weight: l.weight))
        .toList();
    _hires = HiresFixConfig(
      enabled: persona.hiresFix,
      scale: persona.hiresScale,
      steps: persona.hiresSteps,
      denoisingStrength: persona.hiresDenoising,
      upscaler: persona.hiresUpscaler,
    );
    _controlNet = persona.controlNetUnits;
    _selectedProfileId = persona.profileId;
    if (persona.profileId != null) {
      final profile = ref
          .read(profilesProvider)
          .valueOrNull
          ?.where((item) => item.id == persona.profileId)
          .firstOrNull;
      if (profile != null && _negativePromptController.text.trim().isEmpty) {
        _negativePromptController.text = profile.negativePrompt;
      }
    }

    if (persona.modelName != null && persona.modelName!.isNotEmpty) {
      final client = ref.read(a1111ClientProvider);
      if (client != null) {
        try {
          await client.setModel(persona.modelName!);
          ref.invalidate(connectionStatusProvider);
        } catch (e) {
          if (mounted) {
            _showError('Could not apply profile model: $e');
          }
        }
      }
    }
  }

  Future<void> _copyImage(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _showError('Image file not found');
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image path copied to clipboard')),
      );
    }
  }

  Future<void> _deleteMessage(SessionMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Generation'),
        content: const Text('Delete this generation and its images?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final db = await ref.read(databaseProvider.future);
    for (final path in msg.imagePaths) {
      final file = ImageStorage.resolveFileSync(path);
      PaintingBinding.instance.imageCache.evict(FileImage(file));
      await ImageStorage.deleteImage(path);
    }
    await db.delete('generated_images',
        where: 'message_id = ?', whereArgs: [msg.id]);
    await db.delete('session_messages',
        where: 'id = ?', whereArgs: [msg.id]);

    final latest = await db.query(
      'generated_images',
      columns: ['file_path'],
      where: 'session_id = ?',
      whereArgs: [msg.sessionId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    final nextThumb =
        latest.isEmpty ? null : latest.first['file_path'] as String?;
    final countRows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM session_messages WHERE session_id = ? AND role = 'assistant'",
      [msg.sessionId],
    );
    final genCount = (countRows.first['c'] as num?)?.toInt() ?? 0;
    await db.update(
      'sessions',
      {
        'thumbnail_path': nextThumb,
        'generation_count': genCount,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [msg.sessionId],
    );

    setState(() => _messages.removeWhere((m) => m.id == msg.id));
    ref.invalidate(galleryImagesProvider);
    ref.invalidate(sessionsProvider);
  }

  Future<void> _editUserMessage(SessionMessage msg) async {
    _promptController.text = msg.prompt;
    _negativePromptController.text = msg.negativePrompt;
    if (msg.parameters.isNotEmpty) {
      _samplerName = msg.parameters['sampler_name'] as String? ?? _samplerName;
      _steps = msg.parameters['steps'] as int? ?? _steps;
      _cfgScale = (msg.parameters['cfg_scale'] as num?)?.toDouble() ?? _cfgScale;
      _width = msg.parameters['width'] as int? ?? _width;
      _height = msg.parameters['height'] as int? ?? _height;
    }
    setState(() {});
  }

  Future<void> _deleteUserMessage(SessionMessage msg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Prompt'),
        content: const Text('Delete this prompt message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final db = await ref.read(databaseProvider.future);
    await db.delete('session_messages', where: 'id = ?', whereArgs: [msg.id]);
    setState(() => _messages.removeWhere((m) => m.id == msg.id));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _applyComfyWorkflowDefaults(
    ComfyWorkflowDefaults defaults,
    String path,
  ) {
    if (!mounted) return;
    setState(() {
      if (defaults.sampler != null && defaults.sampler!.isNotEmpty) {
        _samplerName = defaults.sampler!;
      }
      if (defaults.scheduler != null && defaults.scheduler!.isNotEmpty) {
        _scheduler = defaults.scheduler;
      } else {
        _scheduler = null;
      }
      if (defaults.steps != null) _steps = defaults.steps!;
      if (defaults.cfg != null) _cfgScale = defaults.cfg!;
      if (defaults.width != null) _width = defaults.width!;
      if (defaults.height != null) _height = defaults.height!;
      if (defaults.batchSize != null) _batchSize = defaults.batchSize!;
      if (defaults.seed != null) {
        _seedController.text = '${defaults.seed}';
      }
      if (defaults.vae != null && defaults.vae!.isNotEmpty) {
        _vae = defaults.vae!;
      } else {
        _vae = 'Automatic';
      }
      if (defaults.denoise != null) {
        _denoisingStrength = defaults.denoise!;
      }
      if (defaults.negativePrompt != null) {
        _negativePromptController.text = defaults.negativePrompt!;
      }
      _loras = [
        for (final lora in defaults.loras)
          LoraSelection(name: lora.name, weight: lora.weight),
      ];
      _comfyFields = defaults.fields;
      _appliedComfyWorkflowPath = path;
    });
    ref.read(selectedCheckpointOverrideProvider.notifier).state = defaults.model;
    _saveParamsToPrefs();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final hideBackButton = widget.embeddedInSplit && isLandscape;
    final hasGenerationTarget = hasUsableGenerationTargetFor(
      ref.watch(activeProviderProvider),
      ref.watch(activeServerProvider),
      ref.watch(selectedAppleMlModelIdProvider),
    );

    // Watch background generation for this session
    final genJob = ref.watch(sessionGenerationProvider(widget.sessionId));
    final isGenerating = genJob != null && !genJob.isComplete;
    final progress = genJob?.progress ?? 0.0;

    // When generation completes, reload messages from DB
    ref.listen<GenerationJob?>(sessionGenerationProvider(widget.sessionId), (prev, next) {
      if (next != null && next.isComplete && (prev == null || !prev.isComplete)) {
        _reloadMessages();
        if (next.hasFailed && next.error != null) {
          _showError('Generation failed: ${next.error}');
        }
        // Clear the job after handling
        Future.microtask(() {
          ref.read(generationServiceProvider.notifier).clearJob(widget.sessionId);
        });
      }
    });

    ref.listen<String?>(selectedComfyWorkflowProvider, (prev, next) {
      if (prev != next) _appliedComfyWorkflowPath = null;
    });
    ref.listen<AsyncValue<ComfyWorkflowDefaults?>>(
      comfyWorkflowDefaultsProvider,
      (prev, next) {
        final defaults = next.asData?.value;
        if (defaults == null) return;
        if (ref.read(activeProviderProvider) != GenerationBackend.comfyui) {
          return;
        }
        final path = ref.read(selectedComfyWorkflowProvider);
        if (path == null || path.trim().isEmpty) return;
        if (_appliedComfyWorkflowPath == path) return;
        _applyComfyWorkflowDefaults(defaults, path);
      },
    );

    final comfyDefaults = ref.watch(comfyWorkflowDefaultsProvider).asData?.value;
    final comfyPath = ref.watch(selectedComfyWorkflowProvider);
    if (comfyDefaults != null &&
        comfyPath != null &&
        comfyPath.trim().isNotEmpty &&
        _appliedComfyWorkflowPath != comfyPath &&
        ref.read(activeProviderProvider) == GenerationBackend.comfyui) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_appliedComfyWorkflowPath == comfyPath) return;
        _applyComfyWorkflowDefaults(comfyDefaults, comfyPath);
      });
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        title: Text(_session?.title ?? 'New Session'),
        leading: hideBackButton
            ? null
            : IconButton(
                icon: const PlatformIcon(
                  material: Icons.arrow_back,
                  cupertino: CupertinoIcons.back,
                ),
                onPressed: () {
                  if (widget.embeddedInSplit) {
                    ref.read(landscapeDetailSessionProvider.notifier).state = null;
                    return;
                  }
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/sessions');
                  }
                },
              ),
        actions: [
          if (!widget.embeddedInSplit)
            IconButton(
              icon: const PlatformIcon(
                material: Icons.settings_outlined,
                cupertino: CupertinoIcons.settings,
                size: 22,
              ),
              onPressed: _showPerChatSettings,
            ),
          if (isGenerating)
            IconButton(
              icon: const PlatformIcon(
                material: Icons.stop_circle_outlined,
                cupertino: CupertinoIcons.stop_circle,
                color: AppColors.error,
              ),
              onPressed: () {
                ref.read(generationServiceProvider.notifier).interrupt(widget.sessionId);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (_showParams) setState(() => _showParams = false);
              },
              child: _messages.isEmpty && !isGenerating
                ? (!hasGenerationTarget ? _NoServerView() : _WelcomeView())
                : Builder(builder: (_) {
                    // Skip the trailing placeholder when this generation is
                    // a regenerate — progress is shown inside the original bubble.
                    final showTrailingPlaceholder = isGenerating &&
                        (genJob.targetMessageId == null);
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(GlassTokens.spacingLg),
                      itemCount:
                          _messages.length + (showTrailingPlaceholder ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length &&
                            showTrailingPlaceholder) {
                          return _GeneratingPlaceholder(
                            progress: progress,
                            width: _width,
                            height: _height,
                            batchSize: _batchSize,
                            previewBase64: genJob.previewImageBase64,
                            etaRelative: genJob.etaRelative,
                            statusText: genJob.statusText,
                            loadingModel: ref.watch(activeProviderProvider) ==
                                    GenerationBackend.appleMl &&
                                _isModelLoadStatus(genJob.statusText),
                          );
                        }
                        final msg = _messages[index];
                        final regenJob = (isGenerating &&
                                genJob.targetMessageId == msg.id)
                            ? genJob
                            : null;
                        return _MessageBubble(
                          message: msg,
                          showNerdStats: ref
                              .watch(generationDefaultsProvider)
                              .showNerdStats,
                          regenerationJob: regenJob,
                          onRegenerate: msg.role == MessageRole.assistant
                              ? () => _regenerate(msg)
                              : null,
                          onCopyImage: msg.role == MessageRole.assistant &&
                                  msg.imagePaths.isNotEmpty
                              ? () => _copyImage(msg.imagePaths.first)
                              : null,
                          onDelete: msg.role == MessageRole.assistant
                              ? () => _deleteMessage(msg)
                              : null,
                          onEditUser: msg.role == MessageRole.user
                              ? () => _editUserMessage(msg)
                              : null,
                          onDeleteUser: msg.role == MessageRole.user
                              ? () => _deleteUserMessage(msg)
                              : null,
                        );
                      },
                    );
                  }),
            ),
          ),
          // Parameter panel (swipe down to dismiss)
          if (_showParams)
            _DismissibleParamsPanel(
              onDismiss: () => setState(() => _showParams = false),
              child: _buildParamsPanel(),
            ),
          // Input area
          _buildInputArea(isDark),
        ],
      ),
    );
  }

  Widget _buildOnDeviceLookFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Look', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: onDeviceLooks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final look = onDeviceLooks[index];
              final selected = _selectedPersonaId == look.personaId;
              return FilterChip(
                label: Text(look.label, style: const TextStyle(fontSize: 12)),
                selected: selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() {
                    if (selected) {
                      _selectedPersonaId = null;
                      if (_selectedProfileId == look.profileId) {
                        _selectedProfileId = null;
                      }
                    } else {
                      _assignOnDeviceLook(look);
                    }
                  });
                  _saveParamsToPrefs();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea(bool isDark) {
    final genJob = ref.watch(sessionGenerationProvider(widget.sessionId));
    final isGenerating = genJob != null && !genJob.isComplete;
    final hasGenerationTarget = hasUsableGenerationTargetFor(
      ref.watch(activeProviderProvider),
      ref.watch(activeServerProvider),
      ref.watch(selectedAppleMlModelIdProvider),
    );
    final canInput = hasGenerationTarget && !isGenerating;
    final backend = ref.watch(activeProviderProvider);
    final isComfy = backend == GenerationBackend.comfyui;
    final isAppleMl = backend == GenerationBackend.appleMl;

    return Container(
      padding: EdgeInsets.fromLTRB(
        GlassTokens.spacingLg,
        GlassTokens.spacingSm,
        GlassTokens.spacingLg,
        MediaQuery.of(context).padding.bottom + GlassTokens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAppleMl) ...[
            _buildOnDeviceLookFilters(),
            const SizedBox(height: 6),
          ],
          // Mode + img2img preview strip
          if (_initImagePath != null || _mode != 'txt2img')
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  if (_initImagePath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(_initImagePath!),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _mode.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: context.accentText,
                      ),
                    ),
                  ),
                  if (_mode != 'txt2img') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          const Text('Denoise',
                              style: TextStyle(fontSize: 11)),
                          Expanded(
                            child: Slider(
                              value: _denoisingStrength,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              label: _denoisingStrength.toStringAsFixed(2),
                              onChanged: (v) => setState(
                                  () => _denoisingStrength = v),
                            ),
                          ),
                          SizedBox(
                              width: 32,
                              child: Text(
                                  _denoisingStrength.toStringAsFixed(2),
                                  style:
                                      const TextStyle(fontSize: 11))),
                        ],
                      ),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark_circle, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _initImagePath = null;
                      _mode = 'txt2img';
                    }),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Toggle params
              IconButton(
                icon: PlatformIcon(
                  material: _showParams ? Icons.tune : Icons.tune_outlined,
                  cupertino: CupertinoIcons.slider_horizontal_3,
                  color: _showParams ? context.accentText : null,
                ),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _showParams = !_showParams);
                },
                tooltip: 'Generation settings',
              ),
              if (kShowLockedFeatures ||
                  ref.watch(hasFeatureProvider(PremiumFeature.imageInput)))
                IconButton(
                  icon: const PlatformIcon(
                    material: Icons.add_photo_alternate_outlined,
                    cupertino: CupertinoIcons.photo_on_rectangle,
                  ),
                  tooltip: 'Use as init (img2img)',
                  onPressed: _pickInitImage,
                ),
              if (!isComfy)
                IconButton(
                  icon: const PlatformIcon(
                    material: Icons.content_paste_search,
                    cupertino: CupertinoIcons.doc_on_clipboard,
                  ),
                  tooltip: 'Import generation info',
                  onPressed: _importPngInfo,
                ),
              // Prompt input
              Expanded(
                child: TextField(
                  controller: _promptController,
                  enabled: canInput,
                  maxLines: 4,
                  minLines: 1,
                  onTap: () {
                    if (_showParams) setState(() => _showParams = false);
                  },
                  decoration: InputDecoration(
                    hintText: hasGenerationTarget ? 'Describe your image...' : 'Connect to a server first',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(GlassTokens.radiusLg),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor:
                        isDark ? AppColors.cardDark : AppColors.cardLight,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 8),
              // Send
              Container(
                decoration: BoxDecoration(
                  color: canInput ? AppColors.primary : Colors.grey,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const PlatformIcon(
                    material: Icons.arrow_upward,
                    cupertino: CupertinoIcons.arrow_up,
                    color: Colors.white,
                  ),
                  onPressed: !canInput ? null : _generate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickInitImage() async {
    if (!await requireFeature(context, ref, PremiumFeature.imageInput)) {
      return;
    }
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return;
      setState(() {
        _initImagePath = picked.path;
        _mode = 'img2img';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Photo picker unavailable: ${e.message ?? e.code}. Do a full app restart after plugin changes.',
          ),
        ),
      );
    }
  }

  void _showPerChatSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: GlassTokens.spacingLg,
            right: GlassTokens.spacingLg,
            top: GlassTokens.spacingLg,
          ),
          child: Consumer(
            builder: (ctx, sheetRef, _) {
              return StatefulBuilder(
                builder: (BuildContext stCtx, StateSetter setModalState) {
                  final backend = sheetRef.watch(activeProviderProvider);
                  final isComfy = backend == GenerationBackend.comfyui;
                  final isAppleMl = backend == GenerationBackend.appleMl;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Session Settings',
                              style: Theme.of(context).textTheme.titleLarge),
                          IconButton(
                            icon: const Icon(CupertinoIcons.xmark_circle),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: GlassTokens.spacingMd),
                      if (isComfy) ...[
                        const ComfyWorkflowDropdown(),
                        const SizedBox(height: GlassTokens.spacingMd),
                      ],
                      if (isAppleMl) ...[
                        _buildAppleMlModelRow(setModalState),
                        const SizedBox(height: GlassTokens.spacingMd),
                        TextField(
                          controller: _seedController,
                          decoration: const InputDecoration(
                            labelText: 'Seed',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ] else ...[
                        _buildModelVaeRow(setModalState),
                        const SizedBox(height: GlassTokens.spacingMd),
                        _buildSamplerSeedRow(setModalState),
                        const SizedBox(height: GlassTokens.spacingMd),
                        _buildSchedulerRow(setModalState),
                        const SizedBox(height: GlassTokens.spacingMd),
                        _buildComfyWorkflowFields(setModalState),
                      ],
                      const SizedBox(height: GlassTokens.spacingLg * 2),
                    ],
                  );
                }
              );
            },
          ),
        ),
      ),
    ).whenComplete(() => _saveParamsToPrefs());
  }

  Future<void> _importPngInfo() async {
    final result = await showModalBottomSheet<PngInfoApply>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PngInfoPasteSheet(),
    );
    if (result == null) return;
    setState(() {
      if (result.prompt != null) _promptController.text = result.prompt!;
      if (result.negativePrompt != null) {
        _negativePromptController.text = result.negativePrompt!;
      }
      if (result.steps != null) _steps = result.steps!;
      if (result.cfgScale != null) _cfgScale = result.cfgScale!;
      if (result.width != null) _width = result.width!;
      if (result.height != null) _height = result.height!;
      if (result.seed != null) _seedController.text = '${result.seed}';
      if (result.sampler != null) _samplerName = result.sampler!;
    });
    
    await _saveParamsToPrefs();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported generation parameters')),
      );
    }
  }

  Widget _buildParamsPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backend = ref.watch(activeProviderProvider);
    final isComfy = backend == GenerationBackend.comfyui;
    final isAppleMl = backend == GenerationBackend.appleMl;
    final profiles = ref.watch(profilesProvider);
    final personas = ref.watch(personasProvider);
    final screenHeight = MediaQuery.of(context).size.height;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 700;
    final maxPanelHeight = isTablet
      ? (screenHeight * 0.85).clamp(420.0, 760.0)
      : (screenHeight * 0.80).clamp(340.0, 620.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxPanelHeight),
      child: Container(
        padding: const EdgeInsets.all(GlassTokens.spacingLg),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
              width: 0.5,
            ),
          ),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (isAppleMl) ...[
              _buildOnDeviceLookFilters(),
              const SizedBox(height: GlassTokens.spacingMd),
              _buildAppleMlModelRow(),
              const SizedBox(height: GlassTokens.spacingMd),
              TextField(
                controller: _seedController,
                decoration: const InputDecoration(
                  labelText: 'Seed (-1 random)',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: GlassTokens.spacingMd),
            ] else if (isComfy) ...[
              const ComfyWorkflowDropdown(),
              const SizedBox(height: GlassTokens.spacingMd),
              _buildModelVaeRow(),
              const SizedBox(height: GlassTokens.spacingMd),
              _buildSamplerSeedRow(),
              const SizedBox(height: GlassTokens.spacingMd),
              _buildSchedulerRow(),
              const SizedBox(height: GlassTokens.spacingMd),
              _buildComfyWorkflowFields(),
            ],
            // ── Quick action chips: Styles · LoRAs · Hires · ControlNet ──
            if (!isAppleMl) _buildFeatureChipsRow(isComfy: isComfy),
            if (!isAppleMl) const SizedBox(height: GlassTokens.spacingMd),
            const SizedBox(height: GlassTokens.spacingMd),

            // ── Style ──
            Text('Style', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            profiles.when(
              data: (list) {
                if (list.isEmpty) {
                  return Text('No styles yet', style: Theme.of(context).textTheme.bodySmall);
                }
                return SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final profile = list[index];
                      final isSelected = _selectedProfileId == profile.id;
                      return ChoiceChip(
                        label: Text(profile.name, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        onSelected: (_) => setState(() {
                          if (isSelected) {
                            _selectedProfileId = null;
                          } else {
                            _selectedProfileId = profile.id;
                            // Apply profile prompts
                            if (profile.positivePrompt.isNotEmpty && _promptController.text.isEmpty) {
                              _promptController.text = profile.positivePrompt;
                            }
                            if (profile.negativePrompt.isNotEmpty) {
                              _negativePromptController.text = profile.negativePrompt;
                            }
                          }
                        }),
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                );
              },
              loading: () => const SizedBox(height: 36),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            // ── Profile ──
            Text('Profile', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            personas.when(
              data: (list) {
                if (list.isEmpty) {
                  return Text('No profiles yet', style: Theme.of(context).textTheme.bodySmall);
                }
                return SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final persona = list[index];
                      final isSelected = _selectedPersonaId == persona.id;
                      return ChoiceChip(
                        label: Text(persona.name, style: const TextStyle(fontSize: 12)),
                        selected: isSelected,
                        onSelected: (_) => setState(() {
                          if (isSelected) {
                            _selectedPersonaId = null;
                          } else {
                            _selectedPersonaId = persona.id;
                            _applyPersona(persona);
                          }
                        }),
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                );
              },
              loading: () => const SizedBox(height: 36),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            // Negative prompt
            TextField(
              controller: _negativePromptController,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              onEditingComplete: () => FocusManager.instance.primaryFocus?.unfocus(),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                hintText: 'Negative prompt...',
                labelText: 'Negative Prompt',
                suffixIcon: IconButton(
                  tooltip: 'Hide keyboard',
                  icon: const Icon(CupertinoIcons.keyboard_chevron_compact_down),
                  onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ),
            ),
            const SizedBox(height: GlassTokens.spacingMd),

            // Steps
            Row(
              children: [
                const Text('Steps'),
                Expanded(
                  child: Slider(
                    value: _steps.toDouble(),
                    min: 1,
                    max: 150,
                    divisions: 149,
                    label: '$_steps',
                    onChanged: (v) => setState(() => _steps = v.round()),
                  ),
                ),
                SizedBox(width: 36, child: Text('$_steps', textAlign: TextAlign.center)),
              ],
            ),

            // CFG Scale
            Row(
              children: [
                const Text('CFG'),
                Expanded(
                  child: Slider(
                    value: _cfgScale,
                    min: 1,
                    max: 30,
                    divisions: 58,
                    label: _cfgScale.toStringAsFixed(1),
                    onChanged: (v) => setState(() => _cfgScale = v),
                  ),
                ),
                SizedBox(width: 36, child: Text(_cfgScale.toStringAsFixed(1), textAlign: TextAlign.center)),
              ],
            ),

            // Distilled CFG (Forge / Flux)
            if (!isComfy && !isAppleMl)
              Row(
                children: [
                  const Text('Distill'),
                  Expanded(
                    child: Slider(
                      value: _distilledCfg.clamp(0, 10),
                      min: 0,
                      max: 10,
                      divisions: 100,
                      label: _distilledCfg.toStringAsFixed(1),
                      onChanged: (v) => setState(() => _distilledCfg = v),
                    ),
                  ),
                  SizedBox(width: 36, child: Text(_distilledCfg.toStringAsFixed(1), textAlign: TextAlign.center)),
                ],
              ),

            // Size presets
            Text('Size', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SizeChip('512×512', 512, 512),
                _SizeChip('512×768', 512, 768),
                _SizeChip('768×512', 768, 512),
                _SizeChip('768×768', 768, 768),
                _SizeChip('1024×1024', 1024, 1024),
                if (isComfy) _SizeChip('1024×1536', 1024, 1536),
              ],
            ),
            if (isAppleMl) ...[
              const SizedBox(height: 6),
              Text(
                'Core ML packages bake in a fixed size (512 for SD 1.5, 768 for SDXL). Steps and CFG still apply.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('width-$_width'),
                    initialValue: '$_width',
                    decoration: const InputDecoration(
                      labelText: 'Width',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n >= 64) {
                        setState(() => _width = n);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('height-$_height'),
                    initialValue: '$_height',
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n >= 64) {
                        setState(() => _height = n);
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: GlassTokens.spacingMd),
            // Toggles & Batch
            if (!isComfy && !isAppleMl) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Restore Faces'),
                    selected: _restoreFaces,
                    onSelected: (v) => setState(() => _restoreFaces = v),
                  ),
                  FilterChip(
                    label: const Text('Live preview'),
                    selected: ref.watch(livePreviewEnabledProvider),
                    onSelected: (v) =>
                        ref.read(livePreviewEnabledProvider.notifier).state = v,
                  ),
                ],
              ),
              const SizedBox(height: GlassTokens.spacingMd),
            ],
            if (!isAppleMl)
              Builder(builder: (context) {
              final maxBatch =
                  ref.watch(hasFeatureProvider(PremiumFeature.largeBatch))
                      ? kPremiumMaxBatch
                      : kFreeMaxBatch;
              if (_batchSize > maxBatch) {
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => setState(() => _batchSize = maxBatch));
              }
              return Row(
                children: [
                  const Text('Batch'),
                  Expanded(
                    child: Slider(
                      value: _batchSize.toDouble().clamp(1, maxBatch.toDouble()),
                      min: 1,
                      max: maxBatch.toDouble(),
                      divisions: maxBatch - 1,
                      label: '$_batchSize',
                      onChanged: (v) =>
                          setState(() => _batchSize = v.round()),
                    ),
                  ),
                  SizedBox(
                      width: 36,
                      child:
                          Text('$_batchSize', textAlign: TextAlign.center)),
                ],
              );
            }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Phase 4 helper builders ──────────────────────────────────────────

  Widget _buildAppleMlModelRow([StateSetter? setModalState]) {
    final installed = ref.watch(appleMlInstalledIdsProvider);
    final selectedId = ref.watch(selectedAppleMlModelIdProvider);
    return installed.when(
      data: (ids) {
        final models = AppleMlCatalog.models
            .where((m) => ids.contains(m.id))
            .toList();
        if (models.isEmpty) {
          return InputDecorator(
            decoration: const InputDecoration(
              labelText: 'On-device model',
              isDense: true,
            ),
            child: TextButton(
              onPressed: () => context.push('/apple-ml-models'),
              child: const Text('Download a Core ML model'),
            ),
          );
        }
        final value = models.any((m) => m.id == selectedId)
            ? selectedId!
            : models.first.id;
        return DropdownButtonFormField<String>(
          isExpanded: true,
          value: value,
          decoration: const InputDecoration(
            labelText: 'On-device model',
            isDense: true,
          ),
          items: models
              .map(
                (m) => DropdownMenuItem(
                  value: m.id,
                  child: Text(
                    '${m.name} · ${m.sizeHint}',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            ref.read(selectedAppleMlModelIdProvider.notifier).set(id);
            final model = AppleMlCatalog.byId(id);
            if (model != null) {
              setState(() {
                _width = model.recommendedWidth;
                _height = model.recommendedHeight;
                _steps = model.recommendedSteps;
                _cfgScale = model.recommendedCfg;
                _samplerName = 'DPM-Solver++';
              });
            }
            if (setModalState != null) setModalState(() {});
          },
        );
      },
      loading: () => const InputDecorator(
        decoration: InputDecoration(
          labelText: 'On-device model',
          isDense: true,
        ),
        child: Text('Checking downloads…'),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildModelVaeRow([StateSetter? setModalState]) {
    final models = ref.watch(serverModelsProvider);
    final vaes = ref.watch(serverVaesProvider);
    final connection = ref.watch(connectionStatusProvider);
    final isComfy =
        ref.watch(activeProviderProvider) == GenerationBackend.comfyui;
    final override = ref.watch(selectedCheckpointOverrideProvider);
    final workflowModel = isComfy
        ? ref.watch(comfyWorkflowDefaultsProvider).asData?.value?.model
        : null;
    final currentModel = override ??
        (isComfy
            ? workflowModel
            : connection.maybeWhen(
                data: (c) => c.currentModel,
                orElse: () => null,
              ));
    final modelLabel = isComfy ? 'Model' : 'Checkpoint';
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: models.when(
            data: (list) {
              final modelsForMenu = [...list];
              if (currentModel != null &&
                  currentModel.isNotEmpty &&
                  !modelsForMenu.any((m) => m.title == currentModel)) {
                modelsForMenu.insert(
                  0,
                  SdModel(
                    title: currentModel,
                    modelName: currentModel,
                    filename: currentModel,
                  ),
                );
              }
              if (modelsForMenu.isEmpty) {
                return InputDecorator(
                  decoration: InputDecoration(
                    labelText: modelLabel,
                    isDense: true,
                  ),
                  child: Text(
                    isComfy ? 'From workflow' : 'No checkpoints',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }
              final selected = modelsForMenu.any((m) => m.title == currentModel)
                  ? currentModel
                  : modelsForMenu.first.title;
              return DropdownButtonFormField<String>(
                key: ValueKey('checkpoint-$_checkpointPickerResets'),
                isExpanded: true,
                value: selected,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
                decoration: InputDecoration(
                  labelText: modelLabel,
                  isDense: true,
                ),
                items: modelsForMenu
                    .map((m) => DropdownMenuItem(
                          value: m.title,
                          child: Text(m.modelName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                selectedItemBuilder: (context) => modelsForMenu
                    .map((m) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            m.modelName,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  final overrideNotifier =
                      ref.read(selectedCheckpointOverrideProvider.notifier);
                  if (isComfy) {
                    overrideNotifier.state = v;
                    ref.invalidate(connectionStatusProvider);
                    if (setModalState != null) setModalState(() {});
                    return;
                  }
                  void revertPicker() {
                    if (!mounted) return;
                    setState(() => _checkpointPickerResets++);
                    if (setModalState != null) setModalState(() {});
                  }

                  final client = ref.read(a1111ClientProvider);
                  if (client == null) {
                    _showError('No A1111 server connected');
                    revertPicker();
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Switching model…')),
                  );
                  try {
                    await client.setModel(v);
                    // Only claim the new checkpoint once A1111 has loaded it.
                    overrideNotifier.state = v;
                    ref.invalidate(connectionStatusProvider);
                  } catch (e) {
                    if (mounted) _showError('Switch failed: $e');
                    revertPicker();
                  }
                },
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => InputDecorator(
              decoration: InputDecoration(
                labelText: modelLabel,
                isDense: true,
                errorText: 'Couldn’t load list',
                suffixIcon: IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    ref.invalidate(serverModelsProvider);
                    if (setModalState != null) setModalState(() {});
                  },
                ),
              ),
              child: Text(
                '$e',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: vaes.when(
            data: (list) {
              final names = <String>['Automatic'];
              if (_vae.isNotEmpty &&
                  _vae != 'Automatic' &&
                  _vae != 'None' &&
                  !names.contains(_vae)) {
                names.add(_vae);
              }
              for (final v in list) {
                if (v.modelName != 'Automatic' &&
                    v.modelName != 'None' &&
                    !names.contains(v.modelName)) {
                  names.add(v.modelName);
                }
              }
              if (!isComfy) names.insert(1, 'None');
              return DropdownButtonFormField<String>(
                isExpanded: true,
                value: names.contains(_vae) ? _vae : 'Automatic',
                decoration: const InputDecoration(
                  labelText: 'VAE',
                  isDense: true,
                ),
                items: names
                    .map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() => _vae = v ?? 'Automatic');
                  if (setModalState != null) setModalState(() {});
                },
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildSamplerSeedRow([StateSetter? setModalState]) {
    final samplers = ref.watch(serverSamplersProvider);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: samplers.when(
            data: (list) {
              if (list.isEmpty) {
                return TextFormField(
                  initialValue: _samplerName,
                  decoration: const InputDecoration(
                    labelText: 'Sampler',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    setState(() => _samplerName = v);
                    if (setModalState != null) setModalState(() {});
                  },
                );
              }
              final names = list.map((s) => s.name).toList();
              var selectedSampler = _samplerName;
              if (selectedSampler.isNotEmpty &&
                  !names.contains(selectedSampler)) {
                final mapped = ComfyWorkflowGraph.mapSampler(selectedSampler);
                if (names.contains(mapped)) {
                  selectedSampler = mapped;
                } else {
                  names.insert(0, selectedSampler);
                }
              }
              return DropdownButtonFormField<String>(
                isExpanded: true,
                value: names.contains(selectedSampler)
                    ? selectedSampler
                    : names.first,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
                decoration: const InputDecoration(
                  labelText: 'Sampler',
                  isDense: true,
                ),
                items: names
                    .map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
                selectedItemBuilder: (context) => names
                    .map((name) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _samplerName = v);
                    if (setModalState != null) setModalState(() {});
                  }
                },
              );
            },
            loading: () => const InputDecorator(
              decoration: InputDecoration(labelText: 'Sampler', isDense: true),
              child: Text('Loading...'),
            ),
            error: (_, __) => TextFormField(
              initialValue: _samplerName,
              decoration:
                  const InputDecoration(labelText: 'Sampler', isDense: true),
              onChanged: (v) {
                setState(() => _samplerName = v);
                if (setModalState != null) setModalState(() {});
              },
            ),
          ),
        ),
        const SizedBox(width: GlassTokens.spacingMd),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _seedController,
            decoration: const InputDecoration(labelText: 'Seed', isDense: true),
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    );
  }

  Widget _buildComfyWorkflowFields([StateSetter? setModalState]) {
    if (_comfyFields.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[
      Text('From this workflow', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
    ];
    String? lastClass;
    for (final field in _comfyFields) {
      if (field.classType != lastClass) {
        lastClass = field.classType;
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              field.classType,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        );
      }
      final value = field.value;
      if (value is bool) {
        children.add(
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(field.label),
            value: value,
            onChanged: (next) {
              _setComfyField(field, next);
              setState(() {});
              setModalState?.call(() {});
            },
          ),
        );
        continue;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            key: ValueKey('comfy-${field.nodeId}-${field.name}'),
            initialValue: value.toString(),
            decoration: InputDecoration(
              labelText: field.label,
              isDense: true,
            ),
            keyboardType: value is num
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            onChanged: (text) {
              final parsed = _parseComfyFieldValue(value, text);
              if (parsed == null) return;
              _setComfyField(field, parsed);
            },
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  void _setComfyField(ComfyWorkflowField field, Object value) {
    final index = _comfyFields.indexWhere(
      (item) => item.nodeId == field.nodeId && item.name == field.name,
    );
    if (index < 0) return;
    _comfyFields = [
      for (var i = 0; i < _comfyFields.length; i++)
        if (i == index) field.copyWith(value: value) else _comfyFields[i],
    ];
  }

  Object? _parseComfyFieldValue(Object original, String text) {
    if (original is int) return int.tryParse(text.trim());
    if (original is double) return double.tryParse(text.trim());
    if (original is num) return num.tryParse(text.trim());
    return text;
  }

  Widget _buildSchedulerRow([StateSetter? setModalState]) {
    final schedulers = ref.watch(serverSchedulersProvider);
    return schedulers.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final names = ['Automatic', ...list.map((s) => s.name)];
        if (_scheduler != null &&
            _scheduler!.isNotEmpty &&
            !names.contains(_scheduler)) {
          names.insert(1, _scheduler!);
        }
        return DropdownButtonFormField<String>(
          isExpanded: true,
          value: names.contains(_scheduler ?? 'Automatic')
              ? (_scheduler ?? 'Automatic')
              : 'Automatic',
          decoration: const InputDecoration(
            labelText: 'Scheduler',
            isDense: true,
          ),
          items: names
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _scheduler = (v == null || v == 'Automatic') ? null : v;
            });
            if (setModalState != null) setModalState(() {});
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildFeatureChipsRow({bool isComfy = false}) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (!isComfy)
          ActionChip(
            avatar: const Icon(CupertinoIcons.tag, size: 14),
            label: Text(_styles.isEmpty
                ? 'Styles'
                : 'Styles · ${_styles.length}'),
            onPressed: () async {
              final res = await showModalBottomSheet<List<String>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => PromptStylesSheet(initial: _styles),
              );
              if (res != null) {
                setState(() => _styles = res);
                await _saveParamsToPrefs();
              }
            },
          ),
        ActionChip(
          avatar: const Icon(CupertinoIcons.layers_alt, size: 14),
          label: Text(
              _loras.isEmpty ? 'LoRAs' : 'LoRAs · ${_loras.length}'),
          onPressed: () async {
            final res = await showModalBottomSheet<List<LoraSelection>>(
              context: context,
              isScrollControlled: true,
              builder: (_) => LoraPickerSheet(initial: _loras),
            );
            if (res != null) {
              setState(() => _loras = res);
              await _saveParamsToPrefs();
            }
          },
        ),
        if (!isComfy)
          ActionChip(
            avatar: Icon(
              _hires.enabled
                  ? CupertinoIcons.arrow_up_right_square_fill
                  : CupertinoIcons.arrow_up_right_square,
              size: 14,
              color: _hires.enabled ? context.accentText : null,
            ),
            label: Text(_hires.enabled
                ? 'Hires ${_hires.scale.toStringAsFixed(1)}×'
                : 'Hires Fix'),
            onPressed: () async {
              final res = await showModalBottomSheet<HiresFixConfig>(
                context: context,
                isScrollControlled: true,
                builder: (_) => HiresFixSheet(initial: _hires),
              );
              if (res != null) {
                setState(() => _hires = res);
              }
            },
          ),
        if (!isComfy)
          ActionChip(
            avatar: Icon(
              _controlNet.any((u) => u.enabled)
                  ? CupertinoIcons.bolt_fill
                  : CupertinoIcons.bolt,
              size: 14,
              color: _controlNet.any((u) => u.enabled) ? context.accentText : null,
            ),
            label: Text(_controlNet.where((u) => u.enabled).isEmpty
                ? 'ControlNet'
                : 'ControlNet · ${_controlNet.where((u) => u.enabled).length}'),
            onPressed: () async {
              final res = await showModalBottomSheet<List<ControlNetUnit>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ControlNetSheet(initial: _controlNet),
              );
              if (res != null) setState(() => _controlNet = res);
            },
          ),
      ],
    );
  }

  Widget _SizeChip(String label, int w, int h) {
    final selected = _width == w && _height == h;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() {
        _width = w;
        _height = h;
      }),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _WelcomeView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.8,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: GlassTokens.spacingLg),
            Text('New Generation Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: GlassTokens.spacingSm),
            Text(
              'Describe your image below to get started',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: GlassTokens.spacingLg),
          ],
        ),
      ),
    );
  }
}

class _NoServerView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(activeProviderProvider);
    final isAppleMl = backend == GenerationBackend.appleMl;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAppleMl ? Icons.phone_iphone : Icons.cloud_off,
              size: 48,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            const SizedBox(height: GlassTokens.spacingLg),
            Text(
              isAppleMl ? 'No on-device model' : 'No Server Connected',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: GlassTokens.spacingSm),
            Text(
              isAppleMl
                  ? 'Download an Apple Core ML Stable Diffusion package to generate on this device.'
                  : 'Please select or add an active server to start generating.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GlassTokens.spacingLg * 1.5),
            FilledButton.icon(
              onPressed: () => isAppleMl
                  ? context.push('/apple-ml-models')
                  : context.push('/servers'),
              icon: Icon(isAppleMl ? Icons.download : Icons.dns),
              label: Text(isAppleMl ? 'Manage models' : 'Manage Servers'),
            ),
            const SizedBox(height: GlassTokens.spacingLg),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final SessionMessage message;
  final bool showNerdStats;
  final GenerationJob? regenerationJob;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCopyImage;
  final VoidCallback? onDelete;
  final VoidCallback? onEditUser;
  final VoidCallback? onDeleteUser;

  const _MessageBubble({
    required this.message,
    this.showNerdStats = false,
    this.regenerationJob,
    this.onRegenerate,
    this.onCopyImage,
    this.onDelete,
    this.onEditUser,
    this.onDeleteUser,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.spacingMd),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isUser) _buildUserMessage(context, isDark),
          if (!isUser) _buildAssistantMessage(context, isDark),
        ],
      ),
    );
  }

  Widget _buildUserMessage(BuildContext context, bool isDark) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(GlassTokens.radiusLg),
          topRight: Radius.circular(GlassTokens.radiusLg),
          bottomLeft: Radius.circular(GlassTokens.radiusLg),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.prompt, style: Theme.of(context).textTheme.bodyMedium),
          if (message.negativePrompt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Negative: ${message.negativePrompt}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (message.parameters['steps'] != null)
                StatusBadge(label: '${message.parameters['steps']} steps', color: AppColors.primary),
              if (message.parameters['cfg_scale'] != null)
                StatusBadge(label: 'CFG ${message.parameters['cfg_scale']}', color: AppColors.primary),
              if (message.parameters['width'] != null)
                StatusBadge(
                  label: '${message.parameters['width']}×${message.parameters['height']}',
                  color: AppColors.primary,
                ),
              if ((message.parameters['batch_size'] as int? ?? 1) > 1)
                StatusBadge(
                  label: 'Batch ${message.parameters['batch_size']}',
                  color: AppColors.primary,
                ),
            ],
          ),
          if (onEditUser != null || onDeleteUser != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onEditUser != null)
                  _UserActionButton(
                    icon: CupertinoIcons.pencil,
                    label: 'Edit',
                    onTap: onEditUser!,
                  ),
                if (onEditUser != null && onDeleteUser != null)
                  const SizedBox(width: 12),
                if (onDeleteUser != null)
                  _UserActionButton(
                    icon: CupertinoIcons.trash,
                    label: 'Delete',
                    onTap: onDeleteUser!,
                    isDestructive: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssistantMessage(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Regeneration progress overlay (in-place)
        if (regenerationJob != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RegenProgressBanner(job: regenerationJob!),
          ),
        // Images grid
        if (message.imagePaths.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final paths = message.imagePaths;
              if (paths.length == 1) {
                return Opacity(
                  opacity: regenerationJob != null ? 0.55 : 1,
                  child: _ImageCard(
                    path: paths[0],
                    width: constraints.maxWidth * 0.75,
                    allPaths: paths,
                    index: 0,
                  ),
                );
              }
              return Opacity(
                opacity: regenerationJob != null ? 0.55 : 1,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < paths.length; i++)
                      _ImageCard(
                        path: paths[i],
                        width: (constraints.maxWidth - 16) / 2,
                        allPaths: paths,
                        index: i,
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        // Metadata badges
        if (message.seed != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                StatusBadge(
                  label: 'Seed: ${message.seed}',
                  color: AppColors.success,
                  icon: Icons.tag,
                ),
                const SizedBox(width: 6),
                if (message.modelName != null)
                  StatusBadge(
                    label: message.modelName!,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
              ],
            ),
          ),
        // Nerd Stats
        if (showNerdStats && message.parameters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GlassCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generation Stats',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (message.parameters['sampler_name'] != null)
                        _NerdStatChip('Sampler: ${message.parameters['sampler_name']}'),
                      if (message.parameters['steps'] != null)
                        _NerdStatChip('Steps: ${message.parameters['steps']}'),
                      if (message.parameters['cfg_scale'] != null)
                        _NerdStatChip('CFG: ${message.parameters['cfg_scale']}'),
                      if (message.parameters['width'] != null)
                        _NerdStatChip('${message.parameters['width']}×${message.parameters['height']}'),
                      if (message.seed != null)
                        _NerdStatChip('Seed: ${message.seed}'),
                      if (message.modelName != null)
                        _NerdStatChip('Model: ${message.modelName}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        // Action icons
        if (message.imagePaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRegenerate != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Regenerate',
                    onPressed: onRegenerate,
                    visualDensity: VisualDensity.compact,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                if (onCopyImage != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy image path',
                    onPressed: onCopyImage,
                    visualDensity: VisualDensity.compact,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    visualDensity: VisualDensity.compact,
                    color: AppColors.error,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NerdStatChip extends StatelessWidget {
  final String text;
  const _NerdStatChip(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
      ),
    );
  }
}

class _UserActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _UserActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String path;
  final double width;
  final List<String> allPaths;
  final int index;

  const _ImageCard({
    required this.path,
    required this.width,
    this.allPaths = const [],
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final paths = allPaths.isNotEmpty ? allPaths : [path];
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ImageViewerScreen(
              imagePaths: paths,
              initialIndex: allPaths.isNotEmpty ? index : 0,
            ),
          ),
        );
      },
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => UpscaleExtrasSheet(
            imagePath: ImageStorage.resolveFileSync(path).path,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: SizedBox(
          width: width,
          child: Image.file(
            ImageStorage.resolveFileSync(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: width,
              height: width,
              color: AppColors.cardLight,
              child: const Center(child: Icon(Icons.broken_image, size: 32)),
            ),
          ),
        ),
      ),
    );
  }
}

bool _isModelLoadStatus(String? statusText) {
  final text = statusText ?? '';
  return !text.startsWith('Step ');
}

class _RegenProgressBanner extends StatelessWidget {
  final GenerationJob job;
  const _RegenProgressBanner({required this.job});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = job.statusText ?? '';
    final loadingModel =
        text.startsWith('Loading model') || text.startsWith('Installing');
    final pct = (job.progress * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35), width: 0.5),
      ),
      child: loadingModel
          ? _RegenLoadBar(statusText: text)
          : Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: job.progress > 0 ? job.progress : null,
                    strokeWidth: 2,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Regenerating… ${job.statusText ?? '$pct%'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.accentText,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _GeneratingPlaceholder extends StatelessWidget {
  final double progress;
  final int width;
  final int height;
  final int batchSize;
  final String? previewBase64;
  final double etaRelative;
  final String? statusText;
  final bool loadingModel;

  const _GeneratingPlaceholder({
    required this.progress,
    required this.width,
    required this.height,
    required this.batchSize,
    this.previewBase64,
    this.etaRelative = 0,
    this.statusText,
    this.loadingModel = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressPercent = (progress * 100).round();
    final screenWidth = MediaQuery.of(context).size.width;
    // Single image takes 75% of width, multiple take half
    final placeholderWidth = batchSize == 1
        ? screenWidth * 0.75
        : (screenWidth - 16 - GlassTokens.spacingLg * 2) / 2;
    final aspectRatio = width / height;

    Widget placeholder = Container(
      width: placeholderWidth,
      height: placeholderWidth / aspectRatio,
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previewBase64 != null && previewBase64!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
              child: Image.memory(
                base64Decode(previewBase64!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          Container(
            color: previewBase64 != null
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.transparent,
          ),
          Center(
            child: loadingModel
                ? _ModelLoadProgress(statusText: statusText, width: placeholderWidth)
                : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress > 0 ? progress : null,
                        strokeWidth: 3,
                        backgroundColor:
                            (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.1),
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                      Text(
                        '$progressPercent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: previewBase64 != null
                              ? Colors.white
                              : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  statusText ??
                      (etaRelative > 0
                          ? 'Generating — ${etaRelative.toStringAsFixed(1)}s left'
                          : 'Generating…'),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 12,
                    color: previewBase64 != null
                        ? Colors.white
                        : (isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.spacingMd),
      child: batchSize == 1
          ? placeholder
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(batchSize, (_) => placeholder),
            ),
    );
  }
}

class _ModelLoadProgress extends StatelessWidget {
  final String? statusText;
  final double width;

  const _ModelLoadProgress({required this.statusText, required this.width});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percent = _loadingPercent(statusText);
    final ink = isDark ? Colors.white : Colors.black;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StaticLoadBar(
            fraction: percent / 100,
            width: width * 0.72,
            height: 6,
            track: ink.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 10),
          Text(
            _loadStatusLabel(statusText, percent),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegenLoadBar extends StatelessWidget {
  final String statusText;
  const _RegenLoadBar({required this.statusText});

  @override
  Widget build(BuildContext context) {
    final percent = _loadingPercent(statusText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _loadStatusLabel(statusText, percent),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: context.accentText,
          ),
        ),
        const SizedBox(height: 6),
        _StaticLoadBar(
          fraction: percent / 100,
          height: 4,
          track: AppColors.primary.withValues(alpha: 0.15),
        ),
      ],
    );
  }
}

/// A fixed-width bar. [LinearProgressIndicator] keeps animating, and those
/// frames were hitting the GPU while Core ML mapped the weights.
class _StaticLoadBar extends StatelessWidget {
  final double fraction;
  final double? width;
  final double height;
  final Color track;

  const _StaticLoadBar({
    required this.fraction,
    required this.height,
    required this.track,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0, 1),
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _loadStatusLabel(String? statusText, int percent) {
  final text = statusText?.trim() ?? '';
  if (text.isEmpty) return '$percent% loaded';
  return text;
}

int _loadingPercent(String? statusText) {
  final text = statusText ?? '';
  final percent = RegExp(r'(\d+)%').firstMatch(text);
  if (percent != null) {
    return (int.tryParse(percent.group(1) ?? '') ?? 0).clamp(0, 100);
  }
  final step = RegExp(r'\((\d+)/(\d+)\)').firstMatch(text);
  if (step != null) {
    final done = int.tryParse(step.group(1) ?? '') ?? 0;
    final total = int.tryParse(step.group(2) ?? '') ?? 1;
    if (total > 0) return ((done / total) * 100).round().clamp(0, 100);
  }
  return 0;
}

// ════════════════════════════════════════════════════════════════
// Wraps the parameters panel so a downward swipe at the top of it
// dismisses it. Tapping outside (in the chat list) also dismisses
// (handled by Listener in build()).
// ════════════════════════════════════════════════════════════════

class _DismissibleParamsPanel extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  const _DismissibleParamsPanel({required this.child, required this.onDismiss});

  @override
  State<_DismissibleParamsPanel> createState() =>
      _DismissibleParamsPanelState();
}

class _DismissibleParamsPanelState extends State<_DismissibleParamsPanel> {
  double _dragAccum = 0;

  void _dismissKeyboardOrSheet() {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (keyboardOpen) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle bar — also captures vertical drag.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _dragAccum = 0,
          onVerticalDragUpdate: (d) {
            if (keyboardOpen) {
              FocusManager.instance.primaryFocus?.unfocus();
              return;
            }
            _dragAccum += d.delta.dy;
            if (_dragAccum > 36) widget.onDismiss();
          },
          onTap: _dismissKeyboardOrSheet,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Flexible(child: widget.child),
        if (keyboardOpen)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: const Text('Done'),
            ),
          ),
      ],
    );
  }
}
