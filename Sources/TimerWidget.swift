import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), endDate: Date().addingTimeInterval(60))
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), endDate: getEndDate())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let currentDate = Date()
        let endDate = getEndDate()
        
        let entry = SimpleEntry(date: currentDate, endDate: endDate)
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 1, to: currentDate)!
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    func getEndDate() -> Date {
        let defaults = UserDefaults(suiteName: "group.com.mytimer.app")
        let timeInterval = defaults?.double(forKey: "timerEndDate") ?? 0
        if timeInterval > 0 {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return Date()
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let endDate: Date
}

struct TimerWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack {
            Text("타이머 남은 시간")
                .font(.caption)
                .foregroundColor(.gray)
            
            let remaining = Int(entry.endDate.timeIntervalSince(Date()))
            if remaining > 0 {
                Text("\(remaining)초")
                    .font(.title)
                    .bold()
                    .foregroundColor(.orange)
            } else {
                Text("완료됨!")
                    .font(.title)
                    .bold()
                    .foregroundColor(.green)
            }
        }
        .containerBackground(.fill.background, for: .widget)
    }
}

struct TimerWidget: Widget {
    let kind: String = "TimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TimerWidgetEntryView(entry: entry)
        }
    }
}