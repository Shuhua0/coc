import SwiftUI
import WidgetKit

@main
struct TimerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var end: Date? = Shared.endDate

    var body: some View {
        VStack(spacing: 28) {
            if let end, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .multilineTextAlignment(.center)
                Button("취소", role: .destructive) { update(nil) }
            } else {
                Text("타이머 없음").font(.title2).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach([10, 30, 60, 300], id: \.self) { sec in
                        Button("\(sec)초") { update(Date().addingTimeInterval(Double(sec))) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .task(id: end) {
            guard let e = end else { return }
            try? await Task.sleep(for: .seconds(max(0, e.timeIntervalSinceNow)))
            if !Task.isCancelled { end = nil }
        }
    }

    private func update(_ date: Date?) {
        Shared.endDate = date
        end = date
        WidgetCenter.shared.reloadAllTimelines()
    }
}
