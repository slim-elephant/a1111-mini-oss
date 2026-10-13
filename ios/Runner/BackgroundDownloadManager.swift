import ActivityKit
import Flutter
import Foundation
import UIKit

/// Duplicate of the struct in A1111MiniLiveActivity — must match exactly.
struct A1111DownloadActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var displayName: String
    var progress: Double
    var statusText: String
  }

  var displayName: String
}

/// Duplicate of the struct in A1111MiniLiveActivity — must match exactly.
struct A1111GenerationActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var displayName: String
    var progress: Double
    var statusText: String
  }

  var displayName: String
}

private struct NativeDownloadFile: Codable {
  let url: String
  let relativePath: String
  let size: Int64
}

private struct NativeDownloadJob: Codable {
  let jobId: String
  let displayName: String
  let destRoot: String
  var files: [NativeDownloadFile]
  var fileIndex: Int
  var receivedBytes: Int64
  var totalBytes: Int64
}

/// Background URLSession downloads with a Lock Screen Live Activity.
final class BackgroundDownloadManager: NSObject, URLSessionDownloadDelegate {
  static let shared = BackgroundDownloadManager()
  static let sessionIdentifier = "net.neuro9.a1111mini.model-download"
  private static let jobDefaultsKey = "a1111mini.bgDownloadJob"

