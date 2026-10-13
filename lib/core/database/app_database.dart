import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'sample_data_seeder.dart';

class AppDatabase {
  static Database? _db;
  static const _dbName = 'a1111_mini.db';
  static const _dbVersion = 6;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    // Seed sample sessions on first launch
    // await SampleDataSeeder.seedIfNeeded(_db!);
    return _db!;
  }

  static Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL DEFAULT 7860,
        provider TEXT NOT NULL DEFAULT 'a1111',
        auth_token TEXT,
        is_active INTEGER NOT NULL DEFAULT 0,
        last_connected_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'auto_awesome',
        color INTEGER NOT NULL DEFAULT 0xFF3B82F6,
        positive_prompt TEXT NOT NULL DEFAULT '',
        negative_prompt TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE personas (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        avatar_path TEXT,
        profile_id TEXT,
        model_name TEXT,
        lora_configs TEXT NOT NULL DEFAULT '[]',
        style_names TEXT NOT NULL DEFAULT '[]',
        scheduler TEXT,
        distilled_cfg_scale REAL NOT NULL DEFAULT 3.5,
        vae TEXT NOT NULL DEFAULT 'Automatic',
        clip_skip INTEGER,
        sampler_name TEXT NOT NULL DEFAULT 'Euler a',
        steps INTEGER NOT NULL DEFAULT 20,
        cfg_scale REAL NOT NULL DEFAULT 7.0,
        seed INTEGER NOT NULL DEFAULT -1,
        width INTEGER NOT NULL DEFAULT 512,
        height INTEGER NOT NULL DEFAULT 512,
        restore_faces INTEGER NOT NULL DEFAULT 0,
        hires_fix INTEGER NOT NULL DEFAULT 0,
        hires_scale REAL NOT NULL DEFAULT 1.5,
        hires_steps INTEGER NOT NULL DEFAULT 0,
        hires_denoising REAL NOT NULL DEFAULT 0.5,
        hires_upscaler TEXT NOT NULL DEFAULT 'Latent',
        controlnet_units TEXT NOT NULL DEFAULT '[]',
        denoising_strength REAL NOT NULL DEFAULT 0.7,
        created_at TEXT NOT NULL,
        FOREIGN KEY (profile_id) REFERENCES ai_profiles(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT,
        icon TEXT NOT NULL DEFAULT 'folder',
        color INTEGER NOT NULL DEFAULT 0xFF3B82F6,
        created_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES folders(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        server_id TEXT,
        persona_id TEXT,
        folder_id TEXT,
        thumbnail_path TEXT,
        generation_count INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (server_id) REFERENCES servers(id) ON DELETE SET NULL,
        FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE SET NULL,
        FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE session_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        prompt TEXT NOT NULL DEFAULT '',
        negative_prompt TEXT NOT NULL DEFAULT '',
        parameters TEXT NOT NULL DEFAULT '{}',
        image_paths TEXT NOT NULL DEFAULT '[]',
        seed INTEGER,
        model_name TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE generated_images (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        thumbnail_path TEXT,
        prompt TEXT NOT NULL DEFAULT '',
        negative_prompt TEXT NOT NULL DEFAULT '',
        model_name TEXT,
        lora_configs TEXT NOT NULL DEFAULT '[]',
        sampler_name TEXT,
        steps INTEGER,
        cfg_scale REAL,
        seed INTEGER,
        width INTEGER,
        height INTEGER,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (message_id) REFERENCES session_messages(id) ON DELETE CASCADE,
        FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_sessions_created ON sessions(created_at DESC)');
    await db.execute('CREATE INDEX idx_sessions_folder ON sessions(folder_id)');
    await db.execute('CREATE INDEX idx_messages_session ON session_messages(session_id, created_at ASC)');
    await db.execute('CREATE INDEX idx_images_session ON generated_images(session_id)');
    await db.execute('CREATE INDEX idx_images_folder ON generated_images(folder_id)');
    await db.execute('CREATE INDEX idx_images_favorite ON generated_images(is_favorite)');

    // Seed default AI profiles
    final now = DateTime.now().toIso8601String();
    await db.insert('ai_profiles', {
      'id': 'preset_photorealistic',
      'name': 'Photorealistic',
      'icon': 'camera',
      'color': 0xFF10B981,
      'positive_prompt': 'photorealistic, hyperdetailed, 8k uhd, dslr, high quality, film grain',
      'negative_prompt': 'cartoon, anime, drawing, painting, sketch, illustration, low quality, blurry, deformed',
      'created_at': now,
    });
    await db.insert('ai_profiles', {
      'id': 'preset_anime',
      'name': 'Anime',
      'icon': 'palette',
      'color': 0xFFEC4899,
      'positive_prompt': 'masterpiece, best quality, anime style, detailed, vibrant colors',
      'negative_prompt': 'photorealistic, 3d render, low quality, worst quality, blurry, watermark',
      'created_at': now,
    });
    await db.insert('ai_profiles', {
      'id': 'preset_digital_art',
      'name': 'Digital Art',
      'icon': 'brush',
      'color': 0xFF8B5CF6,
      'positive_prompt': 'digital art, concept art, highly detailed, artstation, trending',
      'negative_prompt': 'photo, photograph, low quality, blurry, noisy, watermark, text',
      'created_at': now,
    });
    await _seedOnDevicePersonas(db);
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Helper to add column safely if it doesn't exist (useful during development when schemas change)
      Future<void> addColumnSafely(String table, String column, String typeAndConstraints) async {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final hasColumn = columns.any((col) => col['name'] == column);
        if (!hasColumn) {
          await db.execute('ALTER TABLE $table ADD COLUMN $column $typeAndConstraints');
        }
      }

      await addColumnSafely('personas', 'style_names', "TEXT NOT NULL DEFAULT '[]'");
      await addColumnSafely('personas', 'scheduler', "TEXT");
      await addColumnSafely('personas', 'distilled_cfg_scale', "REAL NOT NULL DEFAULT 3.5");
      await addColumnSafely('personas', 'vae', "TEXT NOT NULL DEFAULT 'Automatic'");
      await addColumnSafely('personas', 'clip_skip', "INTEGER");
      await addColumnSafely('personas', 'hires_scale', "REAL NOT NULL DEFAULT 1.5");
      await addColumnSafely('personas', 'hires_steps', "INTEGER NOT NULL DEFAULT 0");
      await addColumnSafely('personas', 'hires_denoising', "REAL NOT NULL DEFAULT 0.5");
      await addColumnSafely('personas', 'hires_upscaler', "TEXT NOT NULL DEFAULT 'Latent'");
      await addColumnSafely('personas', 'controlnet_units', "TEXT NOT NULL DEFAULT '[]'");
    }
    if (oldVersion < 3) {
      Future<void> addColumnSafely(String table, String column, String typeAndConstraints) async {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final hasColumn = columns.any((col) => col['name'] == column);
        if (!hasColumn) {
          await db.execute('ALTER TABLE $table ADD COLUMN $column $typeAndConstraints');
        }
      }

      await addColumnSafely('servers', 'provider', "TEXT NOT NULL DEFAULT 'a1111'");
    }
    if (oldVersion < 4) {
      Future<void> addColumnSafely(String table, String column, String typeAndConstraints) async {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final hasColumn = columns.any((col) => col['name'] == column);
        if (!hasColumn) {
          await db.execute('ALTER TABLE $table ADD COLUMN $column $typeAndConstraints');
        }
      }

      await addColumnSafely('servers', 'auth_token', 'TEXT');
    }
    if (oldVersion < 6) {
      await _seedOnDevicePersonas(db);
    }
  }

  /// On-device SDXL looks wrong at A1111's 512 / CFG 7 defaults. These personas
  /// set 768, 30 steps, CFG 5, and a style profile in one tap.
  static Future<void> _seedOnDevicePersonas(Database db) async {
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'ai_profiles',
      {
        'id': 'preset_cinematic',
        'name': 'Cinematic',
        'icon': 'movie',
        'color': 0xFFF59E0B,
        'positive_prompt':
            'cinematic still, dramatic lighting, shallow depth of field, film grain, detailed, 35mm',
        'negative_prompt':
            'cartoon, anime, low quality, blurry, deformed, watermark, text',
        'created_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    Future<void> persona({
      required String id,
      required String name,
      required String description,
      required String profileId,
      required int steps,
      required double cfg,
    }) async {
      await db.insert(
        'personas',
        {
          'id': id,
          'name': name,
          'description': description,
          'profile_id': profileId,
          'lora_configs': '[]',
          'style_names': '[]',
          'sampler_name': 'DPM-Solver++',
          'steps': steps,
          'cfg_scale': cfg,
          'seed': -1,
          'width': 768,
          'height': 768,
          'restore_faces': 0,
          'hires_fix': 0,
          'denoising_strength': 0.7,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await persona(
      id: 'preset_on_device_photo',
      name: 'On-device Photo',
      description:
          'SDXL on this iPhone: 768×768, 30 steps, CFG 5, photoreal style. One-time Neural Engine setup already happened if the model is installed.',
      profileId: 'preset_photorealistic',
      steps: 30,
      cfg: 5,
    );
    await persona(
      id: 'preset_on_device_cinema',
      name: 'On-device Cinema',
      description:
          'SDXL on this iPhone with cinematic lighting. 768×768, 30 steps, CFG 5.',
      profileId: 'preset_cinematic',
      steps: 30,
      cfg: 5,
    );
    await persona(
      id: 'preset_on_device_anime',
      name: 'On-device Anime',
      description:
          'SDXL on this iPhone, anime profile. 768×768, 28 steps, CFG 6.',
      profileId: 'preset_anime',
      steps: 28,
      cfg: 6,
    );
  }
}
