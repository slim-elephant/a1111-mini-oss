import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/apple_ml_sd_plugin.dart';
import '../providers/core_providers.dart';
import 'apple_ml_downloader.dart';
import 'apple_ml_models.dart';

final appleMlDownloaderProvider = Provider<AppleMlDownloader>((ref) {
  return AppleMlDownloader();
});

final appleMlInstalledIdsProvider = FutureProvider<Set<String>>((ref) async {
  return ref.watch(appleMlDownloaderProvider).installedIds();
});

class AppleMlDownloadController
    extends StateNotifier<Map<String, AppleMlDownloadProgress>> {
  final Ref _ref;
  bool _ensuringInstall = false;
  bool _installAgain = false;

  AppleMlDownloadController(this._ref) : super(const {}) {
    restoreNativeJob().whenComplete(ensureNeuralEngineInstall);
  }

  Future<void> restoreNativeJob() async {
    final downloader = _ref.read(appleMlDownloaderProvider);
    try {
      final info = await downloader.resumeIfNativeJobActive((progress) {
        state = {...state, progress.modelId: progress};
      });
      if (info != null) {
        _ref.invalidate(appleMlInstalledIdsProvider);
        _ref.invalidate(connectionStatusProvider);
      }
    } catch (e) {
      // Keep the in-app progress card if native already reported an id.
    }
  }

  bool isBusy(String modelId) {
    final current = state[modelId];
    if (current == null) return false;
    return current.stage == 'listing' ||
        current.stage == 'downloading' ||
        current.stage == 'finalizing' ||
        current.stage == 'installing';
  }

  /// Specializes downloaded Core ML packages for this iPhone once.
  /// Later generations skip this and go straight to sampling.
  Future<void> ensureNeuralEngineInstall() async {
    if (_ensuringInstall) {
      _installAgain = true;
      return;
    }
    _ensuringInstall = true;
    try {
      final available = await AppleMlSdPlugin.isAvailable();
      if (!available) return;
      final downloader = _ref.read(appleMlDownloaderProvider);
      do {
        _installAgain = false;
        for (final model in AppleMlCatalog.models) {
          if (isBusy(model.id)) continue;
          final info = await downloader.installInfo(model);
          if (info == null) continue;
          if (!await downloader.isInstalled(model)) continue;
          if (await AppleMlSdPlugin.isCompiled(info.resourcesPath)) continue;
          state = {
            ...state,
            model.id: AppleMlDownloadProgress(
              modelId: model.id,
              stage: 'installing',
              currentFile:
                  'Installing on the Neural Engine — one time, speed depends on this iPhone',
            ),
          };
          try {
            await AppleMlSdPlugin.install(
              resourcesPath: info.resourcesPath,
              variant: model.isSdxl ? 'sdxl' : 'sd15',
              displayName: model.name,
            );
            state = {
              ...state,
              model.id: AppleMlDownloadProgress(
                modelId: model.id,
                stage: 'ready',
              ),
            };
          } catch (e) {
            state = {
              ...state,
              model.id: AppleMlDownloadProgress(
                modelId: model.id,
                stage: 'error',
                error: e.toString(),
              ),
            };
          }
        }
      } while (_installAgain);
    } finally {
      _ensuringInstall = false;
    }
  }

  Future<void> download(AppleMlCatalogModel model) async {
    if (isBusy(model.id)) return;
    final downloader = _ref.read(appleMlDownloaderProvider);
    state = {
      ...state,
      model.id: AppleMlDownloadProgress(modelId: model.id, stage: 'listing'),
    };
    try {
      await downloader.download(
        model,
        onProgress: (progress) {
          state = {...state, model.id: progress};
        },
      );
      final selected = _ref.read(selectedAppleMlModelIdProvider);
      if (selected == null || selected.isEmpty) {
        await _ref.read(selectedAppleMlModelIdProvider.notifier).set(model.id);
      }
      _ref.invalidate(appleMlInstalledIdsProvider);
      _ref.invalidate(connectionStatusProvider);
      await ensureNeuralEngineInstall();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = {
          ...state,
          model.id: AppleMlDownloadProgress(
            modelId: model.id,
            stage: 'idle',
            cancelRequested: true,
          ),
        };
        return;
      }
      state = {
        ...state,
        model.id: AppleMlDownloadProgress(
          modelId: model.id,
          stage: 'error',
          error: e.message ?? e.toString(),
        ),
      };
      rethrow;
    } catch (e) {
      if (e.toString().contains('cancelled')) {
        state = {
          ...state,
          model.id: AppleMlDownloadProgress(
            modelId: model.id,
            stage: 'idle',
            cancelRequested: true,
          ),
        };
        return;
      }
      state = {
        ...state,
        model.id: AppleMlDownloadProgress(
          modelId: model.id,
          stage: 'error',
          error: e.toString(),
        ),
      };
      rethrow;
    }
  }

  void cancel(AppleMlCatalogModel model) {
    _ref.read(appleMlDownloaderProvider).cancel();
  }

  Future<void> delete(AppleMlCatalogModel model) async {
    cancel(model);
    await _ref.read(appleMlDownloaderProvider).delete(model);
    final selected = _ref.read(selectedAppleMlModelIdProvider);
    if (selected == model.id) {
      await _ref.read(selectedAppleMlModelIdProvider.notifier).set(null);
    }
    final next = Map<String, AppleMlDownloadProgress>.from(state);
    next.remove(model.id);
    state = next;
    _ref.invalidate(appleMlInstalledIdsProvider);
    _ref.invalidate(connectionStatusProvider);
  }
}

final appleMlDownloadControllerProvider = StateNotifierProvider<
    AppleMlDownloadController, Map<String, AppleMlDownloadProgress>>((ref) {
  return AppleMlDownloadController(ref);
});
