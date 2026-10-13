import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../api/a1111_client_interface.dart';
import '../api/local_a1111_client.dart';
import '../api/apple_ml_sd_plugin.dart';
import '../api/comfyui_client.dart';
import '../api/api_models.dart';
import '../api/comfy_builtin_workflows.dart';
import '../api/comfy_catalog.dart';
import '../api/comfyui_workflow.dart';
import '../models/generation_backend.dart';
import '../models/server.dart';
import '../models/session.dart';
import '../on_device/apple_ml_downloader.dart';
import '../on_device/apple_ml_models.dart';
import '../remote/remote_access.dart';

final databaseProvider = FutureProvider<Database>((ref) async {
  return AppDatabase.database;
});

// ─── Theme ───
final themeModeProvider = StateProvider<String>((ref) => 'system');

// ─── Servers ───
final serversListProvider = FutureProvider<List<Server>>((ref) async {
  final db = await ref.read(databaseProvider.future);
  final results = await db.query('servers', orderBy: 'created_at DESC');
  return results.map((e) => Server.fromMap(e)).toList();
});

// ─── Active Provider (A1111 / ComfyUI) ───
final activeProviderProvider =
    StateNotifierProvider<ActiveProviderNotifier, GenerationBackend>((ref) {
  return ActiveProviderNotifier(ref);
});

class ActiveProviderNotifier extends StateNotifier<GenerationBackend> {
  final Ref _ref;
  final Completer<void> _loaded = Completer<void>();

  ActiveProviderNotifier(this._ref) : super(GenerationBackend.a1111) {
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await _ref.read(databaseProvider.future);
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['active_provider'],
      );
      final saved = rows.isNotEmpty
          ? GenerationBackend.fromId(rows.first['value'] as String?)
          : null;
      if (saved == GenerationBackend.appleMl) {
        state = saved!;
        return;
      }
      final active = await db.query('servers', where: 'is_active = 1', limit: 1);
      if (active.isNotEmpty) {
        state = Server.fromMap(active.first).provider;
        return;
      }
      if (saved != null) state = saved;
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> ensureLoaded() => _loaded.future;

