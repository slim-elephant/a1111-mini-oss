import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlatformIcon extends StatelessWidget {
  final IconData material;
  final IconData cupertino;
  final double? size;
  final Color? color;

  const PlatformIcon({
    super.key,
    required this.material,
    required this.cupertino,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final useCupertino = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return Icon(
      useCupertino ? cupertino : material,
      size: size,
      color: color,
    );
  }
}
