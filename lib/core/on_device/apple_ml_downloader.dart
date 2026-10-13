import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'apple_ml_download_platform.dart';
import 'apple_ml_models.dart';

const kAppleMlReadyFile = '.ready';

class AppleMlInstallInfo {
  final String modelId;
  final String resourcesPath;
  final int bytes;

  const AppleMlInstallInfo({
    required this.modelId,
    required this.resourcesPath,
    required this.bytes,
  });

  factory AppleMlInstallInfo.fromJson(Map<String, dynamic> json) {
    return AppleMlInstallInfo(
      modelId: json['modelId'] as String? ?? '',
      resourcesPath: json['resourcesPath'] as String? ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'modelId': modelId,
        'resourcesPath': resourcesPath,
        'bytes': bytes,
      };
}

class AppleMlDownloadProgress {
  final String modelId;
  final String stage;
  final int receivedBytes;
  final int totalBytes;
  final int fileIndex;
  final int fileCount;
  final String? currentFile;
  final String? error;
  final bool cancelRequested;

  const AppleMlDownloadProgress({
    required this.modelId,
    this.stage = 'idle',
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.fileIndex = 0,
    this.fileCount = 0,
    this.currentFile,
    this.error,
    this.cancelRequested = false,
  });

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  AppleMlDownloadProgress copyWith({
    String? stage,
    int? receivedBytes,
    int? totalBytes,
    int? fileIndex,
    int? fileCount,
    String? currentFile,
    String? error,
    bool? cancelRequested,
  }) =>
      AppleMlDownloadProgress(
        modelId: modelId,
        stage: stage ?? this.stage,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        fileIndex: fileIndex ?? this.fileIndex,
        fileCount: fileCount ?? this.fileCount,
        currentFile: currentFile ?? this.currentFile,
        error: error,
        cancelRequested: cancelRequested ?? this.cancelRequested,
      );
}

class AppleMlDownloader {
  final Dio _dio;
  final Future<Directory> Function() _supportDir;
  final AppleMlDownloadPlatform _native;
  CancelToken? _cancelToken;
  String? _activeNativeJobId;

  AppleMlDownloader({
    Dio? dio,
    Future<Directory> Function()? supportDir,
    AppleMlDownloadPlatform? native,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                followRedirects: true,
                maxRedirects: 8,
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 90),
                headers: const {'User-Agent': 'A1111-Mini'},
              ),
            ),
        _supportDir = supportDir ?? getApplicationSupportDirectory,
        _native = native ?? AppleMlDownloadPlatform.instance;

