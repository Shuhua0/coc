import Foundation

enum Shared {
    static let fallbackGroup = "group.com.example.timertest"

    // SideStore가 앱 그룹 ID를 바꿔 넣을 수 있어서 Info.plist의 ALTAppGroups를 우선 사용
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first ?? fallbackGroup
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    static var endDate: Date? {
        get { defaults.object(forKey: "endDate") as? Date }
        set { defaults.set(newValue, forKey: "endDate") }
    }
}
