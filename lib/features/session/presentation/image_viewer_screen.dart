import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import '../../../core/utils/image_storage.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;
  int _imageVersion = 0; // used to force image reload after editing

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  Future<void> _shareImage() async {
    final path = widget.imagePaths[_currentIndex];
    final file = ImageStorage.resolveFileSync(path);
    if (!file.existsSync()) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _saveToPhotos() async {
    final path = widget.imagePaths[_currentIndex];
    final file = ImageStorage.resolveFileSync(path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    await ImageGallerySaverPlus.saveImage(bytes, quality: 100);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Photos')),
      );
    }
  }

  Future<void> _editImage() async {
    final path = widget.imagePaths[_currentIndex];
    final file = ImageStorage.resolveFileSync(path);
    if (!file.existsSync()) return;

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
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.imagePaths.length > 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image pager
              PageView.builder(
                controller: _pageController,
                itemCount: widget.imagePaths.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) {
                  final file = ImageStorage.resolveFileSync(
                    widget.imagePaths[index],
                  );
                  return InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: Center(
                      child: Image.file(
                        file,
                        key: ValueKey('${file.path}_$_imageVersion'),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Top bar
              if (_showControls)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 8,
                      right: 8,
                      bottom: 12,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        if (hasMultiple)
                          Text(
                            '${_currentIndex + 1} / ${widget.imagePaths.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const Spacer(),
                        const SizedBox(width: 48), // balance close button
                      ],
                    ),
                  ),
                ),

              // Bottom bar with actions
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 12,
                      left: 24,
                      right: 24,
                      top: 16,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ViewerAction(
                          icon: CupertinoIcons.pencil,
                          label: 'Edit',
                          onTap: _editImage,
                        ),
                        _ViewerAction(
                          icon: CupertinoIcons.share,
                          label: 'Share',
                          onTap: _shareImage,
                        ),
                        _ViewerAction(
                          icon: CupertinoIcons.arrow_down_to_line,
                          label: 'Save',
                          onTap: _saveToPhotos,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ViewerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
