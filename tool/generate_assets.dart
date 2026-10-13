// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

// Minimal PNG encoder for RGBA data
class PngEncoder {
  static Uint8List encode(int width, int height, Uint8List rgba) {
    final raw = <int>[];
    for (int y = 0; y < height; y++) {
      raw.add(0); // filter: none
      final rowStart = y * width * 4;
      raw.addAll(rgba.sublist(rowStart, rowStart + width * 4));
    }
    final compressed = zlib(Uint8List.fromList(raw));

    final out = BytesBuilder();
    // PNG signature
    out.add([137, 80, 78, 71, 13, 10, 26, 10]);
    // IHDR
    _writeChunk(out, 'IHDR', _ihdr(width, height));
    // IDAT
    _writeChunk(out, 'IDAT', compressed);
    // IEND
    _writeChunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  static Uint8List _ihdr(int w, int h) {
    final b = ByteData(13);
    b.setUint32(0, w);
    b.setUint32(4, h);
    b.setUint8(8, 8);  // bit depth
    b.setUint8(9, 6);  // RGBA
    b.setUint8(10, 0); // compression
    b.setUint8(11, 0); // filter
    b.setUint8(12, 0); // interlace
    return b.buffer.asUint8List();
  }

  static void _writeChunk(BytesBuilder out, String type, Uint8List data) {
    final typeBytes = type.codeUnits;
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);
    final crc = _crc32([...typeBytes, ...data]);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    out.add(crcBytes.buffer.asUint8List());
  }

  static Uint8List zlib(Uint8List data) => ZLibCodec().encode(data) as Uint8List;

  static int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

void main() {
  _generateIcon(1024, 'assets/icon/app_icon.png');
  _generateSplash(512, 'assets/splash/splash_logo.png');
  print('Assets generated!');
}

void _generateIcon(int size, String path) {
  final pixels = Uint8List(size * size * 4);

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final nx = x / size;
      final ny = y / size;

      // Background gradient: deep indigo to dark purple
      final r = (26 + (nx * 20)).round().clamp(0, 255);
      final g = (26 + (ny * 10)).round().clamp(0, 255);
      final b = (46 + (nx * 30 + ny * 20)).round().clamp(0, 255);

      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = 255;
    }
  }

  // Draw a stylized sparkle/star icon in the center
  final cx = size / 2;
  final cy = size / 2;
  final starRadius = size * 0.32;
  final innerRadius = size * 0.12;

  // Draw glow
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < starRadius * 1.5) {
        final glowIntensity = (1.0 - dist / (starRadius * 1.5)).clamp(0.0, 1.0);
        final i = (y * size + x) * 4;
        // Blue glow
        pixels[i] = (pixels[i] + (59 * glowIntensity * 0.4)).round().clamp(0, 255);
        pixels[i + 1] = (pixels[i + 1] + (130 * glowIntensity * 0.4)).round().clamp(0, 255);
        pixels[i + 2] = (pixels[i + 2] + (246 * glowIntensity * 0.6)).round().clamp(0, 255);
      }
    }
  }

  // Draw 4-point star
  _drawStar(pixels, size, cx, cy, starRadius, innerRadius, 4, [59, 130, 246, 255]);

  // Draw smaller sparkle offset
  final sx = cx + size * 0.18;
  final sy = cy - size * 0.18;
  _drawStar(pixels, size, sx, sy, starRadius * 0.3, innerRadius * 0.3, 4, [96, 165, 250, 255]);

  // Draw dot sparkle
  _drawCircle(pixels, size, cx - size * 0.15, cy - size * 0.22, size * 0.03, [255, 255, 255, 200]);
  _drawCircle(pixels, size, cx + size * 0.25, cy + size * 0.12, size * 0.02, [255, 255, 255, 160]);

  // Rounded corners mask (iOS will clip, but let's make it nice)
  final cornerRadius = size * 0.22;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      // Check if in corner regions
      bool inCorner = false;
      double cdx = 0, cdy = 0;

      if (x < cornerRadius && y < cornerRadius) {
        cdx = cornerRadius - x;
        cdy = cornerRadius - y;
        inCorner = true;
      } else if (x >= size - cornerRadius && y < cornerRadius) {
        cdx = x - (size - cornerRadius);
        cdy = cornerRadius - y;
        inCorner = true;
      } else if (x < cornerRadius && y >= size - cornerRadius) {
        cdx = cornerRadius - x;
        cdy = y - (size - cornerRadius);
        inCorner = true;
      } else if (x >= size - cornerRadius && y >= size - cornerRadius) {
        cdx = x - (size - cornerRadius);
        cdy = y - (size - cornerRadius);
        inCorner = true;
      }

      if (inCorner && sqrt(cdx * cdx + cdy * cdy) > cornerRadius) {
        pixels[i + 3] = 0; // transparent
      }
    }
  }

  final png = PngEncoder.encode(size, size, pixels);
  File(path).writeAsBytesSync(png);
  print('Generated $path (${png.length} bytes)');
}