  Future<Directory> modelsRoot() async {
    final support = await _supportDir();
    final dir = Directory(p.join(support.path, 'apple_ml_models'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelDir(AppleMlCatalogModel model) async {
    final root = await modelsRoot();
    return Directory(p.join(root.path, model.id));
  }

  Future<File> readyFile(AppleMlCatalogModel model) async {
    final dir = await modelDir(model);
    return File(p.join(dir.path, kAppleMlReadyFile));
  }

  Future<bool> isInstalled(AppleMlCatalogModel model) async {
    final info = await installInfo(model);
    if (info == null) return false;
    final textEncoder = Directory(p.join(info.resourcesPath, 'TextEncoder.mlmodelc'));
    final textEncoder2 =
        Directory(p.join(info.resourcesPath, 'TextEncoder2.mlmodelc'));
    final vocab = File(p.join(info.resourcesPath, 'vocab.json'));
    final merges = File(p.join(info.resourcesPath, 'merges.txt'));
    if (!await vocab.exists() || !await merges.exists()) return false;
    if (model.isSdxl) return textEncoder2.exists();
    return textEncoder.exists();
  }

  Future<AppleMlInstallInfo?> installInfo(AppleMlCatalogModel model) async {
    final file = await readyFile(model);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final info = AppleMlInstallInfo.fromJson(json);
      if (info.resourcesPath.isEmpty) return null;
      if (!await Directory(info.resourcesPath).exists()) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> installedIds() async {
    final ids = <String>{};
    for (final model in AppleMlCatalog.models) {
      if (await isInstalled(model)) ids.add(model.id);
    }
    return ids;
  }

  void cancel() {
    _cancelToken?.cancel('Download cancelled');
    final jobId = _activeNativeJobId;
    if (jobId != null) {
      _native.cancel(jobId);
    }
  }

  Future<AppleMlInstallInfo> download(
    AppleMlCatalogModel model, {
    required void Function(AppleMlDownloadProgress progress) onProgress,
  }) async {
    _cancelToken = CancelToken();
    final dir = await modelDir(model);
    await dir.create(recursive: true);

    onProgress(AppleMlDownloadProgress(
      modelId: model.id,
      stage: 'listing',
    ));

    final files = await listDownloadFiles(model);
    if (files.isEmpty) {
      throw Exception('No Core ML files found in ${model.hfRepo}');
    }
    final total = files.fold<int>(0, (sum, f) => sum + f.size);

    final useNative = !kIsWeb &&
        Platform.isIOS &&
        await _native.isAvailable();
    if (useNative) {
      return _downloadNative(
        model: model,
        dir: dir,
        files: files,
        total: total,
        onProgress: onProgress,
      );
    }

    var received = 0;

    for (var i = 0; i < files.length; i++) {
      if (_cancelToken?.isCancelled == true) {
        throw Exception('Download cancelled');
      }
      final file = files[i];
      onProgress(AppleMlDownloadProgress(
        modelId: model.id,
        stage: 'downloading',
        receivedBytes: received,
        totalBytes: total,
        fileIndex: i + 1,
        fileCount: files.length,
        currentFile: p.basename(file.path),
      ));

      final dest = File(p.join(dir.path, file.path));
      await dest.parent.create(recursive: true);
      if (await dest.exists()) {
        final existing = await dest.length();
        if (file.size > 0 && existing == file.size) {
          received += existing;
          continue;
        }
      }

      final url =
          'https://huggingface.co/${model.hfRepo}/resolve/main/${file.path}?download=true';
      final part = File('${dest.path}.part');
      var fileReceived = 0;
      await _dio.download(
        url,
        part.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (count, _) {
          fileReceived = count;
          onProgress(AppleMlDownloadProgress(
            modelId: model.id,
            stage: 'downloading',
            receivedBytes: received + count,
            totalBytes: total,
            fileIndex: i + 1,
            fileCount: files.length,
            currentFile: p.basename(file.path),
          ));
        },
      );
      if (await dest.exists()) await dest.delete();
      await part.rename(dest.path);
      received += fileReceived > 0 ? fileReceived : (file.size > 0 ? file.size : await dest.length());
    }

    return _finalize(model, dir.path, total, files.length, onProgress);
  }

  Future<AppleMlInstallInfo> _downloadNative({
    required AppleMlCatalogModel model,
    required Directory dir,
    required List<HfRemoteFile> files,
    required int total,
    required void Function(AppleMlDownloadProgress progress) onProgress,
  }) async {
    _activeNativeJobId = model.id;
    onProgress(AppleMlDownloadProgress(
      modelId: model.id,
      stage: 'downloading',
      totalBytes: total,
      fileCount: files.length,
    ));
    try {
      await _native.downloadJob(
        jobId: model.id,
        displayName: model.name,
        destRoot: dir.path,
        files: appleMlNativeDownloadFiles(hfRepo: model.hfRepo, files: files),
        onProgress: (payload) {
          onProgress(AppleMlDownloadProgress(
            modelId: model.id,
            stage: payload['stage'] as String? ?? 'downloading',
            receivedBytes: (payload['receivedBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (payload['totalBytes'] as num?)?.toInt() ?? total,
            fileIndex: (payload['fileIndex'] as num?)?.toInt() ?? 0,
            fileCount: (payload['fileCount'] as num?)?.toInt() ?? files.length,
            currentFile: payload['currentFile'] as String?,
          ));
        },
      );
    } catch (e) {
      _activeNativeJobId = null;
      if (e.toString().contains('cancelled')) {
        throw Exception('Download cancelled');
      }
      rethrow;
    }
    _activeNativeJobId = null;
    return _finalize(model, dir.path, total, files.length, onProgress);
  }

  Future<AppleMlInstallInfo> _finalize(
    AppleMlCatalogModel model,
    String dirPath,
    int total,
    int fileCount,
    void Function(AppleMlDownloadProgress progress) onProgress,
  ) async {
    onProgress(AppleMlDownloadProgress(
      modelId: model.id,
      stage: 'finalizing',
      receivedBytes: total,
      totalBytes: total,
      fileIndex: fileCount,
      fileCount: fileCount,
    ));

    final resourcesPath = await findResourcesDir(dirPath);
    if (resourcesPath == null) {
      throw Exception(
        'Downloaded files but could not find TextEncoder.mlmodelc / vocab.json',
      );
    }
    final info = AppleMlInstallInfo(
      modelId: model.id,
      resourcesPath: resourcesPath,
      bytes: total,
    );
    final ready = await readyFile(model);
    await ready.writeAsString(const JsonEncoder.withIndent('  ').convert(info.toJson()));
    onProgress(AppleMlDownloadProgress(
      modelId: model.id,
      stage: 'ready',
      receivedBytes: total,
      totalBytes: total,
      fileIndex: fileCount,
      fileCount: fileCount,
    ));
    return info;
  }

  Future<Map<String, dynamic>?> nativeActiveJob() {
    return _native.activeJob();
  }

  Future<AppleMlInstallInfo?> resumeIfNativeJobActive(
    void Function(AppleMlDownloadProgress progress) onProgress,
  ) async {
    final active = await _native.activeJob();
    if (active != null) {
      final id = active['jobId'] as String?;
      if (id == null || id.isEmpty) return null;
      final model = AppleMlCatalog.byId(id);
      if (model == null) return null;
      final dir = await modelDir(model);
      final total = (active['totalBytes'] as num?)?.toInt() ?? 0;
      final fileCount = (active['fileCount'] as num?)?.toInt() ?? 0;
      _activeNativeJobId = id;
      onProgress(AppleMlDownloadProgress(
        modelId: id,
        stage: active['stage'] as String? ?? 'downloading',
        receivedBytes: (active['receivedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: total,
        fileIndex: (active['fileIndex'] as num?)?.toInt() ?? 0,
        fileCount: fileCount,
        currentFile: active['currentFile'] as String?,
      ));
      try {
        final destRoot = await _native.attachJob(
          jobId: id,
          onProgress: (payload) {
            onProgress(AppleMlDownloadProgress(
              modelId: id,
              stage: payload['stage'] as String? ?? 'downloading',
              receivedBytes: (payload['receivedBytes'] as num?)?.toInt() ?? 0,
              totalBytes: (payload['totalBytes'] as num?)?.toInt() ?? total,
              fileIndex: (payload['fileIndex'] as num?)?.toInt() ?? 0,
              fileCount: (payload['fileCount'] as num?)?.toInt() ?? fileCount,
              currentFile: payload['currentFile'] as String?,
            ));
          },
        );
        _activeNativeJobId = null;
        return _finalize(
          model,
          destRoot.isEmpty ? dir.path : destRoot,
          total,
          fileCount,
          onProgress,
        );
      } catch (e) {
        _activeNativeJobId = null;
        if (e.toString().contains('cancelled')) return null;
        rethrow;
      }
    }

    for (final model in AppleMlCatalog.models) {
      if (await isInstalled(model)) continue;
      final dir = await modelDir(model);
      if (!await dir.exists()) continue;
      final resources = await findResourcesDir(dir.path);
      if (resources == null) continue;
      return _finalize(model, dir.path, 0, 0, onProgress);
    }
    return null;
  }

  Future<void> delete(AppleMlCatalogModel model) async {
    cancel();
    final dir = await modelDir(model);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<List<HfRemoteFile>> listDownloadFiles(AppleMlCatalogModel model) async {
    final entries = await listHfTree(model.hfRepo, model.treePrefix);
    return entries.where((e) => !appleMlShouldSkipRemotePath(e.path)).toList();
  }

  Future<List<HfRemoteFile>> listHfTree(String repo, String prefix) async {
    final files = <HfRemoteFile>[];
    String? cursor;
    for (var page = 0; page < 20; page++) {
      final params = <String, String>{
        'recursive': '1',
        'limit': '1000',
      };
      if (cursor != null) params['cursor'] = cursor;
      final url = Uri.https(
        'huggingface.co',
        '/api/models/$repo/tree/main/$prefix',
        params,
      );
      final response = await _dio.get<dynamic>(url.toString());
      final data = response.data;
      if (data is! List) break;
      if (data.isEmpty) break;
      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        if (map['type'] != 'file') continue;
        final path = map['path'] as String? ?? '';
        if (path.isEmpty) continue;
        final size = (map['size'] as num?)?.toInt() ??
            (map['lfs'] is Map
                ? ((map['lfs'] as Map)['size'] as num?)?.toInt()
                : null) ??
            0;
        files.add(HfRemoteFile(path: path, size: size));
      }
      if (data.length < 1000) break;
      final last = data.last;
      cursor = last is Map ? last['path'] as String? : null;
      if (cursor == null) break;
    }
    return files;
  }

  static Future<String?> findResourcesDir(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return null;
    Future<bool> looksLikeResources(Directory dir) async {
      final vocab = File(p.join(dir.path, 'vocab.json'));
      final merges = File(p.join(dir.path, 'merges.txt'));
      if (!await vocab.exists() || !await merges.exists()) return false;
      final te = Directory(p.join(dir.path, 'TextEncoder.mlmodelc'));
      final te2 = Directory(p.join(dir.path, 'TextEncoder2.mlmodelc'));
      return await te.exists() || await te2.exists();
    }

    if (await looksLikeResources(root)) return root.path;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory && entity.path.endsWith('.mlmodelc')) {
        final parent = entity.parent.path;
        if (await looksLikeResources(Directory(parent))) return parent;
      }
    }
    return null;
  }
}
