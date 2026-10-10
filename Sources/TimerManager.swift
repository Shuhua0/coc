import Foundation
import UserNotifications

class TimerManager: ObservableObject {
    static let shared = TimerManager()
    
    let userDefaults = UserDefaults(suiteName: "group.com.mytimer.app")
    
    @Published var remainingSeconds: Int {
        didSet {
            userDefaults?.set(remainingSeconds, forKey: "remainingSeconds")
            userDefaults?.set(timerEndDate?.timeIntervalSince1970, forKey: "timerEndDate")
        }
    }
    
    @Published var isRunning: Bool = false
    var timerEndDate: Date?
    
    init() {
        self.remainingSeconds = userDefaults?.integer(forKey: "remainingSeconds") ?? 0
    }
    
    func startTimer(seconds: Int) {
        self.remainingSeconds = seconds
        self.isRunning = true
        let endDate = Date().addingTimeInterval(TimeInterval(seconds))
        self.timerEndDate = endDate
        
        userDefaults?.set(endDate.timeIntervalSince1970, forKey: "timerEndDate")
        userDefaults?.set(true, forKey: "isRunning")
        
        scheduleNotification(in: Double(seconds))
    }
    
    func scheduleNotification(in seconds: Double) {
        let content = UNMutableNotificationContent()
        content.title = "타이머 종료"
        content.body = "설정한 시간이 완료되었습니다!"
        content.sound = .default
        
        UNUserNotificationCenter.current().setBadgeCount(1) { _ in }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "TimerEnd", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
}