import WidgetKit
import SwiftUI

struct TimerEntry: TimelineEntry {
    let date: Date
    let end: Date?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: .now, end: .now.addingTimeInterval(60))
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let now = Date()
        if let end = Shared.endDate, end > now {
            let entries = [TimerEntry(date: now, end: end), TimerEntry(date: end, end: nil)]
            completion(Timeline(entries: entries, policy: .never))
        } else {
            completion(Timeline(entries: [TimerEntry(date: now, end: nil)], policy: .never))
        }
    }
}

struct WidgetView: View {
    let entry: TimerEntry

    var body: some View {
        VStack(spacing: 4) {
            if let end = entry.end {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
            } else {
                Text("대기 중").font(.headline).foregroundStyle(.secondary)
            }
            Text(Shared.groupID).font(.system(size: 8))
            Text(String(describing: Shared.endDate)).font(.system(size: 8))
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TimerWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("타이머")
        .description("앱에서 시작한 타이머를 보여줍니다.")
        .supportedFamilies([.systemSmall])
    }
}