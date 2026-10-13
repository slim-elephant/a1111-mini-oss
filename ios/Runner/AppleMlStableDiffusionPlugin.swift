import Flutter
import UIKit
import CoreML
import UniformTypeIdentifiers

#if canImport(StableDiffusion)
import StableDiffusion
#endif

class AppleMlStableDiffusionPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let queue = DispatchQueue(label: "net.neuro9.a1111mini.appleml", qos: .userInitiated)
  private var eventSink: FlutterEventSink?
  private var cancelRequested = false
  private var loadedVariant: String?
  private var loadedPath: String?
  private var reportingInstall = false
  private var installDisplayName = "On-device model"
  private var loadTicker: DispatchSourceTimer?

#if canImport(StableDiffusion)
  private var pipeline: (any StableDiffusionPipelineProtocol)?
#endif

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AppleMlStableDiffusionPlugin()
    let channel = FlutterMethodChannel(
      name: "net.neuro9.a1111mini/apple_ml_sd",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(
      name: "net.neuro9.a1111mini/apple_ml_sd_progress",
      binaryMessenger: registrar.messenger()
    )
    events.setStreamHandler(instance)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      if #available(iOS 16.2, *) {
        result(true)
      } else {
        result(false)
      }
    case "osVersion":
      result(UIDevice.current.systemVersion)
    case "load":
      guard let args = call.arguments as? [String: Any],
            let path = args["resourcesPath"] as? String,
            let variant = args["variant"] as? String else {
        result(FlutterError(code: "bad_args", message: "resourcesPath and variant required", details: nil))
        return
      }
      load(path: path, variant: variant, result: result)
    case "generate":
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String else {
        result(FlutterError(code: "bad_args", message: "prompt required", details: nil))
        return
      }
      generate(args: args, prompt: prompt, result: result)
    case "interrupt":
      cancelRequested = true
      result(nil)
    case "isCompiled":
      let path = (call.arguments as? [String: Any])?["resourcesPath"] as? String ?? ""
      result(Self.isCompiled(path: path))
    case "install":
      guard let args = call.arguments as? [String: Any],
            let path = args["resourcesPath"] as? String,
            let variant = args["variant"] as? String else {
        result(FlutterError(code: "bad_args", message: "resourcesPath and variant required", details: nil))
        return
      }
      let displayName = args["displayName"] as? String ?? "On-device model"
      install(path: path, variant: variant, displayName: displayName, result: result)
    case "unload":
      queue.async { [weak self] in
        self?.unloadLocked()
        DispatchQueue.main.async { result(nil) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func install(
    path: String,
    variant: String,
    displayName: String,
    result: @escaping FlutterResult
  ) {
    if #available(iOS 16.2, *) {
#if canImport(StableDiffusion)
      if Self.isCompiled(path: path) {
        result(true)
        return
      }
      installDisplayName = displayName
      BackgroundDownloadManager.shared.beginInstall(displayName: displayName)
      queue.async { [weak self] in
        guard let self else { return }
        self.reportingInstall = true
        do {
          try self.loadLocked(path: path, variant: variant)
          self.reportingInstall = false
          BackgroundDownloadManager.shared.endInstall(success: true, statusText: "Installed")
          DispatchQueue.main.async { result(true) }
        } catch {
          self.reportingInstall = false
          let message = error.localizedDescription
          NSLog("A1111 AppleML install_failed: \(message)")
          BackgroundDownloadManager.shared.endInstall(success: false, statusText: "Install failed")
          DispatchQueue.main.async {
            result(FlutterError(code: "install_failed", message: message, details: nil))
          }
        }
      }
#else
      result(FlutterError(code: "missing_package", message: "StableDiffusion Swift package is not linked", details: nil))
#endif
    } else {
      result(FlutterError(code: "unsupported_os", message: "On-device Stable Diffusion needs iOS 16.2 or later", details: nil))
    }
  }

  private func load(path: String, variant: String, result: @escaping FlutterResult) {
    if #available(iOS 16.2, *) {
#if canImport(StableDiffusion)
      BackgroundDownloadManager.shared.beginGeneration(
        displayName: variant == "sdxl" ? "Stable Diffusion XL" : "Stable Diffusion",
        liveActivity: false
      )
      queue.async { [weak self] in
        guard let self else { return }
        do {
          try self.loadLocked(path: path, variant: variant)
          DispatchQueue.main.async { result(nil) }
        } catch {
          let message = error.localizedDescription
          fputs("A1111 AppleML load_failed: \(message)\n", stderr)
          fflush(stderr)
          NSLog("A1111 AppleML load_failed: \(message)")
          BackgroundDownloadManager.shared.endGeneration(success: false, statusText: "Could not load model")
          DispatchQueue.main.async {
            result(FlutterError(code: "load_failed", message: message, details: nil))
          }
        }
      }
#else
      result(FlutterError(code: "missing_package", message: "StableDiffusion Swift package is not linked", details: nil))
#endif
    } else {
      result(FlutterError(code: "unsupported_os", message: "On-device Stable Diffusion needs iOS 16.2 or later", details: nil))
    }
  }

  private func generate(args: [String: Any], prompt: String, result: @escaping FlutterResult) {
    if #available(iOS 16.2, *) {
#if canImport(StableDiffusion)
      let negative = args["negativePrompt"] as? String ?? ""
      let steps = max(1, Self.intArg(args, "steps", 20))
      let cfg = Self.floatArg(args, "cfgScale", 7)
      let seedRaw = Self.intArg(args, "seed", -1)
      let scheduler = args["scheduler"] as? String ?? "dpmSolver"
      let originalSize = Self.floatArg(args, "originalSize", 512)
      queue.async { [weak self] in
        guard let self else { return }
        do {
          let generated = try self.generateLocked(
            prompt: prompt,
            negative: negative,
            steps: steps,
            cfg: cfg,
            seedRaw: seedRaw,
            scheduler: scheduler,
            originalSize: originalSize
          )
          DispatchQueue.main.async { result(generated) }
          BackgroundDownloadManager.shared.endGeneration(success: true, statusText: "Image ready")
        } catch {
          let message = error.localizedDescription
          fputs("A1111 AppleML generate_failed: \(message)\n", stderr)
          fflush(stderr)
          NSLog("A1111 AppleML generate_failed: \(message)")
          BackgroundDownloadManager.shared.endGeneration(success: false, statusText: "Generation failed")
          DispatchQueue.main.async {
            result(FlutterError(code: "generate_failed", message: message, details: nil))
          }
        }
      }
#else
      result(FlutterError(code: "missing_package", message: "StableDiffusion Swift package is not linked", details: nil))
#endif
    } else {
      result(FlutterError(code: "unsupported_os", message: "On-device Stable Diffusion needs iOS 16.2 or later", details: nil))
    }
  }