  private var channel: FlutterMethodChannel?
  private var backgroundCompletionHandler: (() -> Void)?
  private var taskMeta: [Int: [String: Any]] = [:]
  private var job: NativeDownloadJob?
  private var downloadActivity: Any?
  private var isRequestingDownloadActivity = false
  private var lastLiveActivityUpdate: Date = .distantPast
  private var pendingLiveActivityUpdate: (displayName: String, progress: Double, statusText: String)?
  private var liveActivityFlushWork: DispatchWorkItem?
  private let liveActivityMinInterval: TimeInterval = 2.0
  private var lastSpeedBytes: Int64 = 0
  private var lastSpeedAt: Date = .distantPast
  private var lastBytesPerSecond: Int = 0
  private var generationActivity: Any?
  private var generationBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var installBackgroundTask: UIBackgroundTaskIdentifier = .invalid
  private let lock = NSLock()

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  func bind(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "net.neuro9.a1111mini/model_download",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Download manager gone", details: nil))
        return
      }
      switch call.method {
      case "isAvailable":
        result(true)
      case "startJob":
        guard let args = call.arguments as? [String: Any],
              let jobId = args["jobId"] as? String,
              let destRoot = args["destRoot"] as? String,
              let rawFiles = args["files"] as? [[String: Any]] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing download job args", details: nil))
          return
        }
        let files: [NativeDownloadFile] = rawFiles.compactMap { item in
          guard let url = item["url"] as? String,
                let relativePath = item["relativePath"] as? String else { return nil }
          let size = (item["size"] as? NSNumber)?.int64Value ?? 0
          return NativeDownloadFile(url: url, relativePath: relativePath, size: size)
        }
        self.startJob(
          jobId: jobId,
          displayName: args["displayName"] as? String ?? "Download",
          destRoot: destRoot,
          files: files
        )
        result(nil)
      case "cancelJob":
        let jobId = (call.arguments as? [String: Any])?["jobId"] as? String
        self.cancelJob(jobId: jobId)
        result(nil)
      case "activeJob":
        result(self.activeJobPayload())
      case "startDownloadLiveActivity":
        if #available(iOS 16.2, *) {
          let args = call.arguments as? [String: Any] ?? [:]
          self.startDownloadLiveActivity(
            displayName: args["displayName"] as? String ?? "Download",
            progress: args["progress"] as? Double ?? 0,
            statusText: args["statusText"] as? String ?? "Starting…",
            completion: { result(nil) }
          )
        } else {
          result(nil)
        }
      case "updateDownloadLiveActivity":
        if #available(iOS 16.2, *) {
          let args = call.arguments as? [String: Any] ?? [:]
          self.updateDownloadLiveActivity(
            displayName: args["displayName"] as? String ?? "Download",
            progress: args["progress"] as? Double ?? 0,
            statusText: args["statusText"] as? String ?? ""
          )
        }
        result(nil)
      case "endDownloadLiveActivity":
        if #available(iOS 16.2, *) {
          let success = (call.arguments as? [String: Any])?["success"] as? Bool ?? true
          self.endDownloadLiveActivity(success: success)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    reattachRestoredTasks()
  }

  func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
    backgroundCompletionHandler = handler
    _ = session
    reattachRestoredTasks()
  }

  private func startJob(
    jobId: String,
    displayName: String,
    destRoot: String,
    files: [NativeDownloadFile]
  ) {
    cancelJob(jobId: nil, notify: false)
    let total = files.reduce(Int64(0)) { $0 + max($1.size, 0) }
    let next = NativeDownloadJob(
      jobId: jobId,
      displayName: displayName,
      destRoot: destRoot,
      files: files,
      fileIndex: 0,
      receivedBytes: 0,
      totalBytes: total
    )
    lock.lock()
    job = next
    lock.unlock()
    persistJob()
    lastSpeedBytes = 0
    lastSpeedAt = .distantPast
    lastBytesPerSecond = 0
    lastLiveActivityUpdate = .distantPast
    pendingLiveActivityUpdate = nil
    liveActivityFlushWork?.cancel()
    if #available(iOS 16.2, *) {
      startDownloadLiveActivity(displayName: displayName, statusText: "Starting…")
    }
    startNextFile()
  }

  func cancelJob(jobId: String?, notify: Bool = true) {
    lock.lock()
    let current = job
    lock.unlock()
    if let jobId, let current, current.jobId != jobId {
      return
    }
    session.getAllTasks { tasks in
      tasks.forEach { $0.cancel() }
    }
    lock.lock()
    taskMeta.removeAll()
    job = nil
    lock.unlock()
    UserDefaults.standard.removeObject(forKey: Self.jobDefaultsKey)
    if notify, let current {
      notifyCancelled(jobId: current.jobId)
    }
    if #available(iOS 16.2, *) {
      endDownloadLiveActivity(success: false)
    }
  }

  private func startNextFile() {
    lock.lock()
    guard var current = job else {
      lock.unlock()
      return
    }
    while current.fileIndex < current.files.count {
      let file = current.files[current.fileIndex]
      let dest = URL(fileURLWithPath: current.destRoot)
        .appendingPathComponent(file.relativePath)
      if FileManager.default.fileExists(atPath: dest.path),
         let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
         let size = attrs[.size] as? NSNumber,
         file.size > 0,
         size.int64Value == file.size {
        current.receivedBytes += file.size
        current.fileIndex += 1
        job = current
        continue
      }
      job = current
      lock.unlock()
      persistJob()
      enqueue(file: file, job: current)
      return
    }
    job = current
    lock.unlock()
    finishJob(success: true)
  }

  private func enqueue(file: NativeDownloadFile, job: NativeDownloadJob) {
    guard let downloadURL = URL(string: file.url) else {
      notifyError(jobId: job.jobId, message: "Invalid URL")
      finishJob(success: false)
      return
    }
    let dest = URL(fileURLWithPath: job.destRoot).appendingPathComponent(file.relativePath)
    let partial = dest.appendingPathExtension("part")
    try? FileManager.default.createDirectory(
      at: dest.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var request = URLRequest(url: downloadURL)
    request.setValue("A1111-Mini", forHTTPHeaderField: "User-Agent")
    var existingBytes: Int64 = 0
    if FileManager.default.fileExists(atPath: partial.path),
       let attrs = try? FileManager.default.attributesOfItem(atPath: partial.path),
       let size = attrs[.size] as? NSNumber,
       size.int64Value > 0 {
      existingBytes = size.int64Value
      request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
    }
    let task = session.downloadTask(with: request)
    lock.lock()
    taskMeta[task.taskIdentifier] = [
      "jobId": job.jobId,
      "displayName": job.displayName,
      "partialPath": partial.path,
      "destPath": dest.path,
      "relativePath": file.relativePath,
      "existingBytes": existingBytes,
      "fileSize": file.size,
      "url": file.url,
    ]
    lock.unlock()
    task.resume()
    notifyProgress(job: job, currentFile: (file.relativePath as NSString).lastPathComponent)
  }

  private func finishJob(success: Bool) {
    lock.lock()
    let current = job
    job = nil
    taskMeta.removeAll()
    lock.unlock()
    UserDefaults.standard.removeObject(forKey: Self.jobDefaultsKey)
    guard let current else { return }
    if success {
      notifyComplete(jobId: current.jobId, destRoot: current.destRoot)
    }
    if #available(iOS 16.2, *) {
      endDownloadLiveActivity(success: success)
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    lock.lock()
    guard let meta = taskMeta[downloadTask.taskIdentifier],
          var current = job,
          meta["jobId"] as? String == current.jobId else {
      lock.unlock()
      return
    }
    let existing = meta["existingBytes"] as? Int64 ?? 0
    let fileDownloaded = existing + totalBytesWritten
    let beforeThisFile = current.receivedBytes
    let overall = beforeThisFile + fileDownloaded
    let now = Date()
    let elapsed = now.timeIntervalSince(lastSpeedAt)
    if elapsed >= 0.4, lastSpeedAt != .distantPast {
      let delta = overall - lastSpeedBytes
      if delta > 0 {
        lastBytesPerSecond = Int(Double(delta) / elapsed)
      }
      lastSpeedBytes = overall
      lastSpeedAt = now
    } else if lastSpeedAt == .distantPast {
      lastSpeedBytes = overall
      lastSpeedAt = now
    }
    let total = current.totalBytes
    let fileIndex = current.fileIndex
    let fileCount = current.files.count
    let currentFile = (meta["relativePath"] as? String).map {
      ($0 as NSString).lastPathComponent
    }
    lock.unlock()

    notifyProgress(
      jobId: current.jobId,
      receivedBytes: overall,
      totalBytes: total,
      fileIndex: fileIndex + 1,
      fileCount: fileCount,
      currentFile: currentFile,
      bytesPerSecond: lastBytesPerSecond
    )
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    lock.lock()
    guard let meta = taskMeta[downloadTask.taskIdentifier],
          var current = job else {
      lock.unlock()
      return
    }
    let partialPath = meta["partialPath"] as? String ?? ""
    let destPath = meta["destPath"] as? String ?? ""
    let existingBytes = meta["existingBytes"] as? Int64 ?? 0
    let fileSize = meta["fileSize"] as? Int64 ?? 0
    lock.unlock()

    do {
      let dest = URL(fileURLWithPath: destPath)
      let partial = URL(fileURLWithPath: partialPath)
      try FileManager.default.createDirectory(
        at: dest.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if existingBytes > 0, FileManager.default.fileExists(atPath: partialPath) {
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let data = try Data(contentsOf: location)
        try handle.write(contentsOf: data)
      } else {
        if FileManager.default.fileExists(atPath: partialPath) {
          try FileManager.default.removeItem(at: partial)
        }
        try FileManager.default.moveItem(at: location, to: partial)
      }
      if FileManager.default.fileExists(atPath: destPath) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.moveItem(at: partial, to: dest)
      let written = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? NSNumber)?
        .int64Value ?? fileSize
      lock.lock()
      if var live = job, live.jobId == current.jobId {
        live.receivedBytes += max(written, 0)
        live.fileIndex += 1
        job = live
        current = live
      }
      taskMeta.removeValue(forKey: downloadTask.taskIdentifier)
      lock.unlock()
      persistJob()
      startNextFile()
    } catch {
      notifyError(jobId: current.jobId, message: error.localizedDescription)
      finishJob(success: false)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error else { return }
    lock.lock()
    let meta = taskMeta[task.taskIdentifier]
    let current = job
    taskMeta.removeValue(forKey: task.taskIdentifier)
    lock.unlock()
    let jobId = (meta?["jobId"] as? String) ?? current?.jobId
    if (error as NSError).code == NSURLErrorCancelled {
      if let jobId { notifyCancelled(jobId: jobId) }
      return
    }
    if let jobId {
      notifyError(jobId: jobId, message: error.localizedDescription)
    }
    finishJob(success: false)
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletionHandler?()
      self.backgroundCompletionHandler = nil
    }
  }

  // MARK: - Persistence / restore

  private func persistJob() {
    lock.lock()
    let current = job
    lock.unlock()
    guard let current,
          let data = try? JSONEncoder().encode(current) else { return }
    UserDefaults.standard.set(data, forKey: Self.jobDefaultsKey)
  }

  private func loadPersistedJob() -> NativeDownloadJob? {
    guard let data = UserDefaults.standard.data(forKey: Self.jobDefaultsKey) else {
      return nil
    }
    return try? JSONDecoder().decode(NativeDownloadJob.self, from: data)
  }

  private func reattachRestoredTasks() {
    if job == nil {
      job = loadPersistedJob()
    }
    guard job != nil else { return }
    session.getAllTasks { [weak self] tasks in
      guard let self, let current = self.job else { return }
      guard current.fileIndex < current.files.count else {
        self.startNextFile()
        return
      }
      let file = current.files[current.fileIndex]
      let dest = URL(fileURLWithPath: current.destRoot)
        .appendingPathComponent(file.relativePath)
      let partial = dest.appendingPathExtension("part")
      var attached = false
      for task in tasks {
        self.lock.lock()
        self.taskMeta[task.taskIdentifier] = [
          "jobId": current.jobId,
          "displayName": current.displayName,
          "partialPath": partial.path,
          "destPath": dest.path,
          "relativePath": file.relativePath,
          "existingBytes": Int64(0),
          "fileSize": file.size,
          "url": file.url,
        ]
        self.lock.unlock()
        attached = true
      }
      if !attached {
        self.startNextFile()
      }
    }
  }

  private func activeJobPayload() -> [String: Any]? {
    lock.lock()
    let current = job ?? loadPersistedJob()
    lock.unlock()
    guard let current else { return nil }
    let file = current.fileIndex < current.files.count
      ? current.files[current.fileIndex]
      : nil
    return [
      "jobId": current.jobId,
      "displayName": current.displayName,
      "destRoot": current.destRoot,
      "fileIndex": current.fileIndex + 1,
      "fileCount": current.files.count,
      "receivedBytes": current.receivedBytes,
      "totalBytes": current.totalBytes,
      "currentFile": file.map { ($0.relativePath as NSString).lastPathComponent } as Any,
      "stage": "downloading",
    ]
  }

  // MARK: - Flutter callbacks

  private func notifyProgress(job: NativeDownloadJob, currentFile: String?) {
    notifyProgress(
      jobId: job.jobId,
      receivedBytes: job.receivedBytes,
      totalBytes: job.totalBytes,
      fileIndex: min(job.fileIndex + 1, max(job.files.count, 1)),
      fileCount: job.files.count,
      currentFile: currentFile,
      bytesPerSecond: lastBytesPerSecond
    )
  }

  private func notifyProgress(
    jobId: String,
    receivedBytes: Int64,
    totalBytes: Int64,
    fileIndex: Int,
    fileCount: Int,
    currentFile: String?,
    bytesPerSecond: Int
  ) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod(
        "onProgress",
        arguments: [
          "jobId": jobId,
          "receivedBytes": receivedBytes,
          "totalBytes": totalBytes,
          "fileIndex": fileIndex,
          "fileCount": fileCount,
          "currentFile": currentFile as Any,
          "bytesPerSecond": bytesPerSecond,
          "stage": "downloading",
        ]
      )
      if #available(iOS 16.2, *) {
        self.lock.lock()
        let name = self.job?.displayName ?? "Download"
        self.lock.unlock()
        self.queueLiveActivityUpdate(
          displayName: name,
          progress: Self.clampedProgress(
            received: receivedBytes,
            total: totalBytes,
            fileIndex: fileIndex,
            fileCount: fileCount
          ),
          statusText: currentFile.map { "Downloading \($0)" } ?? "Downloading…"
        )
      }
    }
  }

  private func notifyComplete(jobId: String, destRoot: String) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod(
        "onComplete",
        arguments: ["jobId": jobId, "destRoot": destRoot]
      )
    }
  }

  private func notifyError(jobId: String, message: String) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod(
        "onError",
        arguments: ["jobId": jobId, "message": message]
      )
    }
  }

  private func notifyCancelled(jobId: String) {
    DispatchQueue.main.async {
      self.channel?.invokeMethod("onCancelled", arguments: ["jobId": jobId])
    }
  }

  // MARK: - Live Activity

  private static func clampedProgress(
    received: Int64,
    total: Int64,
    fileIndex: Int,
    fileCount: Int
  ) -> Double {
    if total > 0 {
      return min(1, max(0, Double(received) / Double(total)))
    }
    if fileCount > 0 {
      return min(1, max(0, Double(max(fileIndex, 0)) / Double(fileCount)))
    }
    return 0
  }

  @available(iOS 16.2, *)
  private func resolvedDownloadActivity() -> Activity<A1111DownloadActivityAttributes>? {
    if let activity = downloadActivity as? Activity<A1111DownloadActivityAttributes> {
      return activity
    }
    let existing = Activity<A1111DownloadActivityAttributes>.activities.first
    downloadActivity = existing
    return existing
  }

  @available(iOS 16.2, *)
  private func queueLiveActivityUpdate(
    displayName: String,
    progress: Double,
    statusText: String,
    force: Bool = false
  ) {
    pendingLiveActivityUpdate = (displayName, progress, statusText)
    flushLiveActivityUpdate(force: force)
    liveActivityFlushWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.flushLiveActivityUpdate(force: true)
    }
    liveActivityFlushWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + liveActivityMinInterval, execute: work)
  }

  @available(iOS 16.2, *)
  private func flushLiveActivityUpdate(force: Bool) {
    guard let pending = pendingLiveActivityUpdate else { return }
    guard let activity = resolvedDownloadActivity() else { return }
    let now = Date()
    if !force, now.timeIntervalSince(lastLiveActivityUpdate) < liveActivityMinInterval {
      return
    }
    lastLiveActivityUpdate = now
    pendingLiveActivityUpdate = nil
    let state = A1111DownloadActivityAttributes.ContentState(
      displayName: pending.displayName,
      progress: pending.progress,
      statusText: pending.statusText
    )
    let stale = now.addingTimeInterval(5 * 60)
    Task {
      await activity.update(.init(state: state, staleDate: stale))
    }
  }

  @available(iOS 16.2, *)
  func startDownloadLiveActivity(
    displayName: String,
    progress: Double = 0,
    statusText: String = "Starting…",
    completion: (() -> Void)? = nil
  ) {
    if isRequestingDownloadActivity {
      queueLiveActivityUpdate(
        displayName: displayName,
        progress: progress,
        statusText: statusText
      )
      completion?()
      return
    }
    isRequestingDownloadActivity = true
    pendingLiveActivityUpdate = (displayName, progress, statusText)
    let attributes = A1111DownloadActivityAttributes(displayName: displayName)
    let state = A1111DownloadActivityAttributes.ContentState(
      displayName: displayName,
      progress: progress,
      statusText: statusText
    )
    DispatchQueue.main.async {
      Task {
        defer { self.isRequestingDownloadActivity = false }
        for activity in Activity<A1111DownloadActivityAttributes>.activities {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        do {
          let activity = try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: Date().addingTimeInterval(5 * 60)),
            pushType: nil
          )
          self.downloadActivity = activity
          self.lastLiveActivityUpdate = Date()
          self.flushLiveActivityUpdate(force: true)
        } catch {
          NSLog("A1111 Mini download Live Activity start failed: \(error)")
        }
        completion?()
      }
    }
  }

  @available(iOS 16.2, *)
  func updateDownloadLiveActivity(displayName: String, progress: Double, statusText: String) {
    queueLiveActivityUpdate(
      displayName: displayName,
      progress: progress,
      statusText: statusText
    )
  }

  @available(iOS 16.2, *)
  func endDownloadLiveActivity(success: Bool, statusText: String? = nil) {
    liveActivityFlushWork?.cancel()
    pendingLiveActivityUpdate = nil
    let finalStatus = statusText ?? (success ? "Complete" : "Stopped")
    DispatchQueue.main.async {
      Task {
        for activity in Activity<A1111DownloadActivityAttributes>.activities {
          let final = A1111DownloadActivityAttributes.ContentState(
            displayName: activity.content.state.displayName,
            progress: success ? 1.0 : activity.content.state.progress,
            statusText: finalStatus
          )
          await activity.end(
            .init(state: final, staleDate: nil),
            dismissalPolicy: .immediate
          )
        }
        self.downloadActivity = nil
      }
    }
  }

  func beginInstall(displayName: String) {
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = true
      if self.installBackgroundTask == .invalid {
        self.installBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "A1111MiniInstall") {
          let task = self.installBackgroundTask
          if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            self.installBackgroundTask = .invalid
          }
        }
      }
      if #available(iOS 16.2, *) {
        self.startDownloadLiveActivity(
          displayName: displayName,
          statusText: "One-time install · depends on this iPhone"
        )
      }
    }
  }

  func updateInstall(displayName: String, progress: Double, statusText: String) {
    guard #available(iOS 16.2, *) else { return }
    updateDownloadLiveActivity(
      displayName: displayName,
      progress: progress,
      statusText: statusText
    )
  }

  func endInstall(success: Bool, statusText: String) {
    DispatchQueue.main.async {
      let task = self.installBackgroundTask
      if task != .invalid {
        UIApplication.shared.endBackgroundTask(task)
        self.installBackgroundTask = .invalid
      }
      if self.generationBackgroundTask == .invalid {
        UIApplication.shared.isIdleTimerDisabled = false
      }
      if #available(iOS 16.2, *) {
        self.endDownloadLiveActivity(success: success, statusText: statusText)
      }
    }
  }

  func beginGeneration(displayName: String, liveActivity: Bool = true) {
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = true
      if self.generationBackgroundTask == .invalid {
        self.generationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "A1111MiniGenerate") {
          let task = self.generationBackgroundTask
          if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            self.generationBackgroundTask = .invalid
          }
        }
      }
      if liveActivity, #available(iOS 16.2, *), self.generationActivity == nil {
        self.startGenerationLiveActivity(displayName: displayName)
      }
    }
  }

  func updateGeneration(progress: Double, statusText: String) {
    guard #available(iOS 16.2, *) else { return }
    DispatchQueue.main.async {
      guard let activity = self.generationActivity as? Activity<A1111GenerationActivityAttributes> else {
        return
      }
      let state = A1111GenerationActivityAttributes.ContentState(
        displayName: activity.content.state.displayName,
        progress: progress,
        statusText: statusText
      )
      Task {
        await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(10 * 60)))
      }
    }
  }

  func endGeneration(success: Bool, statusText: String) {
    DispatchQueue.main.async {
      UIApplication.shared.isIdleTimerDisabled = false
      let task = self.generationBackgroundTask
      if task != .invalid {
        UIApplication.shared.endBackgroundTask(task)
        self.generationBackgroundTask = .invalid
      }
      if #available(iOS 16.2, *) {
        self.finishGenerationLiveActivity(success: success, statusText: statusText)
      }
    }
  }

  @available(iOS 16.2, *)
  private func startGenerationLiveActivity(displayName: String) {
    let attributes = A1111GenerationActivityAttributes(displayName: displayName)
    let state = A1111GenerationActivityAttributes.ContentState(
      displayName: displayName,
      progress: 0.02,
      statusText: "Loading model…"
    )
    Task {
      for activity in Activity<A1111GenerationActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      do {
        let activity = try Activity.request(
          attributes: attributes,
          content: .init(state: state, staleDate: Date().addingTimeInterval(10 * 60)),
          pushType: nil
        )
        self.generationActivity = activity
      } catch {
        NSLog("A1111 Mini generation Live Activity start failed: \(error)")
      }
    }
  }

  @available(iOS 16.2, *)
  private func finishGenerationLiveActivity(success: Bool, statusText: String) {
    Task {
      for activity in Activity<A1111GenerationActivityAttributes>.activities {
        let final = A1111GenerationActivityAttributes.ContentState(
          displayName: activity.content.state.displayName,
          progress: success ? 1 : activity.content.state.progress,
          statusText: statusText
        )
        await activity.end(
          .init(state: final, staleDate: nil),
          dismissalPolicy: success ? .default : .immediate
        )
      }
      self.generationActivity = nil
    }
  }
}
