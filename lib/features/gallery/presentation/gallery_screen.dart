import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/glass_tokens.dart';
import '../../../core/models/session.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/utils/image_storage.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/adaptive_scaffold.dart';

const _uuid = Uuid();

enum GallerySortMode { date, session, favorites }

final galleryImagesProvider = FutureProvider<List<GeneratedImage>>((ref) async {
  final db = await ref.read(databaseProvider.future);
  final results = await db.query('generated_images', orderBy: 'created_at DESC');
  return results.map((e) => GeneratedImage.fromMap(e)).toList();
});

final galleryFoldersProvider = FutureProvider<List<Folder>>((ref) async {
  final db = await ref.read(databaseProvider.future);
  final results = await db.query('folders', orderBy: 'created_at DESC');
  return results.map((e) => Folder.fromMap(e)).toList();
});

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  GallerySortMode _sortMode = GallerySortMode.date;
  int _columns = 3;
  String? _activeFolderId; // null = show all + folders

  @override
  Widget build(BuildContext context) {
    final images = ref.watch(galleryImagesProvider);
    final folders = ref.watch(galleryFoldersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > GlassTokens.tabletMinWidth;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.gradientDarkStart, AppColors.gradientDarkEnd]
              : [AppColors.gradientLightStart, AppColors.gradientLightEnd],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            ScreenHeader(
              title: _activeFolderId != null ? 'Folder' : 'Gallery',
              actions: [
                if (_activeFolderId != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _activeFolderId = null),
                  ),
                // Add folder
                if (_activeFolderId == null)
                  IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => _showCreateFolderDialog(),
                  ),
                // Column toggle
                IconButton(
                  icon: Icon(_columns == 2 ? Icons.grid_on : Icons.grid_view),
                  onPressed: () => setState(() => _columns = _columns == 2 ? 3 : (_columns == 3 ? 4 : 2)),
                ),
                // Sort
                PopupMenuButton<GallerySortMode>(
                  icon: const Icon(Icons.sort),
                  onSelected: (mode) => setState(() => _sortMode = mode),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: GallerySortMode.date, child: Text('By Date')),
                    const PopupMenuItem(value: GallerySortMode.session, child: Text('By Session')),
                    const PopupMenuItem(value: GallerySortMode.favorites, child: Text('Favorites First')),
                  ],
                ),
              ],
            ),
            // Grid
            Expanded(
              child: images.when(
                data: (allImages) {
                  final folderList = folders.valueOrNull ?? [];

                  // If inside a folder, show only that folder's images
                  if (_activeFolderId != null) {
                    final folderImages = allImages
                        .where((img) => img.folderId == _activeFolderId)
                        .toList();
                    return _buildImageGrid(folderImages, isWide);
                  }

                  // Show folders + unfiled images
                  final unfiledImages = allImages
                      .where((img) => img.folderId == null)
                      .toList();

                  if (folderList.isEmpty && allImages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_outlined, size: 64,
                            color: AppColors.primary.withValues(alpha: 0.4)),
                          const SizedBox(height: GlassTokens.spacingLg),
                          Text('No images yet', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: GlassTokens.spacingSm),
                          Text('Generated images will appear here',
                            style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(GlassTokens.spacingLg),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isWide ? _columns + 1 : _columns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: folderList.length + _sortImages(unfiledImages).length,
                    itemBuilder: (context, index) {
                      if (index < folderList.length) {
                        final folder = folderList[index];
                        // Get cover images for this folder (up to 4)
                        final coverImages = allImages
                            .where((img) => img.folderId == folder.id)
                            .take(4)
                            .toList();
                        return _FolderTile(
                          folder: folder,
                          coverImages: coverImages,
                          onTap: () => setState(() => _activeFolderId = folder.id),
                          onLongPress: () => _showFolderOptions(folder),
                        );
                      }
                      final imgIndex = index - folderList.length;
                      final sorted = _sortImages(unfiledImages);
                      return _GalleryTile(
                        image: sorted[imgIndex],
                        onTap: () => _showImageDetail(context, sorted[imgIndex]),
                        onFavorite: () => _toggleFavorite(sorted[imgIndex]),
                        onMoveToFolder: () => _showMoveToFolder(sorted[imgIndex]),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<GeneratedImage> images, bool isWide) {
    final sorted = _sortImages(images);
    if (sorted.isEmpty) {
      return const Center(child: Text('No images in this folder'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(GlassTokens.spacingLg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? _columns + 1 : _columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) => _GalleryTile(
        image: sorted[index],
        onTap: () => _showImageDetail(context, sorted[index]),
        onFavorite: () => _toggleFavorite(sorted[index]),
        onMoveToFolder: () => _showMoveToFolder(sorted[index]),
      ),
    );
  }

  List<GeneratedImage> _sortImages(List<GeneratedImage> images) {
    final sorted = List<GeneratedImage>.from(images);
    switch (_sortMode) {
      case GallerySortMode.date:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case GallerySortMode.session:
        sorted.sort((a, b) => a.sessionId.compareTo(b.sessionId));
      case GallerySortMode.favorites:
        sorted.sort((a, b) {
          if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
          return b.createdAt.compareTo(a.createdAt);
        });
    }
    return sorted;
  }

  Future<void> _toggleFavorite(GeneratedImage image) async {
    final db = await ref.read(databaseProvider.future);
    await db.update(
      'generated_images',
      {'is_favorite': image.isFavorite ? 0 : 1},
      where: 'id = ?',
      whereArgs: [image.id],
    );
    ref.invalidate(galleryImagesProvider);
  }

  void _showImageDetail(BuildContext context, GeneratedImage image) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ImageDetailScreen(image: image),
      ),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    String draftName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextFormField(
          autofocus: true,
          initialValue: '',
          decoration: const InputDecoration(hintText: 'Folder name'),
          onChanged: (value) => draftName = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, draftName.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final db = await ref.read(databaseProvider.future);
    await db.insert('folders', Folder(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    ).toMap());
    ref.invalidate(galleryFoldersProvider);
  }

  Future<void> _showFolderOptions(Folder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'rename') {
      String draftName = folder.name;
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename Folder'),
          content: TextFormField(
            initialValue: folder.name,
            autofocus: true,
            onChanged: (value) => draftName = value,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, draftName.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;

      final db = await ref.read(databaseProvider.future);
      await db.update('folders', {'name': name},
          where: 'id = ?', whereArgs: [folder.id]);
      ref.invalidate(galleryFoldersProvider);
    } else if (action == 'delete') {
      final db = await ref.read(databaseProvider.future);
      // Un-assign images from this folder
      await db.update('generated_images', {'folder_id': null},
          where: 'folder_id = ?', whereArgs: [folder.id]);
      await db.delete('folders', where: 'id = ?', whereArgs: [folder.id]);
      ref.invalidate(galleryFoldersProvider);
      ref.invalidate(galleryImagesProvider);
    }
  }

  Future<void> _showMoveToFolder(GeneratedImage image) async {
    final folders = ref.read(galleryFoldersProvider).valueOrNull ?? [];
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a folder first')),
      );
      return;
    }

    final folderId = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Move to Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (image.folderId != null)
              ListTile(
                leading: const Icon(Icons.folder_off),
                title: const Text('Remove from folder'),
                onTap: () => Navigator.pop(ctx, '__none__'),
              ),
            ...folders.map((f) => ListTile(
              leading: Icon(Icons.folder, color: Color(f.color)),
              title: Text(f.name),
              selected: f.id == image.folderId,
              onTap: () => Navigator.pop(ctx, f.id),
            )),
          ],
        ),
      ),
    );

    if (folderId == null) return;

    final db = await ref.read(databaseProvider.future);
    await db.update(
      'generated_images',
      {'folder_id': folderId == '__none__' ? null : folderId},
      where: 'id = ?',
      whereArgs: [image.id],
    );
    ref.invalidate(galleryImagesProvider);
  }
}

