import ActivityKit
import SwiftUI
import WidgetKit

struct A1111DownloadActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var displayName: String
    var progress: Double
    var statusText: String
  }

  var displayName: String
}

@available(iOS 16.2, *)
struct DownloadLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: A1111DownloadActivityAttributes.self) { context in
      DownloadLockScreenView(context: context)
        .widgetURL(URL(string: "a1111mini://apple-ml-models"))
    } dynamicIsland: { context in
      let progress = context.state.progress.clampedProgress
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundColor(.purple)
            .font(.title3)
            .padding(.leading, 6)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(progress.percentLabel)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundColor(.purple)
            .padding(.trailing, 6)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.displayName)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(downloadStatusLine(context.state.statusText))
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
            ProgressView(value: progress)
              .tint(.purple)
          }
          .padding(.horizontal, 6)
          .padding(.bottom, 4)
        }
      } compactLeading: {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundColor(.purple)
      } compactTrailing: {
        Text(progress.percentLabel)
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundColor(.purple)
      } minimal: {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundColor(.purple)
      }
    }
  }
}

@available(iOS 16.2, *)
private struct DownloadLockScreenView: View {
  let context: ActivityViewContext<A1111DownloadActivityAttributes>
  private let purple = Color.purple

  var body: some View {
    let progress = context.state.progress.clampedProgress
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        ZStack {
          Circle()
            .fill(purple.opacity(0.18))
            .frame(width: 28, height: 28)
          Image(systemName: "arrow.down.circle.fill")
            .foregroundColor(purple)
            .font(.system(size: 14, weight: .semibold))
        }
        VStack(alignment: .leading, spacing: 1) {
          Text("A1111 Mini")
            .font(.caption2)
            .foregroundColor(.secondary)
          Text(context.state.displayName)
            .font(.subheadline.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        Spacer(minLength: 8)
        Text(progress.percentLabel)
          .font(.subheadline.monospacedDigit().bold())
          .foregroundColor(purple)
      }

      Text(downloadStatusLine(context.state.statusText))
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)

      ProgressView(value: progress)
        .tint(purple)
    }
    .padding()
    .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
  }
}

private extension Double {
  var clampedProgress: Double { min(1, max(0, self)) }

  var percentLabel: String {
    "\(Int((self * 100).rounded()))%"
  }
}

private func downloadStatusLine(_ statusText: String) -> String {
  let trimmed = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return "Downloading…" }
  if trimmed.range(of: #"^\d{1,3}%$"#, options: .regularExpression) != nil {
    return "Downloading…"
  }
  return trimmed
}
