import ActivityKit
import SwiftUI
import WidgetKit

struct A1111GenerationActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var displayName: String
    var progress: Double
    var statusText: String
  }

  var displayName: String
}

@available(iOS 16.2, *)
struct GenerationLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: A1111GenerationActivityAttributes.self) { context in
      GenerationLockScreenView(context: context)
        .widgetURL(URL(string: "a1111mini://sessions"))
    } dynamicIsland: { context in
      let progress = context.state.progress.clampedGeneration
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "sparkles")
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
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(context.state.statusText)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(2)
            Text("Phone stays awake until this finishes")
              .font(.caption2)
              .foregroundColor(.secondary)
            ProgressView(value: progress)
              .tint(.purple)
          }
          .padding(.horizontal, 6)
          .padding(.bottom, 4)
        }
      } compactLeading: {
        Image(systemName: "sparkles")
          .foregroundColor(.purple)
      } compactTrailing: {
        Text(progress.percentLabel)
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundColor(.purple)
      } minimal: {
        Image(systemName: "sparkles")
          .foregroundColor(.purple)
      }
    }
  }
}

@available(iOS 16.2, *)
private struct GenerationLockScreenView: View {
  let context: ActivityViewContext<A1111GenerationActivityAttributes>
  private let purple = Color.purple

  var body: some View {
    let progress = context.state.progress.clampedGeneration
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "sparkles")
          .foregroundColor(purple)
        Text(context.state.displayName)
          .font(.subheadline.bold())
          .lineLimit(1)
        Spacer()
        Text(progress.percentLabel)
          .font(.subheadline.monospacedDigit().bold())
          .foregroundColor(purple)
      }
      Text(context.state.statusText)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(2)
      Text("One image at a time. The screen stays on while this runs.")
        .font(.caption2)
        .foregroundColor(.secondary)
      ProgressView(value: progress)
        .tint(purple)
    }
    .padding()
    .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
  }
}

private extension Double {
  var clampedGeneration: Double { min(1, max(0, self)) }
  var percentLabel: String { "\(Int((self * 100).rounded()))%" }
}
