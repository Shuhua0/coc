import Foundation

enum Shared {
    static var groupID: String {
        if let g = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first {
            return g
        }
        // 위젯 번들 ID(...widget[.TEAMID])에서 ".widget"만 빼면 앱 번들 ID와 같아짐
        let id = (Bundle.main.bundleIdentifier ?? "com.example.timertest")
            .replacingOccurrences(of: ".widget", with: "")
        return "group." + id
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    static var endDate: Date? {
        get { defaults.object(forKey: "endDate") as? Date }
        set { defaults.set(newValue, forKey: "endDate") }
    }
}