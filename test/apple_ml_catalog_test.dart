import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:a1111_mini/core/models/generation_backend.dart';
import 'package:a1111_mini/core/on_device/apple_ml_download_platform.dart';
import 'package:a1111_mini/core/on_device/apple_ml_downloader.dart';
import 'package:a1111_mini/core/on_device/apple_ml_models.dart';

void main() {
  test('Apple ML is an on-device backend without a remote server', () {
    expect(GenerationBackend.fromId('appleMl'), GenerationBackend.appleMl);
    expect(GenerationBackend.appleMl.requiresRemoteServer, isFalse);
    expect(GenerationBackend.appleMl.label, 'Apple ML');
    expect(GenerationBackend.a1111.requiresRemoteServer, isTrue);
    expect(GenerationBackend.comfyui.requiresRemoteServer, isTrue);
  });

  test('catalog skip filter drops SafetyChecker, unsplit Unet, zip, and docs', () {
    expect(
      appleMlShouldSkipRemotePath('split_einsum/compiled/SafetyChecker.mlmodelc/weights/weight.bin'),
      isTrue,
    );
    expect(
      appleMlShouldSkipRemotePath('split_einsum/compiled/Unet.mlmodelc/weights/weight.bin'),
      isTrue,
    );
    expect(
      appleMlShouldSkipRemotePath('split_einsum/compiled/UnetChunk1.mlmodelc/weights/weight.bin'),
      isFalse,
    );
    expect(
      appleMlShouldSkipRemotePath('split_einsum/compiled/VAEEncoder.mlmodelc/coremldata.bin'),
      isTrue,
    );
    expect(
      appleMlShouldSkipRemotePath(
        'coreml-stable-diffusion-xl-base-ios_split_einsum_compiled.zip',
      ),
      isTrue,
    );
    expect(appleMlShouldSkipRemotePath('README.md'), isTrue);
    expect(
      appleMlShouldSkipRemotePath('split_einsum/compiled/TextEncoder.mlmodelc/weights/weight.bin'),
      isFalse,
    );
    expect(
      appleMlShouldSkipRemotePath(
        'coreml-stable-diffusion-xl-base-ios_split_einsum_compiled/vocab.json',
      ),
      isFalse,
    );
  });

  test('native download file map uses Hugging Face resolve URLs', () {
    final files = appleMlNativeDownloadFiles(
      hfRepo: 'apple/coreml-stable-diffusion-v1-5',
      files: const [
        HfRemoteFile(path: 'split_einsum/compiled/vocab.json', size: 12),
        HfRemoteFile(
          path: 'split_einsum/compiled/UnetChunk1.mlmodelc/weights/weight.bin',
          size: 99,
        ),
      ],
    );
    expect(files, hasLength(2));
    expect(
      files.first['url'],
      'https://huggingface.co/apple/coreml-stable-diffusion-v1-5/resolve/main/split_einsum/compiled/vocab.json?download=true',
    );
    expect(files.first['relativePath'], 'split_einsum/compiled/vocab.json');
    expect(files.first['size'], 12);
    expect(
      files.last['relativePath'],
      'split_einsum/compiled/UnetChunk1.mlmodelc/weights/weight.bin',
    );
  });

  test('SD 1.5 and SDXL catalog entries point at Apple HF repos', () {
    final sd15 = AppleMlCatalog.byId('sd15-ane')!;
    expect(sd15.hfRepo, 'apple/coreml-stable-diffusion-v1-5');
    expect(sd15.treePrefix, 'split_einsum/compiled');
    expect(sd15.pipeline, AppleMlPipelineKind.sd15);
    expect(sd15.recommendedWidth, 512);

    final sdxl = AppleMlCatalog.byId('sdxl-ios')!;
    expect(sdxl.hfRepo, 'apple/coreml-stable-diffusion-xl-base-ios');
    expect(sdxl.isSdxl, isTrue);
    expect(sdxl.minIosMajor, 17);
    expect(sdxl.recommendedWidth, 768);
  });

  test('findResourcesDir locates vocab + text encoder folder', () async {
    final tmp = await Directory.systemTemp.createTemp('apple-ml-test');
    addTearDown(() => tmp.delete(recursive: true));
    final resources = Directory('${tmp.path}/split_einsum/compiled');
    await resources.create(recursive: true);
    await File('${resources.path}/vocab.json').writeAsString('{}');
    await File('${resources.path}/merges.txt').writeAsString('a');
    await Directory('${resources.path}/TextEncoder.mlmodelc').create();

    final found = await AppleMlDownloader.findResourcesDir(tmp.path);
    expect(found, resources.path);
  });
}
