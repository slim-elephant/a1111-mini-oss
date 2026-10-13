import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ImageStorage {
  static const _uuid = Uuid();
  static String? _basePath;
  static String? _docsPath;

  static Future<String> get docsPath async {
    if (_docsPath != null) return _docsPath!;
    final dir = await getApplicationDocumentsDirectory();
    _docsPath = dir.path;
    return _docsPath!;
  }

  static Future<String> get basePath async {
    if (_basePath != null) return _basePath!;
    final docs = await docsPath;
    _basePath = p.join(docs, 'generated_images');
    await Directory(_basePath!).create(recursive: true);
    return _basePath!;
  }

  /// Resolve a stored path (relative or legacy absolute) to a File.
  /// Stored paths are relative to the app documents directory.
  /// Legacy absolute paths are also handled for backward compatibility.
  static Future<File> resolveFile(String storedPath) async {
    // If the file exists at the stored path, it's a legacy absolute path
    final absoluteFile = File(storedPath);
    if (absoluteFile.existsSync()) return absoluteFile;

    // Otherwise treat as relative to documents directory
    final docs = await docsPath;
    return File(p.join(docs, storedPath));
  }

  /// Synchronous resolve using cached docsPath (call after at least one async resolve).
  static File resolveFileSync(String storedPath) {
    if (_docsPath == null) return File(storedPath);
    // Check if it's already absolute and exists
    if (p.isAbsolute(storedPath) && File(storedPath).existsSync()) {
      return File(storedPath);
    }
    return File(p.join(_docsPath!, storedPath));
  }

  /// Decode a base64 image and save it to the app sandbox.
  /// Returns a relative path (relative to documents directory).
  static Future<String> saveBase64Image(
    String base64Data, {
    String? sessionId,
  }) async {
    final base = await basePath;
    final sessionDir = sessionId != null ? p.join(base, sessionId) : base;
    await Directory(sessionDir).create(recursive: true);

    final fileName = '${_uuid.v4()}.png';
    final filePath = p.join(sessionDir, fileName);
    final bytes = base64Decode(base64Data);
    await File(filePath).writeAsBytes(bytes);

    // Return relative path for storage in DB
    final docs = await docsPath;
    return p.relative(filePath, from: docs);
  }

  /// Copy an existing PNG into the sandbox. Returns a documents-relative path.
  static Future<String> savePngFile(
    File source, {
    String? sessionId,
  }) async {
    final base = await basePath;
    final sessionDir = sessionId != null ? p.join(base, sessionId) : base;
    await Directory(sessionDir).create(recursive: true);

    final fileName = '${_uuid.v4()}.png';
    final filePath = p.join(sessionDir, fileName);
    await source.copy(filePath);

    final docs = await docsPath;
    return p.relative(filePath, from: docs);
  }

  /// Save multiple base64 images. Returns list of local file paths.
  static Future<List<String>> saveBase64Images(
    List<String> base64Images, {
    String? sessionId,
  }) async {
    final paths = <String>[];
    for (final img in base64Images) {
      final path = await saveBase64Image(img, sessionId: sessionId);
      paths.add(path);
    }
    return paths;
  }

  /// Delete a generated image file (handles both relative and absolute paths).
  static Future<void> deleteImage(String filePath) async {
    final file = await resolveFile(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Delete all images for a session.
  static Future<void> deleteSessionImages(String sessionId) async {
    final base = await basePath;
    final dir = Directory(p.join(base, sessionId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Get total storage used by generated images.
  static Future<int> getTotalStorageBytes() async {
    final base = await basePath;
    final dir = Directory(base);
    if (!await dir.exists()) return 0;

    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