class _FolderTile extends StatelessWidget {
  final Folder folder;
  final List<GeneratedImage> coverImages;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FolderTile({
    required this.folder,
    required this.coverImages,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            border: Border.all(
              color: Color(folder.color).withValues(alpha: 0.3),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover image mosaic
              if (coverImages.isNotEmpty)
                _buildCoverMosaic()
              else
                Center(
                  child: Icon(Icons.folder, size: 36, color: Color(folder.color)),
                ),
              // Folder name overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Text(
                    folder.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Image count badge
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${coverImages.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverMosaic() {
    if (coverImages.length == 1) {
      return Image.file(
        ImageStorage.resolveFileSync(coverImages[0].filePath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(),
      );
    }
    // 2x2 grid of cover images
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: coverImages.isNotEmpty
                    ? Image.file(ImageStorage.resolveFileSync(coverImages[0].filePath), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox())
                    : const SizedBox(),
              ),
              if (coverImages.length > 1)
                Expanded(
                  child: Image.file(ImageStorage.resolveFileSync(coverImages[1].filePath), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
            ],
          ),
        ),
        if (coverImages.length > 2)
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Image.file(ImageStorage.resolveFileSync(coverImages[2].filePath), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
                if (coverImages.length > 3)
                  Expanded(
                    child: Image.file(ImageStorage.resolveFileSync(coverImages[3].filePath), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final GeneratedImage image;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onMoveToFolder;

  const _GalleryTile({
    required this.image,
    required this.onTap,
    required this.onFavorite,
    required this.onMoveToFolder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    image.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: image.isFavorite ? Colors.red : null,
                  ),
                  title: Text(image.isFavorite ? 'Remove Favorite' : 'Favorite'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onFavorite();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('Move to Folder'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onMoveToFolder();
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              ImageStorage.resolveFileSync(image.filePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.cardLight,
                child: const Icon(Icons.broken_image),
              ),
            ),
            if (image.isFavorite)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.favorite, size: 18, color: Colors.red.shade400),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageDetailScreen extends StatefulWidget {
  final GeneratedImage image;

  const _ImageDetailScreen({required this.image});

  @override
  State<_ImageDetailScreen> createState() => _ImageDetailScreenState();
}

class _ImageDetailScreenState extends State<_ImageDetailScreen> {
  int _imageVersion = 0; // used to force image reload after editing

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final file = ImageStorage.resolveFileSync(widget.image.filePath);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Image Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Image',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProImageEditor.file(
                    file,
                    callbacks: ProImageEditorCallbacks(
                      onImageEditingComplete: (Uint8List bytes) async {
                        await file.writeAsBytes(bytes);
                        Navigator.pop(context);
                        if (mounted) {
                          setState(() {
                            PaintingBinding.instance.imageCache.clear();
                            _imageVersion++;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Image saved successfully')),
                          );
                        }
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Share functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: () {
              // Save to photos
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            InteractiveViewer(
              child: Image.file(
                file,
                key: ValueKey(_imageVersion),
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
            // Metadata
            Padding(
              padding: const EdgeInsets.all(GlassTokens.spacingLg),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Generation Details',
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: GlassTokens.spacingMd),
                    _MetadataRow('Prompt', widget.image.prompt),
                    if (widget.image.negativePrompt.isNotEmpty)
                      _MetadataRow('Negative', widget.image.negativePrompt),
                    if (widget.image.modelName != null)
                      _MetadataRow('Model', widget.image.modelName!),
                    if (widget.image.samplerName != null)
                      _MetadataRow('Sampler', widget.image.samplerName!),
                    if (widget.image.steps != null)
                      _MetadataRow('Steps', '${widget.image.steps}'),
                    if (widget.image.cfgScale != null)
                      _MetadataRow('CFG Scale', '${widget.image.cfgScale}'),
                    if (widget.image.seed != null)
                      _MetadataRow('Seed', '${widget.image.seed}'),
                    if (widget.image.width != null && widget.image.height != null)
                      _MetadataRow('Size', '${widget.image.width}×${widget.image.height}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _MetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
              style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
