import ActivityKit
import SwiftUI
import WidgetKit

struct InsulisisCheckLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: InsulinActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(context.state.isOverdue ? .red : .green)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(context.state.isOverdue ? "IsisWaiting" : "IsisOk")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insulisis")
                            .font(.headline)
                        Text("\(context.state.periodTitle) pendente")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(endDate: context.state.countdownEndsAt)
                        .font(.headline.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "syringe")
                    .foregroundStyle(.red)
            } compactTrailing: {
                CountdownText(endDate: context.state.countdownEndsAt)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "syringe")
                    .foregroundStyle(.red)
            }
            .keylineTint(.red)
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<InsulinActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(context.state.isOverdue ? "IsisWaiting" : "IsisOk")
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text("Insulina da \(context.attributes.dogName)")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("\(context.state.periodTitle) ainda não foi marcada como OK")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    CountdownText(endDate: context.state.countdownEndsAt)
                        .monospacedDigit()
                }
                .font(.title3.bold())
                .foregroundStyle(.white)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct CountdownText: View {
    let endDate: Date

    var body: some View {
        Text(timerInterval: Date()...endDate, countsDown: true)
    }
}