#if canImport(StableDiffusion)
  @available(iOS 16.2, *)
  private func loadLocked(path: String, variant: String) throws {
    if loadedPath == path, loadedVariant == variant, pipeline != nil {
      return
    }
    unloadLocked()
    guard let resources = Self.resolveResourcesDir(path) else {
      throw NSError(
        domain: "AppleMlSd",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No Core ML resources found at \(path)"]
      )
    }
    let config = MLModelConfiguration()
#if targetEnvironment(simulator)
    config.computeUnits = .cpuOnly
#else
    // Text encoders and the UNet use the Neural Engine. The XL pipeline
    // itself puts only the VAE on the GPU.
    config.computeUnits = .cpuAndNeuralEngine
#endif
    if variant == "sdxl" {
      if #available(iOS 17.0, *) {
        let xl = try StableDiffusionXLPipeline(
          resourcesAt: resources,
          configuration: config,
          reduceMemory: true
        )
        pipeline = xl
      } else {
        throw NSError(
          domain: "AppleMlSd",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "SDXL on device needs iOS 17 or later"]
        )
      }
    } else {
      let sd = try StableDiffusionPipeline(
        resourcesAt: resources,
        controlNet: [],
        configuration: config,
        disableSafety: true,
        reduceMemory: true
      )
      pipeline = sd
    }
    let parts = Self.prewarmParts(at: resources, variant: variant)
    emit(
      [
        "stage": "loading",
        "step": 0,
        "stepCount": 100,
        "message": "Loading model 0%",
      ],
      notifyActivity: false
    )
    startModelLoadTicker(parts: parts)
    defer { stopModelLoadTicker() }
    // reduceMemory makes this prewarm one model at a time, then unload it.
    try pipeline?.loadResources()
    let packages = Self.modelPackages(at: resources)
    if !packages.isEmpty {
      let stamp = resources.appendingPathComponent(".ane-compiled")
      try Self.stampToken(packages).write(to: stamp, atomically: true, encoding: .utf8)
    }
    emit(
      [
        "stage": "loading",
        "step": 100,
        "stepCount": 100,
        "message": "Loading model 100%",
      ],
      notifyActivity: false
    )
    loadedPath = path
    loadedVariant = variant
  }

  @available(iOS 16.2, *)
  private func generateLocked(
    prompt: String,
    negative: String,
    steps: Int,
    cfg: Float,
    seedRaw: Int,
    scheduler: String,
    originalSize: Float
  ) throws -> [String: Any] {
    guard let pipeline else {
      throw NSError(
        domain: "AppleMlSd",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Load a Core ML model before generating"]
      )
    }
    cancelRequested = false
    let seed: UInt32
    if seedRaw < 0 {
      seed = UInt32.random(in: 0 ..< UInt32.max)
    } else {
      seed = UInt32(truncatingIfNeeded: seedRaw)
    }
    var config = PipelineConfiguration(prompt: prompt)
    config.negativePrompt = negative
    config.imageCount = 1
    config.stepCount = steps
    config.guidanceScale = cfg
    config.seed = seed
    config.disableSafety = true
    config.useDenoisedIntermediates = false
    config.originalSize = originalSize
    config.targetSize = originalSize
    if loadedVariant == "sdxl" {
      // SDXL latents use 0.13025. The pipeline default 0.18215 is SD 1.5 and
      // makes XL images look noisy and washed out.
      config.encoderScaleFactor = 0.13025
      config.decoderScaleFactor = 0.13025
    }
    config.schedulerType = scheduler == "pndm"
      ? .pndmScheduler
      : .dpmSolverMultistepScheduler

    emit(
      [
        "stage": "loading",
        "step": 0,
        "stepCount": 100,
        "message": "Loading model 0%",
      ],
      notifyActivity: false
    )
    startModelLoadTicker()
    defer { stopModelLoadTicker() }

    let images = try pipeline.generateImages(configuration: config) { [weak self] progress in
      self?.stopModelLoadTicker()
      BackgroundDownloadManager.shared.beginGeneration(
        displayName: self?.loadedVariant == "sdxl" ? "Stable Diffusion XL" : "Stable Diffusion"
      )
      self?.emit([
        "stage": "generating",
        "step": progress.step + 1,
        "stepCount": progress.stepCount,
        "message": "Step \(progress.step + 1) of \(progress.stepCount)",
      ])
      return !(self?.cancelRequested ?? false)
    }
    if cancelRequested {
      throw NSError(
        domain: "AppleMlSd",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Interrupted"]
      )
    }
    guard let cgImage = images.first ?? nil else {
      throw NSError(
        domain: "AppleMlSd",
        code: 5,
        userInfo: [NSLocalizedDescriptionKey: "The pipeline returned no image"]
      )
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("apple-ml-\(UUID().uuidString).png")
    let uiImage = UIImage(cgImage: cgImage)
    guard let data = uiImage.pngData() else {
      throw NSError(
        domain: "AppleMlSd",
        code: 6,
        userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"]
      )
    }
    try data.write(to: url)
    return [
      "path": url.path,
      "seed": Int(seed),
      "width": cgImage.width,
      "height": cgImage.height,
    ]
  }

  private static func isCompiled(path: String) -> Bool {
    guard let resources = resolveResourcesDir(path) else { return false }
    let packages = modelPackages(at: resources)
    if packages.isEmpty { return false }
    let stamp = resources.appendingPathComponent(".ane-compiled")
    guard let existing = try? String(contentsOf: stamp, encoding: .utf8) else { return false }
    return existing == stampToken(packages)
  }

  private static func stampToken(_ packages: [URL]) -> String {
    let body = packages.map { url in
      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
      let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
      return "\(url.lastPathComponent):\(Int(modified))"
    }.joined(separator: "|")
    return "pipeline-v2|\(body)"
  }

  /// Files Apple's `prewarmResources` loads, in that order. Sizes are read
  /// once, before the load, so the bar can name the model it is most likely on.
  private static func prewarmParts(at resources: URL, variant: String) -> [(name: String, bytes: Int)] {
    let fm = FileManager.default
    func exists(_ name: String) -> Bool {
      fm.fileExists(atPath: resources.appendingPathComponent(name).path)
    }
    func part(_ name: String) -> (name: String, bytes: Int)? {
      let url = resources.appendingPathComponent(name)
      guard fm.fileExists(atPath: url.path) else { return nil }
      let label = displayName(url.deletingPathExtension().lastPathComponent)
      return (label, directoryByteCount(url))
    }
    var names: [String] = []
    if variant == "sdxl" {
      names.append("TextEncoder2.mlmodelc")
      if exists("UnetChunk1.mlmodelc"), exists("UnetChunk2.mlmodelc") {
        names.append("UnetChunk1.mlmodelc")
        names.append("UnetChunk2.mlmodelc")
      } else {
        names.append("Unet.mlmodelc")
      }
      names.append("VAEDecoder.mlmodelc")
      names.append("TextEncoder.mlmodelc")
    } else {
      names.append("TextEncoder.mlmodelc")
      if exists("UnetChunk1.mlmodelc"), exists("UnetChunk2.mlmodelc") {
        names.append("UnetChunk1.mlmodelc")
        names.append("UnetChunk2.mlmodelc")
      } else {
        names.append("Unet.mlmodelc")
      }
      names.append("VAEDecoder.mlmodelc")
    }
    return names.compactMap { part($0) }
  }

  private static func displayName(_ fileName: String) -> String {
    switch fileName {
    case "TextEncoder": return "Text Encoder"
    case "TextEncoder2": return "Text Encoder 2"
    case "Unet": return "UNet"
    case "UnetChunk1": return "UNet part 1"
    case "UnetChunk2": return "UNet part 2"
    case "VAEDecoder": return "VAE"
    default: return fileName
    }
  }

  private static func directoryByteCount(_ url: URL) -> Int {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles]
    ) else {
      return 1
    }
    var total = 0
    for case let file as URL in enumerator {
      let values = try? file.resourceValues(forKeys: keys)
      if values?.isDirectory == true { continue }
      total += values?.fileSize ?? 0
    }
    return max(total, 1)
  }

  private final class LoadTickState {
    var lastMessage = ""
  }

  /// Core ML does not report bytes while `loadResources` runs. The percent
  /// keeps moving and the name follows each file's share of the package.
  private func startModelLoadTicker(parts: [(name: String, bytes: Int)] = []) {
    stopModelLoadTicker()
    let started = Date()
    let expected: TimeInterval = 90
    let totalBytes = parts.reduce(0) { $0 + $1.bytes }
    let state = LoadTickState()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      let elapsed = Date().timeIntervalSince(started)
      let fraction = min(0.99, elapsed / (elapsed + expected))
      let pct = max(1, Int((fraction * 100).rounded(.down)))
      let name = Self.prewarmName(parts: parts, totalBytes: totalBytes, fraction: fraction)
      let message = name.isEmpty
        ? "Loading model \(pct)%"
        : "Loading model · \(name) · \(pct)%"
      if message == state.lastMessage { return }
      state.lastMessage = message
      self.emit(
        [
          "stage": "loading",
          "step": pct,
          "stepCount": 100,
          "message": message,
        ],
        notifyActivity: false
      )
    }
    timer.resume()
    loadTicker = timer
  }

  private static func prewarmName(
    parts: [(name: String, bytes: Int)],
    totalBytes: Int,
    fraction: Double
  ) -> String {
    guard totalBytes > 0, !parts.isEmpty else { return "" }
    let target = Int((fraction * Double(totalBytes)).rounded(.down))
    var cursor = 0
    for part in parts {
      cursor += part.bytes
      if cursor >= target { return part.name }
    }
    return parts.last?.name ?? ""
  }

  private func stopModelLoadTicker() {
    loadTicker?.cancel()
    loadTicker = nil
  }

  private static func modelPackages(at resources: URL) -> [URL] {
    let children = (try? FileManager.default.contentsOfDirectory(
      at: resources,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )) ?? []
    let skip: Set<String> = ["SafetyChecker.mlmodelc", "VAEEncoder.mlmodelc"]
    return children
      .filter { $0.pathExtension == "mlmodelc" && !skip.contains($0.lastPathComponent) }
      .sorted { lhs, rhs in
        let left = Self.modelRank(lhs.lastPathComponent)
        let right = Self.modelRank(rhs.lastPathComponent)
        if left != right { return left < right }
        return lhs.lastPathComponent < rhs.lastPathComponent
      }
  }

  private static func modelRank(_ name: String) -> Int {
    if name.hasPrefix("TextEncoder") { return 0 }
    if name.hasPrefix("VAEDecoder") { return 1 }
    if name.hasPrefix("Unet") { return 2 }
    return 3
  }

  private static func intArg(_ args: [String: Any], _ key: String, _ fallback: Int) -> Int {
    if let number = args[key] as? NSNumber { return number.intValue }
    if let number = args[key] as? Int { return number }
    return fallback
  }

  private static func floatArg(_ args: [String: Any], _ key: String, _ fallback: Float) -> Float {
    if let number = args[key] as? NSNumber { return number.floatValue }
    if let number = args[key] as? Double { return Float(number) }
    if let number = args[key] as? Int { return Float(number) }
    return fallback
  }

  private func unloadLocked() {
    pipeline?.unloadResources()
    pipeline = nil
    loadedPath = nil
    loadedVariant = nil
  }