  Future<void> set(GenerationBackend backend) async {
    if (state == backend) return;
    state = backend;
    final db = await _ref.read(databaseProvider.future);
    await db.insert(
      'app_settings',
      {'key': 'active_provider', 'value': backend.id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (backend.requiresRemoteServer) {
      final remembered = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['active_server_${backend.id}'],
      );
      Server? next;
      if (remembered.isNotEmpty) {
        final id = remembered.first['value'] as String;
        final rows = await db.query('servers', where: 'id = ?', whereArgs: [id]);
        if (rows.isNotEmpty) next = Server.fromMap(rows.first);
      }
      next ??= await _firstServer(backend);
      if (next != null) {
        await _ref.read(activeServerProvider.notifier).setActive(next);
      } else {
        await _ref.read(activeServerProvider.notifier).clear();
      }
    }
    _invalidateServerCaches();
  }

  Future<Server?> _firstServer(GenerationBackend backend) async {
    final db = await _ref.read(databaseProvider.future);
    final rows = await db.query(
      'servers',
      where: 'provider = ?',
      whereArgs: [backend.id],
      orderBy: 'last_connected_at DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Server.fromMap(rows.first);
  }

  void _invalidateServerCaches() {
    invalidateGenerationCaches(_ref);
  }
}

// ─── Active Server ───
final activeServerProvider = StateNotifierProvider<ActiveServerNotifier, Server?>((ref) {
  return ActiveServerNotifier(ref);
});

class ActiveServerNotifier extends StateNotifier<Server?> {
  final Ref _ref;
  final Completer<void> _loaded = Completer<void>();

  ActiveServerNotifier(this._ref) : super(null) {
    _loadActiveServer();
  }

  Future<void> ensureLoaded() => _loaded.future;

  Future<void> _loadActiveServer() async {
    try {
      final db = await _ref.read(databaseProvider.future);
      final results = await db.query('servers', where: 'is_active = 1', limit: 1);
      if (results.isNotEmpty) {
        final server = Server.fromMap(results.first);
        state = server;
        final backend = _ref.read(activeProviderProvider);
        if (backend.requiresRemoteServer && backend != server.provider) {
          _ref.read(activeProviderProvider.notifier).state = server.provider;
        }
      }
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> setActive(Server server) async {
    final db = await _ref.read(databaseProvider.future);
    await db.update('servers', {'is_active': 0});
    await db.update('servers', {'is_active': 1}, where: 'id = ?', whereArgs: [server.id]);
    await db.insert(
      'app_settings',
      {'key': 'active_server_${server.provider.id}', 'value': server.id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'app_settings',
      {'key': 'active_provider', 'value': server.provider.id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    state = server.copyWith(isActive: true);
    if (_ref.read(activeProviderProvider) != server.provider) {
      _ref.read(activeProviderProvider.notifier).state = server.provider;
    }
    invalidateGenerationCaches(_ref);
  }

  Future<void> clear() async {
    final db = await _ref.read(databaseProvider.future);
    await db.update('servers', {'is_active': 0});
    state = null;
    invalidateGenerationCaches(_ref);
  }

  /// Swaps in an edited copy of the active server so clients pick up the
  /// new host/port/token, without changing which backend is selected.
  void refreshIfActive(Server server) {
    if (state?.id != server.id) return;
    state = server.copyWith(isActive: true);
    invalidateGenerationCaches(_ref);
  }
}

/// Records a successful probe. Only the DB row changes: replacing the
/// active server state here would rebuild clients and re-probe.
Future<DateTime> markServerConnected(Database db, String serverId) async {
  final now = DateTime.now();
  await db.update(
    'servers',
    {'last_connected_at': now.toIso8601String()},
    where: 'id = ?',
    whereArgs: [serverId],
  );
  return now;
}

final selectedComfyWorkflowProvider =
    StateNotifierProvider<SelectedComfyWorkflowNotifier, String?>((ref) {
  return SelectedComfyWorkflowNotifier(ref);
});

class SelectedComfyWorkflowNotifier extends StateNotifier<String?> {
  final Ref _ref;

  SelectedComfyWorkflowNotifier(this._ref) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final db = await _ref.read(databaseProvider.future);
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['comfyui_workflow_path'],
    );
    if (rows.isNotEmpty) {
      final value = rows.first['value'] as String;
      if (value.isNotEmpty) {
        state = value;
        return;
      }
    }
    state = kComfyBuiltinSdWorkflowPath;
  }

  Future<void> set(String? path) async {
    state = path;
    final db = await _ref.read(databaseProvider.future);
    await db.insert(
      'app_settings',
      {'key': 'comfyui_workflow_path', 'value': path ?? ''},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

final selectedCheckpointOverrideProvider = StateProvider<String?>((_) => null);

final selectedAppleMlModelIdProvider =
    StateNotifierProvider<SelectedAppleMlModelNotifier, String?>((ref) {
  return SelectedAppleMlModelNotifier(ref);
});

class SelectedAppleMlModelNotifier extends StateNotifier<String?> {
  final Ref _ref;

  SelectedAppleMlModelNotifier(this._ref) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final db = await _ref.read(databaseProvider.future);
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['apple_ml_model_id'],
    );
    if (rows.isNotEmpty) {
      state = rows.first['value'] as String?;
    }
  }

  Future<void> set(String? id) async {
    state = id;
    final db = await _ref.read(databaseProvider.future);
    if (id == null || id.isEmpty) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['apple_ml_model_id'],
      );
    } else {
      await db.insert(
        'app_settings',
        {'key': 'apple_ml_model_id', 'value': id},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    _ref.invalidate(connectionStatusProvider);
  }
}

// ─── Generation timeout (1 minute … 1 day) ───
const kGenerationTimeoutMinMinutes = 1;
const kGenerationTimeoutMaxMinutes = 24 * 60;
const kGenerationTimeoutDefaultMinutes = 10;

String formatGenerationTimeout(int minutes) {
  final clamped = minutes.clamp(
    kGenerationTimeoutMinMinutes,
    kGenerationTimeoutMaxMinutes,
  );
  if (clamped < 60) {
    return clamped == 1 ? '1 minute' : '$clamped minutes';
  }
  if (clamped % (24 * 60) == 0) {
    return '1 day';
  }
  if (clamped % 60 == 0) {
    final hours = clamped ~/ 60;
    return hours == 1 ? '1 hour' : '$hours hours';
  }
  final hours = clamped ~/ 60;
  final mins = clamped % 60;
  return '${hours}h ${mins}m';
}

final generationTimeoutMinutesProvider =
    StateNotifierProvider<GenerationTimeoutNotifier, int>((ref) {
  return GenerationTimeoutNotifier(ref);
});

class GenerationTimeoutNotifier extends StateNotifier<int> {
  final Ref _ref;

  GenerationTimeoutNotifier(this._ref)
      : super(kGenerationTimeoutDefaultMinutes) {
    _load();
  }

  Future<void> _load() async {
    final db = await _ref.read(databaseProvider.future);
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['gen_timeout_minutes'],
    );
    if (rows.isEmpty) return;
    final parsed = int.tryParse(rows.first['value'] as String? ?? '');
    if (parsed == null) return;
    state = parsed.clamp(
      kGenerationTimeoutMinMinutes,
      kGenerationTimeoutMaxMinutes,
    );
  }

  Future<void> setMinutes(int minutes) async {
    state = minutes.clamp(
      kGenerationTimeoutMinMinutes,
      kGenerationTimeoutMaxMinutes,
    );
    final db = await _ref.read(databaseProvider.future);
    await db.insert(
      'app_settings',
      {'key': 'gen_timeout_minutes', 'value': '$state'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

// ─── Clients ───
const kRelayUnsupportedMessage =
    'Remote relay servers aren’t supported in this version. '
    'Use your computer’s local IP on the same Wi‑Fi instead.';

/// Relay servers stay saved but unusable without remote access.
bool _relayLocked(Ref ref, Server server) =>
    server.isRemote && ref.watch(enabledRemoteAccessProvider) == null;

final a1111ClientProvider = Provider<IA1111Client?>((ref) {
  // On-device mode keeps a remembered server, but it isn't in use.
  if (ref.watch(activeProviderProvider) == GenerationBackend.appleMl) {
    return null;
  }
  final server = ref.watch(activeServerProvider);
  if (server == null || server.provider != GenerationBackend.a1111) return null;
  if (_relayLocked(ref, server)) return null;
  final timeout = Duration(minutes: ref.watch(generationTimeoutMinutesProvider));
  final client = LocalA1111Client(
    host: server.host,
    port: server.port,
    authToken: server.authToken,
    backendHeader: server.provider.id,
    receiveTimeout: timeout,
  );
  // Keep client alive so in-flight generation requests survive screen navigation.
  // It will be replaced naturally when active server changes.
  return client;
});

final comfyuiClientProvider = Provider<ComfyUiClient?>((ref) {
  if (ref.watch(activeProviderProvider) == GenerationBackend.appleMl) {
    return null;
  }
  final server = ref.watch(activeServerProvider);
  if (server == null || server.provider != GenerationBackend.comfyui) return null;
  if (_relayLocked(ref, server)) return null;
  final timeout = Duration(minutes: ref.watch(generationTimeoutMinutesProvider));
  return ComfyUiClient(
    host: server.host,
    port: server.port,
    authToken: server.authToken,
    backendHeader: server.provider.id,
    receiveTimeout: timeout,
  );
});

final comfyLastRunGraphProvider =
    StateProvider<Map<String, dynamic>?>((_) => null);

/// True when comfyWorkflowsProvider couldn't read the server's saved
/// workflows / last run and fell back to the built-ins.
final comfyWorkflowsListingFailedProvider = StateProvider<bool>((_) => false);

final comfyWorkflowsProvider = FutureProvider<List<ComfyWorkflowInfo>>((ref) async {
  final builtins = builtinComfyWorkflows();
  final client = ref.watch(comfyuiClientProvider);
  if (client == null) return builtins;

  var listingFailed = false;
  ComfyHistoryGraph? last;
  try {
    last = await client.fetchLastRun();
  } catch (_) {
    listingFailed = true;
  }

  if (last != null) {
    ref.read(comfyLastRunGraphProvider.notifier).state =
        Map<String, dynamic>.from(last.graph);
  }

  List<ComfyWorkflowInfo> saved = const [];
  try {
    saved = await client.listWorkflows();
  } catch (_) {
    listingFailed = true;
  }
  ref.read(comfyWorkflowsListingFailedProvider.notifier).state = listingFailed;

  final lastLabel = last?.loaderLabel;
  return [
    ...builtins,
    if (last != null)
      ComfyWorkflowInfo(
        path: kComfyLastRunWorkflowPath,
        name: (lastLabel == null || lastLabel.isEmpty)
            ? 'Last run in ComfyUI'
            : 'Last run ($lastLabel)',
      ),
    ...saved,
  ];
});

final comfyWorkflowDefaultsProvider =
    FutureProvider<ComfyWorkflowDefaults?>((ref) async {
  if (ref.watch(activeProviderProvider) != GenerationBackend.comfyui) {
    return null;
  }
  final path = ref.watch(selectedComfyWorkflowProvider);
  if (path == null || path.trim().isEmpty) return null;
  final client = ref.watch(comfyuiClientProvider);
  if (client == null) return null;

  Map<String, dynamic> raw;
  if (isComfyLastRunWorkflowPath(path)) {
    final snap = ref.watch(comfyLastRunGraphProvider);
    raw = snap ?? await client.getWorkflow(path);
  } else {
    raw = await client.getWorkflow(path);
  }
  Map<String, dynamic>? objectInfo;
  if (!ComfyWorkflowGraph.isApiFormat(raw)) {
    try {
      objectInfo = await client.objectInfo();
    } catch (_) {}
  }
  return ComfyWorkflowGraph.fromWorkflow(raw, objectInfo: objectInfo)
      .readDefaults();
});

// ─── Server Data Cache ───
final serverModelsProvider = FutureProvider<List<SdModel>>((ref) async {
  final a1111 = ref.watch(a1111ClientProvider);
  if (a1111 != null) return a1111.getModels();
  final comfy = ref.watch(comfyuiClientProvider);
  if (comfy != null) return comfy.getModels();
  return [];
});

final serverSamplersProvider = FutureProvider<List<SdSampler>>((ref) async {
  final a1111 = ref.watch(a1111ClientProvider);
  if (a1111 != null) return a1111.getSamplers();
  final comfy = ref.watch(comfyuiClientProvider);
  if (comfy != null) return comfy.getSamplers();
  return [];
});

final serverLorasProvider = FutureProvider<List<SdLora>>((ref) async {
  final a1111 = ref.watch(a1111ClientProvider);
  if (a1111 != null) return a1111.getLoras();
  final comfy = ref.watch(comfyuiClientProvider);
  if (comfy != null) return comfy.getLoras();
  return [];
});

final serverVaesProvider = FutureProvider<List<SdVae>>((ref) async {
  final a1111 = ref.watch(a1111ClientProvider);
  if (a1111 != null) return a1111.getVaes();
  final comfy = ref.watch(comfyuiClientProvider);
  if (comfy != null) return comfy.getVaes();
  return [];
});

final serverUpscalersProvider = FutureProvider<List<SdUpscaler>>((ref) async {
  final a1111 = ref.watch(a1111ClientProvider);
  if (a1111 != null) return a1111.getUpscalers();
  final comfy = ref.watch(comfyuiClientProvider);
  if (comfy != null) return comfy.getUpscalers();
  return [];
});

final serverSchedulersProvider = FutureProvider<List<SdScheduler>>((ref) async {
  final a1111 = ref.watch(a1111ClientProvider);
  if (a1111 != null) return a1111.getSchedulers();
  final comfy = ref.watch(comfyuiClientProvider);
  if (comfy != null) return comfy.getSchedulers();
  return [];
});

final serverPromptStylesProvider =
    FutureProvider<List<SdPromptStyle>>((ref) async {
  final client = ref.watch(a1111ClientProvider);
  if (client == null) return [];
  return client.getPromptStyles();
});

final controlNetTypesProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(a1111ClientProvider);
  if (client == null) return const {};
  return client.controlNetTypes();
});

final controlNetModelsProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.watch(a1111ClientProvider);
  if (client == null) return const [];
  return client.controlNetModels();
});

final controlNetModulesProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.watch(a1111ClientProvider);
  if (client == null) return const [];
  return client.controlNetModules();
});

void invalidateGenerationCaches(Ref ref) {
  ref.invalidate(connectionStatusProvider);
  ref.invalidate(serverModelsProvider);
  ref.invalidate(serverSamplersProvider);
  ref.invalidate(serverLorasProvider);
  ref.invalidate(serverVaesProvider);
  ref.invalidate(serverUpscalersProvider);
  ref.invalidate(serverSchedulersProvider);
  ref.invalidate(serverPromptStylesProvider);
  ref.invalidate(comfyWorkflowsProvider);
  ref.invalidate(comfyWorkflowDefaultsProvider);
  // A checkpoint picked on the previous server doesn't exist on the next.
  ref.invalidate(selectedCheckpointOverrideProvider);
}

bool hasUsableGenerationTargetFor(
  GenerationBackend backend,
  Server? server,
  String? appleModelId,
) {
  if (backend == GenerationBackend.appleMl) {
    return AppleMlCatalog.byId(appleModelId) != null;
  }
  return server != null;
}

// ─── Connection Status ───
final connectionStatusProvider = FutureProvider<ConnectionStatus>((ref) async {
  await ref.read(activeServerProvider.notifier).ensureLoaded();
  await ref.read(activeProviderProvider.notifier).ensureLoaded();
  final backend = ref.watch(activeProviderProvider);
  if (backend == GenerationBackend.appleMl) {
    if (!Platform.isIOS) {
      return const ConnectionStatus(
        connected: false,
        error: 'On-device Apple ML is available on iOS only',
      );
    }
    final available = await AppleMlSdPlugin.isAvailable();
    if (!available) {
      return const ConnectionStatus(
        connected: false,
        error: 'On-device Stable Diffusion needs iOS 16.2 or later',
      );
    }
    final id = ref.watch(selectedAppleMlModelIdProvider);
    final model = AppleMlCatalog.byId(id);
    if (model == null) {
      return const ConnectionStatus(
        connected: false,
        error: 'Download a Core ML model to generate on device',
      );
    }
    final installed = await AppleMlDownloader().isInstalled(model);
    if (!installed) {
      return ConnectionStatus(
        connected: false,
        error: 'Download ${model.name} to generate on device',
      );
    }
    return ConnectionStatus(connected: true, currentModel: model.name);
  }
  final server = ref.watch(activeServerProvider);
  if (server != null && _relayLocked(ref, server)) {
    return const ConnectionStatus(
      connected: false,
      error: kRelayUnsupportedMessage,
    );
  }
  if (backend == GenerationBackend.comfyui) {
    final client = ref.watch(comfyuiClientProvider);
    if (client == null) {
      return const ConnectionStatus(
        connected: false,
        error: 'No ComfyUI server configured',
      );
    }
    final status = await client.testConnection();
    if (status.connected) {
      final db = await ref.read(databaseProvider.future);
      await markServerConnected(db, server!.id);
    }
    final override = ref.watch(selectedCheckpointOverrideProvider);
    return ConnectionStatus(
      connected: status.connected,
      currentModel: override ?? status.currentModel,
      error: status.error,
      warning: status.warning,
    );
  }

  final client = ref.watch(a1111ClientProvider);
  if (client == null) {
    return const ConnectionStatus(connected: false, error: 'No server configured');
  }
  final status = await client.testConnection();
  if (status.connected) {
    final db = await ref.read(databaseProvider.future);
    await markServerConnected(db, server!.id);
  }
  return status;
});

// ─── Global Generation Settings ───
class GenerationDefaults {
  final String samplerName;
  final String? scheduler;
  final int steps;
  final double cfgScale;
  final double distilledCfgScale; // Forge / Flux distilled CFG
  final int width;
  final int height;
  final bool restoreFaces;
  final int batchSize;
  final bool showNerdStats;
  // Hires Fix
  final bool hiresEnabled;
  final double hiresScale;
  final int hiresSteps;
  final double hiresDenoising;
  final String hiresUpscaler;
  // Refiner
  final String? refinerCheckpoint;
  final double refinerSwitchAt;
  // Prompt styles applied by default (server-side)
  final List<String> promptStyles;
  // Active VAE override ("Automatic" leaves server's choice)
  final String vae;

  const GenerationDefaults({
    this.samplerName = 'Euler a',
    this.scheduler,
    this.steps = 20,
    this.cfgScale = 7.0,
    this.distilledCfgScale = 3.5,
    this.width = 512,
    this.height = 512,
    this.restoreFaces = false,
    this.batchSize = 1,
    this.showNerdStats = false,
    this.hiresEnabled = false,
    this.hiresScale = 1.5,
    this.hiresSteps = 0,
    this.hiresDenoising = 0.5,
    this.hiresUpscaler = 'Latent',
    this.refinerCheckpoint,
    this.refinerSwitchAt = 0.8,
    this.promptStyles = const [],
    this.vae = 'Automatic',
  });

  GenerationDefaults copyWith({
    String? samplerName,
    String? scheduler,
    int? steps,
    double? cfgScale,
    double? distilledCfgScale,
    int? width,
    int? height,
    bool? restoreFaces,
    int? batchSize,
    bool? showNerdStats,
    bool? hiresEnabled,
    double? hiresScale,
    int? hiresSteps,
    double? hiresDenoising,
    String? hiresUpscaler,
    String? refinerCheckpoint,
    double? refinerSwitchAt,
    List<String>? promptStyles,
    String? vae,
  }) =>
      GenerationDefaults(
        samplerName: samplerName ?? this.samplerName,
        scheduler: scheduler ?? this.scheduler,
        steps: steps ?? this.steps,
        cfgScale: cfgScale ?? this.cfgScale,
        distilledCfgScale: distilledCfgScale ?? this.distilledCfgScale,
        width: width ?? this.width,
        height: height ?? this.height,
        restoreFaces: restoreFaces ?? this.restoreFaces,
        batchSize: batchSize ?? this.batchSize,
        showNerdStats: showNerdStats ?? this.showNerdStats,
        hiresEnabled: hiresEnabled ?? this.hiresEnabled,
        hiresScale: hiresScale ?? this.hiresScale,
        hiresSteps: hiresSteps ?? this.hiresSteps,
        hiresDenoising: hiresDenoising ?? this.hiresDenoising,
        hiresUpscaler: hiresUpscaler ?? this.hiresUpscaler,
        refinerCheckpoint: refinerCheckpoint ?? this.refinerCheckpoint,
        refinerSwitchAt: refinerSwitchAt ?? this.refinerSwitchAt,
        promptStyles: promptStyles ?? this.promptStyles,
        vae: vae ?? this.vae,
      );
}

final generationDefaultsProvider =
    StateNotifierProvider<GenerationDefaultsNotifier, GenerationDefaults>((ref) {
  return GenerationDefaultsNotifier(ref);
});

class GenerationDefaultsNotifier extends StateNotifier<GenerationDefaults> {
  final Ref _ref;

  GenerationDefaultsNotifier(this._ref) : super(const GenerationDefaults()) {
    _load();
  }

  Future<void> _load() async {
    final db = await _ref.read(databaseProvider.future);
    final rows = await db.query('app_settings');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};

    state = GenerationDefaults(
      samplerName: map['gen_sampler'] ?? 'Euler a',
      scheduler: map['gen_scheduler'],
      steps: int.tryParse(map['gen_steps'] ?? '') ?? 20,
      cfgScale: double.tryParse(map['gen_cfg_scale'] ?? '') ?? 7.0,
      distilledCfgScale:
          double.tryParse(map['gen_distilled_cfg'] ?? '') ?? 3.5,
      width: int.tryParse(map['gen_width'] ?? '') ?? 512,
      height: int.tryParse(map['gen_height'] ?? '') ?? 512,
      restoreFaces: map['gen_restore_faces'] == 'true',
      batchSize: int.tryParse(map['gen_batch_size'] ?? '') ?? 1,
      showNerdStats: map['gen_show_nerd_stats'] == 'true',
      hiresEnabled: map['gen_hires_enabled'] == 'true',
      hiresScale: double.tryParse(map['gen_hires_scale'] ?? '') ?? 1.5,
      hiresSteps: int.tryParse(map['gen_hires_steps'] ?? '') ?? 0,
      hiresDenoising: double.tryParse(map['gen_hires_denoise'] ?? '') ?? 0.5,
      hiresUpscaler: map['gen_hires_upscaler'] ?? 'Latent',
      refinerCheckpoint: map['gen_refiner_ckpt'],
      refinerSwitchAt:
          double.tryParse(map['gen_refiner_switch'] ?? '') ?? 0.8,
      promptStyles: (map['gen_prompt_styles'] ?? '').isEmpty
          ? const []
          : map['gen_prompt_styles']!.split('\u0001'),
      vae: map['gen_vae'] ?? 'Automatic',
    );
  }

  Future<void> update(GenerationDefaults newDefaults) async {
    state = newDefaults;
    final db = await _ref.read(databaseProvider.future);
    final entries = {
      'gen_sampler': newDefaults.samplerName,
      'gen_scheduler': newDefaults.scheduler ?? '',
      'gen_steps': '${newDefaults.steps}',
      'gen_cfg_scale': '${newDefaults.cfgScale}',
      'gen_distilled_cfg': '${newDefaults.distilledCfgScale}',
      'gen_width': '${newDefaults.width}',
      'gen_height': '${newDefaults.height}',
      'gen_restore_faces': '${newDefaults.restoreFaces}',
      'gen_batch_size': '${newDefaults.batchSize}',
      'gen_show_nerd_stats': '${newDefaults.showNerdStats}',
      'gen_hires_enabled': '${newDefaults.hiresEnabled}',
      'gen_hires_scale': '${newDefaults.hiresScale}',
      'gen_hires_steps': '${newDefaults.hiresSteps}',
      'gen_hires_denoise': '${newDefaults.hiresDenoising}',
      'gen_hires_upscaler': newDefaults.hiresUpscaler,
      'gen_refiner_ckpt': newDefaults.refinerCheckpoint ?? '',
      'gen_refiner_switch': '${newDefaults.refinerSwitchAt}',
      'gen_prompt_styles': newDefaults.promptStyles.join('\u0001'),
      'gen_vae': newDefaults.vae,
    };
    for (final e in entries.entries) {
      await db.insert(
        'app_settings',
        {'key': e.key, 'value': e.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}

// ─── Sessions ───
/// All persisted sessions, sorted newest first.
final sessionsProvider = FutureProvider<List<Session>>((ref) async {
  final db = await ref.read(databaseProvider.future);
  final results = await db.query('sessions', orderBy: 'updated_at DESC');
  return results.map((e) => Session.fromMap(e)).toList();
});

// ─── Landscape split-view ───
/// Session ID shown in the right (detail) panel on landscape devices.
final landscapeDetailSessionProvider = StateProvider<String?>((ref) => null);