void _generateSplash(int size, String path) {
  final pixels = Uint8List(size * size * 4);
  // Transparent background - the native splash bg color handles the rest
  // Just draw the sparkle icon centered

  final cx = size / 2;
  final cy = size / 2;
  final starRadius = size * 0.3;
  final innerRadius = size * 0.1;

  _drawStar(pixels, size, cx, cy, starRadius, innerRadius, 4, [59, 130, 246, 255]);
  _drawStar(pixels, size, cx + size * 0.16, cy - size * 0.16, starRadius * 0.28, innerRadius * 0.28, 4, [96, 165, 250, 255]);
  _drawCircle(pixels, size, cx - size * 0.13, cy - size * 0.2, size * 0.025, [255, 255, 255, 220]);
  _drawCircle(pixels, size, cx + size * 0.22, cy + size * 0.1, size * 0.018, [255, 255, 255, 180]);

  final png = PngEncoder.encode(size, size, pixels);
  File(path).writeAsBytesSync(png);
  print('Generated $path (${png.length} bytes)');
}

void _drawStar(Uint8List pixels, int size, double cx, double cy,
    double outerR, double innerR, int points, List<int> color) {
  final totalPoints = points * 2;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final dist = sqrt(dx * dx + dy * dy);
      var angle = atan2(dy, dx);
      if (angle < 0) angle += 2 * pi;

      // Calculate star radius at this angle
      final segment = (angle / (2 * pi) * totalPoints);
      final t = (segment % 1.0);
      final isOuter = segment.floor() % 2 == 0;
      double r1, r2;
      if (isOuter) {
        r1 = outerR;
        r2 = innerR;
      } else {
        r1 = innerR;
        r2 = outerR;
      }
      final starR = r1 + (r2 - r1) * t;

      if (dist < starR) {
        final i = (y * size + x) * 4;
        final alpha = color[3] / 255.0;
        final existAlpha = pixels[i + 3] / 255.0;
        final outAlpha = alpha + existAlpha * (1 - alpha);
        if (outAlpha > 0) {
          pixels[i] = ((color[0] * alpha + pixels[i] * existAlpha * (1 - alpha)) / outAlpha).round().clamp(0, 255);
          pixels[i + 1] = ((color[1] * alpha + pixels[i + 1] * existAlpha * (1 - alpha)) / outAlpha).round().clamp(0, 255);
          pixels[i + 2] = ((color[2] * alpha + pixels[i + 2] * existAlpha * (1 - alpha)) / outAlpha).round().clamp(0, 255);
          pixels[i + 3] = (outAlpha * 255).round().clamp(0, 255);
        }
      }
    }
  }
}

void _drawCircle(Uint8List pixels, int size, double cx, double cy, double radius, List<int> color) {
  for (int y = max(0, (cy - radius - 1).floor()); y < min(size, (cy + radius + 1).ceil()); y++) {
    for (int x = max(0, (cx - radius - 1).floor()); x < min(size, (cx + radius + 1).ceil()); x++) {
      final dx = x - cx;
      final dy = y - cy;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist <= radius) {
        final i = (y * size + x) * 4;
        final edge = (radius - dist).clamp(0.0, 1.0);
        final alpha = (color[3] / 255.0) * edge;
        final existAlpha = pixels[i + 3] / 255.0;
        final outAlpha = alpha + existAlpha * (1 - alpha);
        if (outAlpha > 0) {
          pixels[i] = ((color[0] * alpha + pixels[i] * existAlpha * (1 - alpha)) / outAlpha).round().clamp(0, 255);
          pixels[i + 1] = ((color[1] * alpha + pixels[i + 1] * existAlpha * (1 - alpha)) / outAlpha).round().clamp(0, 255);
          pixels[i + 2] = ((color[2] * alpha + pixels[i + 2] * existAlpha * (1 - alpha)) / outAlpha).round().clamp(0, 255);
          pixels[i + 3] = (outAlpha * 255).round().clamp(0, 255);
        }
      }
    }
  }
}
