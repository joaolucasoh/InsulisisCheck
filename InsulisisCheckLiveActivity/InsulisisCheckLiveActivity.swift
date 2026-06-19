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
                    ElapsedDelayText(startDate: context.state.overdueStartedAt)
                        .font(.headline.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "syringe")
                    .foregroundStyle(.red)
            } compactTrailing: {
                ElapsedDelayText(startDate: context.state.overdueStartedAt)
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
        ZStack(alignment: .trailing) {
            Image(.liveActivityOverdueBg)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(height: 156)
                .clipped()

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isOverdue ? "exclamationmark.triangle.fill" : "syringe.fill")
                        Text(context.state.periodTitle)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 20, weight: .semibold, design: .rounded))

                    HStack(spacing: 12) {
                        Image(systemName: "timer")
                        ElapsedDelayText(startDate: context.state.overdueStartedAt)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .font(.system(size: 44, weight: .bold, design: .rounded))

                    Text(context.state.isOverdue ? "de atraso" : "até a próxima dose")
                        .font(.system(size: 24, weight: .regular, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 214, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
            .padding(.trailing, 150)
            .unredacted()
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .unredacted()
    }

}

private struct ElapsedDelayText: View {
    let startDate: Date

    var body: some View {
        Text(timerInterval: startDate...Date.distantFuture, countsDown: false)
            .unredacted()
    }
}
