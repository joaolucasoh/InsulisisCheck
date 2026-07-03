import ActivityKit
import SwiftUI
import WidgetKit

struct InsulisisCheckLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: InsulinActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(.isisFainted)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .unredacted()
                        .accessibilityIdentifier("live-activity.dynamic-island.image")
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insulisis")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("live-activity.dynamic-island.title.text")
                        Text("\(context.state.periodTitle) pendente")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("live-activity.dynamic-island.status.text")
                    }
                    .accessibilityIdentifier("live-activity.dynamic-island.center.container")
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedDelayText(startDate: context.state.overdueStartedAt)
                        .font(.headline.monospacedDigit())
                        .accessibilityIdentifier("live-activity.dynamic-island.elapsed.text")
                }
            } compactLeading: {
                Image(systemName: "syringe")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("live-activity.compact-leading.icon")
            } compactTrailing: {
                ElapsedDelayText(startDate: context.state.overdueStartedAt)
                    .font(.caption2.monospacedDigit())
                    .accessibilityIdentifier("live-activity.compact-trailing.elapsed.text")
            } minimal: {
                Image(systemName: "syringe")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("live-activity.minimal.icon")
            }
            .keylineTint(.red)
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<InsulinActivityAttributes>

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(.liveActivityOverdueBg)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(height: 156)
                .clipped()
                .accessibilityIdentifier("live-activity.lock-screen.background-image")

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isOverdue ? "exclamationmark.triangle.fill" : "syringe.fill")
                            .accessibilityIdentifier("live-activity.lock-screen.status-icon")
                        Text(context.state.periodTitle)
                            .fontWeight(.semibold)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("live-activity.lock-screen.period.text")
                    }
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("live-activity.lock-screen.period-row.container")

                    HStack(spacing: 12) {
                        Image(systemName: "timer")
                            .accessibilityIdentifier("live-activity.lock-screen.timer-icon")
                        ElapsedDelayText(startDate: context.state.overdueStartedAt)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier("live-activity.lock-screen.elapsed.text")
                    }
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("live-activity.lock-screen.elapsed-row.container")

                    Text(context.state.isOverdue ? "de atraso" : "até a próxima dose")
                        .font(.system(size: 24, weight: .regular, design: .rounded))
                        .accessibilityIdentifier("live-activity.lock-screen.subtitle.text")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 214, alignment: .leading)
                .accessibilityIdentifier("live-activity.lock-screen.text-stack.container")

                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
            .padding(.trailing, 150)
            .unredacted()
            .accessibilityIdentifier("live-activity.lock-screen.content-row.container")
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .unredacted()
        .accessibilityIdentifier("live-activity.lock-screen.container")
    }

}

private struct ElapsedDelayText: View {
    let startDate: Date

    var body: some View {
        Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
            .unredacted()
    }
}
