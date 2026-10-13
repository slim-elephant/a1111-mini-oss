import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../utils/image_storage.dart';

/// Seeds sample sessions on first launch and auto-deletes them after 6 hours.
class SampleDataSeeder {
  static const _uuid = Uuid();
  static const _seededKey = 'sample_data_seeded';
  static const _seededAtKey = 'sample_data_seeded_at';
  static const _samplePrefix = 'sample_session_';
  static const _expiryDuration = Duration(hours: 6);

  static const _sampleSessions = <_SampleDef>[
    _SampleDef(
      title: 'Sample Session – Magical Library',
      asset: 'assets/samples/sample_library.png',
      prompt: 'A tiny magical library inside a tree, glowing mushrooms, floating books, warm lantern light, whimsical fantasy, ultra detailed, cozy mood',
      steps: 20,
      cfgScale: 7.0,
      seed: 3209438649,
      model: 'Mac',
    ),
    _SampleDef(
      title: 'Sample Session – Butterfly Closeup',
      asset: 'assets/samples/sample_butterfly.png',
      prompt: 'Butterfly closeup',
      steps: 20,
      cfgScale: 7.0,
      seed: 3942138243,
      model: 'Mac',
    ),
    _SampleDef(
      title: 'Sample Session – Sports Cars',
      asset: 'assets/samples/sample_cars.png',
      prompt: 'Sports Cars',
      steps: 20,
      cfgScale: 7.5,
      seed: 4196700468,
      model: 'Mac',
    ),
  ];

  /// Call once at app startup. Seeds on first launch, cleans up after 6 hours.
  static Future<void> seedIfNeeded(Database db) async {
    final seededRow = await db.query(
      'app_settings',
      where: "key = ?",
      whereArgs: [_seededKey],
    );

    if (seededRow.isNotEmpty) {
      // Already seeded — check if it's time to delete
      await _deleteIfExpired(db);
      return;
    }

    // First launch — seed samples
    final docs = await ImageStorage.docsPath;
    final now = DateTime.now();

    for (var i = 0; i < _sampleSessions.length; i++) {
      final sample = _sampleSessions[i];
      final sessionId = '$_samplePrefix${_uuid.v4()}';
      final userMsgId = _uuid.v4();
      final assistantMsgId = _uuid.v4();
      final imageId = _uuid.v4();
      final createdAt = now.subtract(Duration(minutes: _sampleSessions.length - i));

      // Copy asset image to documents
      String? relativePath;
      try {
        final bytes = await rootBundle.load(sample.asset);
        final imageDir = p.join(docs, 'generated_images', sessionId);
        await Directory(imageDir).create(recursive: true);
        final fileName = '${_uuid.v4()}.png';
        final filePath = p.join(imageDir, fileName);
        await File(filePath).writeAsBytes(bytes.buffer.asUint8List());
        relativePath = p.relative(filePath, from: docs);
      } catch (_) {
        continue;
      }

      final params = '{"sampler_name":"Euler a","steps":${sample.steps},"cfg_scale":${sample.cfgScale},"width":512,"height":512}';

      await db.insert('sessions', {
        'id': sessionId,
        'title': sample.title,
        'thumbnail_path': relativePath,
        'generation_count': 1,
        'is_favorite': 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': createdAt.toIso8601String(),
      });

      await db.insert('session_messages', {
        'id': userMsgId,
        'session_id': sessionId,
        'role': 'user',
        'prompt': sample.prompt,
        'negative_prompt': '',
        'parameters': params,
        'image_paths': '[]',
        'created_at': createdAt.toIso8601String(),
      });

      await db.insert('session_messages', {
        'id': assistantMsgId,
        'session_id': sessionId,
        'role': 'assistant',
        'prompt': sample.prompt,
        'negative_prompt': '',
        'parameters': params,
        'image_paths': '["$relativePath"]',
        'seed': sample.seed,
        'model_name': sample.model,
        'created_at': createdAt.add(const Duration(seconds: 10)).toIso8601String(),
      });

      await db.insert('generated_images', {
        'id': imageId,
        'session_id': sessionId,
        'message_id': assistantMsgId,
        'file_path': relativePath,
        'prompt': sample.prompt,
        'negative_prompt': '',
        'model_name': sample.model,
        'sampler_name': 'Euler a',
        'steps': sample.steps,
        'cfg_scale': sample.cfgScale,
        'seed': sample.seed,
        'width': 512,
        'height': 512,
        'is_favorite': 0,
        'created_at': createdAt.add(const Duration(seconds: 10)).toIso8601String(),
      });
    }

    await db.insert('app_settings', {'key': _seededKey, 'value': 'true'});
    await db.insert('app_settings', {
      'key': _seededAtKey,
      'value': now.toIso8601String(),
    });
  }

  /// Deletes sample sessions if 6 hours have passed since seeding.
  static Future<void> _deleteIfExpired(Database db) async {
    final row = await db.query(
      'app_settings',
      where: "key = ?",
      whereArgs: [_seededAtKey],
    );
    if (row.isEmpty) return; // already cleaned up

    final seededAt = DateTime.tryParse(row.first['value'] as String? ?? '');
    if (seededAt == null) return;

    if (DateTime.now().difference(seededAt) < _expiryDuration) return;

    // Time to clean up — find all sample sessions by ID prefix
    final sessions = await db.query(
      'sessions',
      columns: ['id'],
      where: "id LIKE ?",
      whereArgs: ['$_samplePrefix%'],
    );

    final docs = await ImageStorage.docsPath;
    for (final s in sessions) {
      final sid = s['id'] as String;
      await db.delete('generated_images', where: 'session_id = ?', whereArgs: [sid]);
      await db.delete('session_messages', where: 'session_id = ?', whereArgs: [sid]);
      await db.delete('sessions', where: 'id = ?', whereArgs: [sid]);
      // Remove image directory
      final imageDir = Directory(p.join(docs, 'generated_images', sid));
      if (await imageDir.exists()) {
        await imageDir.delete(recursive: true);
      }
    }

    // Remove the seeded_at key so we don't check again
    await db.delete('app_settings', where: "key = ?", whereArgs: [_seededAtKey]);
  }
}

class _SampleDef {
  final String title;
  final String asset;
  final String prompt;
  final int steps;
  final double cfgScale;
  final int seed;
  final String model;

  const _SampleDef({
    required this.title,
    required this.asset,
    required this.prompt,
    required this.steps,
    required this.cfgScale,
    required this.seed,
    this.model = '',
  });
}