#else
  private func unloadLocked() {
    loadedPath = nil
    loadedVariant = nil
  }
#endif

  private func emit(_ payload: [String: Any], notifyActivity: Bool = true) {
    let stage = payload["stage"] as? String ?? ""
    let message = payload["message"] as? String ?? ""
    let step = (payload["step"] as? NSNumber)?.intValue ?? (payload["step"] as? Int) ?? 0
    let stepCount = (payload["stepCount"] as? NSNumber)?.intValue ?? (payload["stepCount"] as? Int) ?? 0
    let progress: Double
    if stage == "generating", stepCount > 0 {
      progress = min(1, max(0, Double(step) / Double(stepCount)))
    } else if stage == "loading", stepCount == 100 {
      progress = min(0.95, max(0, Double(step) / 100))
    } else if stage == "loading", stepCount > 0 {
      progress = min(0.2, max(0.02, Double(step) / Double(stepCount) * 0.2))
    } else {
      progress = 0.02
    }
    let status = message.isEmpty
      ? (stage == "generating" ? "Generating…" : "Loading model…")
      : message
    // Live Activity updates use the GPU. Core ML is already using it while the
    // weights load, and overlapping the two was locking the graphics chip.
    if notifyActivity, stage != "loading" {
      if reportingInstall {
        BackgroundDownloadManager.shared.updateInstall(
          displayName: installDisplayName,
          progress: progress,
          statusText: status
        )
      }
      BackgroundDownloadManager.shared.updateGeneration(progress: progress, statusText: status)
    }
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  private static func resolveResourcesDir(_ path: String) -> URL? {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    if isResourcesDir(url) { return url }
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return nil
    }
    for case let child as URL in enumerator {
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
        if child.lastPathComponent.hasSuffix(".mlmodelc") {
          let parent = child.deletingLastPathComponent()
          if isResourcesDir(parent) { return parent }
        }
      }
    }
    return nil
  }

  private static func isResourcesDir(_ url: URL) -> Bool {
    let vocab = url.appendingPathComponent("vocab.json")
    let merges = url.appendingPathComponent("merges.txt")
    let te = url.appendingPathComponent("TextEncoder.mlmodelc")
    let te2 = url.appendingPathComponent("TextEncoder2.mlmodelc")
    let fm = FileManager.default
    guard fm.fileExists(atPath: vocab.path), fm.fileExists(atPath: merges.path) else {
      return false
    }
    return fm.fileExists(atPath: te.path) || fm.fileExists(atPath: te2.path)
  }
}
