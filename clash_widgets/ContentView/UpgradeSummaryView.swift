import SwiftUI
import Combine
import Foundation

// MARK: - 남은 업그레이드 요약 (비용 / 시간)
//
// 상단 툴바의 프로필 전환 버튼 왼쪽에 놓이는 버튼과, 그 버튼으로 여는 화면입니다.
// - 가격/시간 데이터: https://assets.clashk.ing/static_data.json (다운로드 후 캐시, 실패 시 앱 내장 데이터 사용)
// - 골드패스 %는 비용과 시간 모두에 적용됩니다.
// - 현재 선택된 프로필 기준이며 프로필을 바꾸면 같이 바뀝니다.

// MARK: - 툴바 버튼

struct UpgradeSummaryButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "list.bullet.clipboard")
        }
        .accessibilityLabel("Remaining Upgrades")
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .fullScreenCover(isPresented: $isPresented) {
            UpgradeSummaryScreen()
        }
    }
}

// MARK: - 자원 종류

enum UpgradeResource: Hashable, CaseIterable {
    case gold
    case elixir
    case darkElixir
    case other

    init(raw: String?, fallback: UpgradeResource) {
        guard let raw, !raw.isEmpty else {
            self = fallback
            return
        }
        let key = raw.lowercased()
        if key.contains("dark") {
            self = .darkElixir
        } else if key.contains("elixir") {
            self = .elixir
        } else if key.contains("gold") {
            self = .gold
        } else {
            self = .other
        }
    }

    var color: Color {
        switch self {
        case .gold: return Color(red: 1.0, green: 0.80, blue: 0.25)
        case .elixir: return Color(red: 0.86, green: 0.40, blue: 0.86)
        case .darkElixir: return Color(red: 0.55, green: 0.52, blue: 0.95)
        case .other: return Color.secondary
        }
    }

    var koreanName: String {
        switch self {
        case .gold: return "골드"
        case .elixir: return "엘릭서"
        case .darkElixir: return "다크 엘릭서"
        case .other: return "기타"
        }
    }
}

// MARK: - 표시 형식

enum UpgradeFormat {
    /// 48K, 1.13M, 14.4M 처럼 줄여서 표시
    static func cost(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000_000 { return trimmed(number / 1_000_000_000, digits: 2) + "B" }
        if number >= 1_000_000 { return trimmed(number / 1_000_000, digits: 2) + "M" }
        if number >= 1_000 { return trimmed(number / 1_000, digits: 1) + "K" }
        return String(value)
    }

    private static func trimmed(_ value: Double, digits: Int) -> String {
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// 2d 19h / 1mo 3d / 2mo 10d / 1y 3mo (한 달 = 30일)
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if days >= 365 {
            let years = days / 365
            let months = (days % 365) / 30
            return months > 0 ? "\(years)y \(months)mo" : "\(years)y"
        }
        if days >= 30 {
            let months = days / 30
            let restDays = days % 30
            return restDays > 0 ? "\(months)mo \(restDays)d" : "\(months)mo"
        }
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }

    /// 진행 중 항목의 남은 시간: 2d 22h 20m
    static func remaining(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}

// MARK: - static_data.json 파싱 (백그라운드에서 실행)

nonisolated struct UpgradeStaticLevel: Sendable {
    let level: Int
    let cost: Double?
    let seconds: Double?
    let resource: String?
}

nonisolated struct UpgradeStaticEntity: Sendable {
    let id: Int
    let resource: String?
    /// true: 레벨 N 줄이 "N → N+1" 업그레이드 값 (유닛/영웅 계열)
    /// false: 레벨 N 줄이 "N 레벨이 되기 위한" 값 (건물 계열)
    let fromSemantic: Bool
    let levels: [UpgradeStaticLevel]
}

nonisolated enum UpgradeStaticParser {
    /// 어떤 구조든 `_id` 와 `levels` 배열을 가진 항목을 찾아 모읍니다.
    static func parse(_ data: Data) -> [Int: UpgradeStaticEntity]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var result: [Int: UpgradeStaticEntity] = [:]
        walk(root, &result)
        return result.isEmpty ? nil : result
    }

    private static func walk(_ node: Any, _ result: inout [Int: UpgradeStaticEntity]) {
        if let array = node as? [Any] {
            for element in array { walk(element, &result) }
            return
        }
        guard let dict = node as? [String: Any] else { return }
        if let id = intValue(dict["_id"]),
           let levels = dict["levels"] as? [[String: Any]],
           result[id] == nil,
           let entity = makeEntity(id: id, dict: dict, levels: levels) {
            result[id] = entity
        }
        for (key, value) in dict where key != "levels" {
            if value is [Any] || value is [String: Any] {
                walk(value, &result)
            }
        }
    }

    private static func makeEntity(id: Int, dict: [String: Any], levels: [[String: Any]]) -> UpgradeStaticEntity? {
        let entityResource = (dict["upgrade_resource"] as? String) ?? (dict["build_resource"] as? String)
        var usesBuildKeys = false
        var rows: [UpgradeStaticLevel] = []
        for row in levels {
            guard let level = intValue(row["level"]) else { continue }
            let buildCost = number(row["build_cost"])
            let buildTime = number(row["build_time"])
            let upgradeCost = number(row["upgrade_cost"])
            let upgradeTime = number(row["upgrade_time"])
            if buildCost != nil || buildTime != nil { usesBuildKeys = true }
            let cost = buildCost ?? upgradeCost ?? number(row["cost"])
            let time = buildTime ?? upgradeTime ?? number(row["time"])
            let resource = (row["upgrade_resource"] as? String) ?? (row["build_resource"] as? String)
            rows.append(UpgradeStaticLevel(level: level, cost: cost, seconds: time, resource: resource))
        }
        guard rows.contains(where: { $0.cost != nil || $0.seconds != nil }) else { return nil }
        rows.sort { $0.level < $1.level }

        var fromSemantic = false
        if !usesBuildKeys, let last = rows.last {
            let lastIsEmpty = (last.cost ?? 0) == 0 && (last.seconds ?? 0) == 0
            let earlierHasValues = rows.dropLast().contains { ($0.cost ?? 0) > 0 || ($0.seconds ?? 0) > 0 }
            fromSemantic = lastIsEmpty && earlierHasValues
        }
        return UpgradeStaticEntity(id: id, resource: entityResource, fromSemantic: fromSemantic, levels: rows)
    }

    // 캐시 파일(작게 줄인 형태) 읽기/쓰기
    static func encode(_ entities: [Int: UpgradeStaticEntity], fetchedAt: Date) -> Data? {
        var list: [[String: Any]] = []
        for entity in entities.values {
            var levels: [[Any]] = []
            for level in entity.levels {
                levels.append([level.level, level.cost ?? -1, level.seconds ?? -1, level.resource ?? ""])
            }
            list.append(["id": entity.id, "res": entity.resource ?? "", "from": entity.fromSemantic, "lv": levels])
        }
        let root: [String: Any] = ["fetchedAt": fetchedAt.timeIntervalSince1970, "entities": list]
        return try? JSONSerialization.data(withJSONObject: root)
    }

    static func decode(_ data: Data) -> (entities: [Int: UpgradeStaticEntity], fetchedAt: Date)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stamp = number(root["fetchedAt"]),
              let list = root["entities"] as? [[String: Any]] else { return nil }
        var result: [Int: UpgradeStaticEntity] = [:]
        for item in list {
            guard let id = intValue(item["id"]),
                  let rawLevels = item["lv"] as? [[Any]] else { continue }
            var levels: [UpgradeStaticLevel] = []
            for raw in rawLevels where raw.count >= 4 {
                guard let level = intValue(raw[0]) else { continue }
                let cost = number(raw[1])
                let seconds = number(raw[2])
                let resource = raw[3] as? String
                levels.append(UpgradeStaticLevel(
                    level: level,
                    cost: (cost ?? -1) < 0 ? nil : cost,
                    seconds: (seconds ?? -1) < 0 ? nil : seconds,
                    resource: (resource ?? "").isEmpty ? nil : resource
                ))
            }
            let resource = item["res"] as? String
            result[id] = UpgradeStaticEntity(
                id: id,
                resource: (resource ?? "").isEmpty ? nil : resource,
                fromSemantic: (item["from"] as? Bool) ?? false,
                levels: levels
            )
        }
        if result.isEmpty { return nil }
        return (entities: result, fetchedAt: Date(timeIntervalSince1970: stamp))
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

// MARK: - static_data.json 저장소 (다운로드 + 캐시)

@MainActor
final class UpgradeStaticDataStore: ObservableObject {
    static let shared = UpgradeStaticDataStore()
    static let remoteURL = URL(string: "https://assets.clashk.ing/static_data.json")!

    @Published private(set) var revision = 0
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var entities: [Int: UpgradeStaticEntity] = [:]
    private let maxAge: TimeInterval = 24 * 3600

    private init() {
        loadCache()
    }

    var hasData: Bool { !entities.isEmpty }

    func entity(_ id: Int) -> UpgradeStaticEntity? {
        entities[id]
    }

    private static var cacheURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("UpgradeSummary", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("static_data_slim.json")
    }

    private func loadCache() {
        guard let url = Self.cacheURL,
              let data = try? Data(contentsOf: url),
              let decoded = UpgradeStaticParser.decode(data) else { return }
        entities = decoded.entities
        fetchedAt = decoded.fetchedAt
    }

    func refreshIfNeeded(force: Bool = false) async {
        if isRefreshing { return }
        if !force, !entities.isEmpty, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge { return }

        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            var request = URLRequest(url: Self.remoteURL)
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                lastError = "HTTP \(http.statusCode)"
                return
            }
            let parsed = await Task.detached(priority: .utility) {
                UpgradeStaticParser.parse(data)
            }.value
            guard let parsed else {
                lastError = "데이터 형식을 읽을 수 없어요"
                return
            }
            let now = Date()
            entities = parsed
            fetchedAt = now
            if let url = Self.cacheURL, let slim = UpgradeStaticParser.encode(parsed, fetchedAt: now) {
                try? slim.write(to: url, options: .atomic)
            }
            revision += 1
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - 레벨별 비용/시간 조회 (static_data → 앱 내장 데이터 순)

struct UpgradeLevelData {
    let cost: Int?
    let seconds: Double?
    let resource: UpgradeResource
}

enum UpgradeDataProvider {
    static func levelData(id: Int, category: String, target: Int, store: UpgradeStaticDataStore) -> UpgradeLevelData? {
        if let entity = store.entity(id), let data = staticLevelData(entity, category: category, target: target) {
            return data
        }
        return BundledUpgradeData.levelData(id: id, category: category, target: target)
    }

    private static func staticLevelData(_ entity: UpgradeStaticEntity, category: String, target: Int) -> UpgradeLevelData? {
        let rowLevel = entity.fromSemantic ? target - 1 : target
        guard let row = entity.levels.first(where: { $0.level == rowLevel }),
              row.cost != nil || row.seconds != nil else { return nil }
        let resource = UpgradeResource(raw: row.resource ?? entity.resource, fallback: defaultResource(for: category))
        return UpgradeLevelData(cost: row.cost.map { Int($0.rounded()) }, seconds: row.seconds, resource: resource)
    }

    static func defaultResource(for category: String) -> UpgradeResource {
        switch category {
        case "heroes", "pets": return .darkElixir
        case "buildings", "crafted_defenses": return .gold
        default: return .elixir
        }
    }
}

/// 앱에 들어 있는 parsed_json_files (오프라인/데이터 누락 대비)
enum BundledUpgradeData {
    private static var cache: [String: [Int: [String: Any]]] = [:]

    private static func entries(_ file: String) -> [Int: [String: Any]] {
        if let cached = cache[file] { return cached }
        var result: [Int: [String: Any]] = [:]
        for base in DataService.candidateFolderURLs(named: "parsed_json_files") {
            let url = base.appendingPathComponent("\(file).json")
            guard let data = try? Data(contentsOf: url),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            for entry in list {
                if let id = integer(entry["id"]), result[id] == nil { result[id] = entry }
            }
            break
        }
        cache[file] = result
        return result
    }

    static func levelData(id: Int, category: String, target: Int) -> UpgradeLevelData? {
        switch category {
        case "buildings":
            return read(file: "buildings", id: id, rowLevel: target,
                        costKey: "buildCost", timeKey: "buildTimeSeconds", resourceKey: "buildResource", category: category)
        case "crafted_defenses":
            return read(file: "seasonal_defense_modules", id: id, rowLevel: target,
                        costKey: "BuildCost", timeKey: "buildTimeSeconds", resourceKey: "BuildResource", category: category)
        case "troops", "dark_troops", "squads", "siege_machines":
            return read(file: "characters", id: id, rowLevel: target - 1,
                        costKey: "UpgradeCost", timeKey: "upgradeTimeSeconds", resourceKey: "UpgradeResource", category: category)
        case "spells":
            return read(file: "spells", id: id, rowLevel: target - 1,
                        costKey: "UpgradeCost", timeKey: "upgradeTimeSeconds", resourceKey: "UpgradeResource", category: category)
        case "heroes":
            return read(file: "heroes", id: id, rowLevel: target - 1,
                        costKey: "UpgradeCost", timeKey: "upgradeTimeSeconds", resourceKey: "UpgradeResource", category: category)
        case "pets":
            return read(file: "pets", id: id, rowLevel: target - 1,
                        costKey: "UpgradeCost", timeKey: "upgradeTimeSeconds", resourceKey: "UpgradeResource", category: category)
        default:
            return nil
        }
    }

    private static func read(file: String, id: Int, rowLevel: Int, costKey: String, timeKey: String,
                             resourceKey: String, category: String) -> UpgradeLevelData? {
        guard let entry = entries(file)[id],
              let levels = entry["levels"] as? [[String: Any]],
              let row = levels.first(where: { integer($0["level"]) == rowLevel }) else { return nil }
        let cost = integer(row[costKey])
        let seconds = integer(row[timeKey])
        guard cost != nil || seconds != nil else { return nil }
        // 자원 종류는 첫 줄에만 적혀 있는 경우가 많아서 항목 전체에서 처음 나오는 값을 사용
        var rawResource: String? = nil
        if let own = row[resourceKey] as? String, !own.isEmpty {
            rawResource = own
        } else {
            rawResource = levels.compactMap { $0[resourceKey] as? String }.first { !$0.isEmpty }
        }
        let resource = UpgradeResource(raw: rawResource, fallback: UpgradeDataProvider.defaultResource(for: category))
        return UpgradeLevelData(cost: cost, seconds: seconds.map { Double($0) }, resource: resource)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

// MARK: - 화면용 모델

struct UpgradeLevelLine: Identifiable {
    let level: Int
    let cost: Int?
    let seconds: Double?
    let resource: UpgradeResource
    var id: Int { level }
}

struct UpgradeProgressInfo {
    let targetLevel: Int
    let remaining: TimeInterval
    let fraction: Double
}

struct UpgradeTotals {
    var seconds: Double = 0
    var levels: Int = 0
    var costs: [UpgradeResource: Int] = [:]

    mutating func add(_ line: UpgradeLevelLine) {
        levels += 1
        seconds += line.seconds ?? 0
        if let cost = line.cost {
            costs[line.resource, default: 0] += cost
        }
    }

    mutating func merge(_ other: UpgradeTotals) {
        levels += other.levels
        seconds += other.seconds
        for (resource, value) in other.costs {
            costs[resource, default: 0] += value
        }
    }

    /// 골드 → 엘릭서 → 다크 엘릭서 순서로 0이 아닌 것만
    var costSegments: [(resource: UpgradeResource, value: Int)] {
        UpgradeResource.allCases.compactMap { resource in
            guard let value = costs[resource], value > 0 else { return nil }
            return (resource, value)
        }
    }
}

struct UpgradeInstanceModel: Identifiable {
    let id: String
    let imageName: String
    let label: String?
    let current: Int
    let cap: Int
    let isMissing: Bool
    let progress: UpgradeProgressInfo?
    let lines: [UpgradeLevelLine]

    var isMaxed: Bool { lines.isEmpty && progress == nil }

    var totals: UpgradeTotals {
        var totals = UpgradeTotals()
        for line in lines { totals.add(line) }
        return totals
    }
}

struct UpgradeItemModel: Identifiable {
    let id: String
    let name: String
    let instances: [UpgradeInstanceModel]
}

struct UpgradeSubsectionModel: Identifiable {
    let id: String
    let title: String?
    let items: [UpgradeItemModel]

    var totals: UpgradeTotals {
        var totals = UpgradeTotals()
        for item in items {
            for instance in item.instances { totals.merge(instance.totals) }
        }
        return totals
    }
}

struct UpgradeSectionModel: Identifiable {
    let id: String
    let title: String
    let subsections: [UpgradeSubsectionModel]

    var totals: UpgradeTotals {
        var totals = UpgradeTotals()
        for subsection in subsections { totals.merge(subsection.totals) }
        return totals
    }
}

// MARK: - 모델 만들기

enum UpgradeSummaryBuilder {
    struct Context {
        let export: CoCExport
        let townHall: Int
        let goldPass: Int
        let store: UpgradeStaticDataStore
        let upgrades: [BuildingUpgrade]
        let townHallCounts: TownHallLevelCounts?
        let nameToId: [String: Int]
        let showMaxed: Bool
    }

    private struct OwnedEntry {
        let level: Int
        let timer: Int?
    }

    private struct SubsectionSpec {
        let title: String?
        let catalogID: String
        let groupID: String?
    }

    private struct SectionSpec {
        let id: String
        let title: String
        let subsections: [SubsectionSpec]
    }

    // 표시 순서: Heroes, Lab(Troops, Spells, Dark Troops, Sieges, Squads), Pets, Army, Defenses, Guardians, Resources, Crafted Def.
    private static let specs: [SectionSpec] = [
        SectionSpec(id: "heroes", title: "Heroes", subsections: [
            SubsectionSpec(title: nil, catalogID: "heroes", groupID: nil)
        ]),
        SectionSpec(id: "lab", title: "Lab", subsections: [
            SubsectionSpec(title: "Troops", catalogID: "troops", groupID: nil),
            SubsectionSpec(title: "Spells", catalogID: "spells", groupID: nil),
            SubsectionSpec(title: "Dark Troops", catalogID: "dark_troops", groupID: nil),
            SubsectionSpec(title: "Sieges", catalogID: "siege_machines", groupID: nil),
            SubsectionSpec(title: "Squads", catalogID: "squads", groupID: nil)
        ]),
        SectionSpec(id: "pets", title: "Pets", subsections: [
            SubsectionSpec(title: nil, catalogID: "pets", groupID: nil)
        ]),
        SectionSpec(id: "army", title: "Army", subsections: [
            SubsectionSpec(title: nil, catalogID: "buildings", groupID: "army")
        ]),
        SectionSpec(id: "defenses", title: "Defenses", subsections: [
            SubsectionSpec(title: nil, catalogID: "buildings", groupID: "defense")
        ]),
        SectionSpec(id: "guardians", title: "Guardians", subsections: [
            SubsectionSpec(title: nil, catalogID: "guardians", groupID: nil)
        ]),
        SectionSpec(id: "resources", title: "Resources", subsections: [
            SubsectionSpec(title: nil, catalogID: "buildings", groupID: "resource")
        ]),
        SectionSpec(id: "crafted", title: "Crafted Def.", subsections: [
            SubsectionSpec(title: nil, catalogID: "crafted_defenses", groupID: nil)
        ])
    ]

    static var sectionList: [(id: String, title: String)] {
        specs.map { (id: $0.id, title: $0.title) }
    }

    static func build(context: Context) -> [UpgradeSectionModel] {
        var pool = context.upgrades
        var result: [UpgradeSectionModel] = []

        for spec in specs {
            var subsections: [UpgradeSubsectionModel] = []
            for sub in spec.subsections {
                guard let section = ProgressCatalog.sections.first(where: { $0.id == sub.catalogID }) else { continue }
                let items = buildItems(section: section, groupID: sub.groupID, context: context, pool: &pool)
                if items.isEmpty { continue }
                subsections.append(UpgradeSubsectionModel(id: "\(spec.id)-\(sub.catalogID)", title: sub.title, items: items))
            }
            if subsections.isEmpty { continue }
            result.append(UpgradeSectionModel(id: spec.id, title: spec.title, subsections: subsections))
        }
        return result
    }

    private static func buildItems(section: ProgressCatalog.Section, groupID: String?, context: Context,
                                   pool: inout [BuildingUpgrade]) -> [UpgradeItemModel] {
        let owned = ownedEntries(for: section, export: context.export)
        var items: [UpgradeItemModel] = []

        for group in section.groups {
            if let groupID, group.id != groupID { continue }
            for item in group.items {
                let instances: [UpgradeInstanceModel]
                if section.id == "crafted_defenses" {
                    instances = craftedInstances(item: item, context: context, pool: &pool)
                } else {
                    instances = standardInstances(section: section, item: item, entries: owned[item.id] ?? [],
                                                  context: context, pool: &pool)
                }
                let visible = context.showMaxed ? instances : instances.filter { !$0.isMaxed }
                if visible.isEmpty { continue }
                items.append(UpgradeItemModel(id: "\(section.id)-\(item.id)", name: koName(item.name), instances: visible))
            }
        }
        return items
    }

    // MARK: 보유 현황

    private static func ownedEntries(for section: ProgressCatalog.Section, export: CoCExport) -> [Int: [OwnedEntry]] {
        var result: [Int: [OwnedEntry]] = [:]
        switch section.exportKey {
        case "units":
            for unit in export.units ?? [] {
                result[unit.data, default: []].append(OwnedEntry(level: unit.lvl, timer: unit.timer))
            }
        case "siege_machines":
            for unit in export.siegeMachines ?? [] {
                result[unit.data, default: []].append(OwnedEntry(level: unit.lvl, timer: unit.timer))
            }
        case "spells":
            for spell in export.spells ?? [] {
                result[spell.data, default: []].append(OwnedEntry(level: spell.lvl, timer: spell.timer))
            }
        case "heroes":
            for hero in export.heroes ?? [] {
                result[hero.data, default: []].append(OwnedEntry(level: hero.lvl, timer: hero.timer))
            }
        case "pets":
            for pet in export.pets ?? [] {
                result[pet.data, default: []].append(OwnedEntry(level: pet.lvl, timer: pet.timer))
            }
        case "guardians":
            for guardian in export.guardians ?? [] {
                result[guardian.data, default: []].append(OwnedEntry(level: guardian.lvl ?? 1, timer: guardian.timer))
            }
        case "buildings":
            for building in export.buildings ?? [] {
                guard let level = building.lvl else { continue }
                let count = max(building.cnt ?? 1, 1)
                for copy in 0..<count {
                    // 타이머(업그레이드 중)는 한 채에만 해당
                    result[building.data, default: []].append(OwnedEntry(level: level, timer: copy == 0 ? building.timer : nil))
                }
            }
        default:
            break
        }
        return result
    }

    private static func requiredCount(for itemID: Int, context: Context) -> Int {
        guard let counts = context.townHallCounts?.counts else { return 0 }
        var total = 0
        for (name, count) in counts where context.nameToId[name.lowercased()] == itemID {
            total += count
        }
        return total
    }

    // 합체 건물 (합체하면 재료 건물이 사라지므로 미건설 칸에서 뺀다)
    private enum MergeID {
        static let cannon = 1000008
        static let archerTower = 1000009
        static let eagleArtillery = 1000031
        static let scattershot = 1000067
        static let multiGearTower = 1000079
        static let multiArcherTower = 1000084
        static let ricochetCannon = 1000085
        static let firecrackerTower = 1000108
    }

    private static func ownedBuildingCount(_ id: Int, export: CoCExport) -> Int {
        var total = 0
        for building in export.buildings ?? [] where building.data == id && building.lvl != nil {
            total += max(building.cnt ?? 1, 1)
        }
        return total
    }

    /// 미건설로 보여줄 칸 수 (합체 건물 규칙 반영)
    private static func missingCount(for itemID: Int, ownedHere: Int, context: Context) -> Int {
        var missing = max(requiredCount(for: itemID, context: context) - ownedHere, 0)
        let export = context.export

        switch itemID {
        case MergeID.eagleArtillery:
            // 마을회관 17 이상: 독수리 타워는 미건설이면 숨김
            if context.townHall >= 17 { missing = 0 }
        case MergeID.cannon:
            missing -= 2 * ownedBuildingCount(MergeID.ricochetCannon, export: export)
            missing -= ownedBuildingCount(MergeID.multiGearTower, export: export)
        case MergeID.archerTower:
            missing -= 2 * ownedBuildingCount(MergeID.multiArcherTower, export: export)
            missing -= ownedBuildingCount(MergeID.multiGearTower, export: export)
            missing -= ownedBuildingCount(MergeID.firecrackerTower, export: export)
        case MergeID.scattershot:
            missing -= ownedBuildingCount(MergeID.firecrackerTower, export: export)
        default:
            break
        }
        return max(missing, 0)
    }

    // MARK: 일반 항목 (영웅/연구소/펫/건물 등)

    private static func standardInstances(section: ProgressCatalog.Section, item: ProgressCatalog.Item,
                                          entries: [OwnedEntry], context: Context,
                                          pool: inout [BuildingUpgrade]) -> [UpgradeInstanceModel] {
        let cap = item.maxLevel(at: context.townHall)
        let isBuilding = section.id == "buildings"
        if cap <= 0 && entries.isEmpty { return [] }

        var instances: [UpgradeInstanceModel] = []
        let sorted = entries.sorted { $0.level < $1.level }
        for (index, entry) in sorted.enumerated() {
            instances.append(makeInstance(
                id: "\(section.id)-\(item.id)-\(index)", item: item, dataID: item.id, category: section.id,
                label: nil, current: entry.level, timer: entry.timer, cap: cap, isMissing: false,
                context: context, pool: &pool))
        }

        if isBuilding && cap > 0 {
            let missing = missingCount(for: item.id, ownedHere: entries.count, context: context)
            if missing > 0 {
                for index in 0..<missing {
                    instances.append(makeInstance(
                        id: "\(section.id)-\(item.id)-missing\(index)", item: item, dataID: item.id, category: section.id,
                        label: nil, current: 0, timer: nil, cap: cap, isMissing: true,
                        context: context, pool: &pool))
                }
            }
        }
        return instances
    }

    // MARK: 크래프트 방어 (모듈별)

    private static func craftedInstances(item: ProgressCatalog.Item, context: Context,
                                         pool: inout [BuildingUpgrade]) -> [UpgradeInstanceModel] {
        let building = (context.export.buildings ?? []).first { building in
            building.types?.contains(where: { $0.data == item.id }) == true
        }
        guard let modules = building?.types?.first(where: { $0.data == item.id })?.modules, !modules.isEmpty else {
            return []
        }
        var instances: [UpgradeInstanceModel] = []
        for (index, moduleID) in item.moduleIds.enumerated() {
            let module = modules.first { $0.data == moduleID }
            let cap = index < item.moduleMaximums.count ? item.moduleMaximums[index] : 0
            instances.append(makeInstance(
                id: "crafted-\(item.id)-\(index)", item: item, dataID: moduleID, category: "crafted_defenses",
                label: "모듈 \(index + 1)", current: module?.lvl ?? 0, timer: module?.timer, cap: cap, isMissing: false,
                context: context, pool: &pool))
        }
        return instances
    }

    // MARK: 공통: 한 칸(건물 1채 / 유닛 1개)의 남은 레벨 계산

    private static func makeInstance(id: String, item: ProgressCatalog.Item, dataID: Int, category: String,
                                     label: String?, current: Int, timer: Int?, cap: Int, isMissing: Bool,
                                     context: Context, pool: inout [BuildingUpgrade]) -> UpgradeInstanceModel {
        let factor = max(0, 1 - Double(context.goldPass) / 100)

        func line(for target: Int) -> UpgradeLevelLine {
            let data = UpgradeDataProvider.levelData(id: dataID, category: category, target: target, store: context.store)
            let cost = data?.cost.map { Int((Double($0) * factor).rounded()) }
            let seconds = data?.seconds.map { $0 * factor }
            return UpgradeLevelLine(level: target, cost: cost, seconds: seconds,
                                    resource: data?.resource ?? UpgradeDataProvider.defaultResource(for: category))
        }

        let inProgressTarget: Int? = timer != nil ? current + 1 : nil
        let startLevel = (inProgressTarget ?? current) + 1

        var lines: [UpgradeLevelLine] = []
        if startLevel <= cap {
            for target in startLevel...cap { lines.append(line(for: target)) }
        }

        var progress: UpgradeProgressInfo? = nil
        if let target = inProgressTarget, let timer {
            if let matchIndex = pool.firstIndex(where: {
                $0.dataId == dataID && $0.superchargeTargetLevel == nil && $0.targetLevel == target
            }) {
                let upgrade = pool.remove(at: matchIndex)
                let total = max(upgrade.effectiveTotalDuration(goldPassBoost: context.goldPass), 1)
                let remaining = max(0, upgrade.endTime.timeIntervalSinceNow)
                let fraction = min(max(1 - remaining / total, 0), 1)
                progress = UpgradeProgressInfo(targetLevel: target, remaining: remaining, fraction: fraction)
            } else {
                // 앱에 진행 중 정보가 없으면 가져온 JSON의 남은 시간(timer)으로 계산
                let exportTime = Double(context.export.timestamp ?? 0)
                let elapsed = exportTime > 0 ? max(0, Date().timeIntervalSince1970 - exportTime) : 0
                let remaining = max(0, Double(timer) - elapsed)
                let total = line(for: target).seconds ?? remaining
                let fraction = total > 0 ? min(max(1 - remaining / total, 0), 1) : 0
                progress = UpgradeProgressInfo(targetLevel: target, remaining: remaining, fraction: fraction)
            }
        }

        return UpgradeInstanceModel(
            id: id,
            imageName: item.assetName(for: max(current, 1)),
            label: label,
            current: current,
            cap: cap,
            isMissing: isMissing,
            progress: progress,
            lines: lines
        )
    }
}

// MARK: - 화면

struct UpgradeSummaryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataService: DataService
    @ObservedObject private var store = UpgradeStaticDataStore.shared

    @AppStorage("upgradeSectionOrder") private var storedOrder = ""
    @AppStorage("upgradeHiddenSections") private var storedHidden = ""
    @AppStorage("upgradeShowMaxed") private var showMaxed = true

    @State private var sections: [UpgradeSectionModel] = []
    @State private var isLoading = true
    @State private var hasExport = true
    @State private var showEditSheet = false

    private struct ReloadKey: Hashable {
        let profileID: UUID?
        let importDate: Date?
        let goldPass: Int
        let revision: Int
        let upgradeCount: Int
        let showMaxed: Bool
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            profileID: dataService.selectedProfileID,
            importDate: dataService.currentProfile?.lastImportDate,
            goldPass: dataService.goldPassBoost,
            revision: store.revision,
            upgradeCount: dataService.currentProfile?.activeUpgrades.count ?? 0,
            showMaxed: showMaxed
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if !hasExport {
                        Text("Import your village export to see remaining upgrades.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        ForEach(visibleSections) { section in
                            UpgradeSectionCard(section: section)
                        }
                        dataSourceFooter
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Upgrades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Edit Upgrades Cards")
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refreshIfNeeded(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Upgrade Data")
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(store.isRefreshing)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProfileSwitcherMenu()
                }
            }
            .sheet(isPresented: $showEditSheet) {
                UpgradeCardsEditSheet(order: orderBinding, hidden: hiddenBinding, showMaxed: $showMaxed)
            }
            .task(id: reloadKey) {
                await rebuild()
            }
            .task {
                await store.refreshIfNeeded()
            }
        }
    }

    // MARK: 카드 순서 / 숨김

    private var resolvedOrder: [String] {
        let defaults = UpgradeSummaryBuilder.sectionList.map { $0.id }
        var result: [String] = []
        for id in storedOrder.split(separator: ",").map(String.init) where defaults.contains(id) && !result.contains(id) {
            result.append(id)
        }
        for id in defaults where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    private var hiddenSet: Set<String> {
        Set(storedHidden.split(separator: ",").map(String.init))
    }

    private var orderBinding: Binding<[String]> {
        Binding(
            get: { resolvedOrder },
            set: { storedOrder = $0.joined(separator: ",") }
        )
    }

    private var hiddenBinding: Binding<Set<String>> {
        Binding(
            get: { hiddenSet },
            set: { storedHidden = $0.sorted().joined(separator: ",") }
        )
    }

    private var visibleSections: [UpgradeSectionModel] {
        let hidden = hiddenSet
        var result: [UpgradeSectionModel] = []
        for id in resolvedOrder where !hidden.contains(id) {
            if let section = sections.first(where: { $0.id == id }) {
                result.append(section)
            }
        }
        return result
    }

    // MARK: 위쪽 요약

    private var headerCard: some View {
        let profileName = dataService.currentProfile.map { dataService.displayName(for: $0) } ?? "Player"
        let goldPass = dataService.goldPassBoost
        return HStack(spacing: 10) {
            Image(goldPass == 0 ? "profile/free_pass" : "profile/gold_pass")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profileName).font(.subheadline.weight(.semibold))
                if goldPass == 0 {
                    Text("골드패스 없음")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 60.0)) { timeline in
                        Text("골드패스 \(goldPass)% 적용 (\(UpgradeGoldPass.remainingText(from: timeline.date)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .upgradeCardStyle()
    }

    private var dataSourceFooter: some View {
        VStack(spacing: 4) {
            if store.isRefreshing {
                Text("최신 데이터 불러오는 중…")
            } else if let fetchedAt = store.fetchedAt {
                Text("데이터: ClashKing static_data.json · \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("데이터: 앱 내장 데이터 (static_data.json을 아직 받지 못했어요)")
            }
            if let error = store.lastError {
                Text("업데이트 실패: \(error)")
                    .foregroundColor(.orange)
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: 계산

    private func currentTownHall(for export: CoCExport) -> Int {
        if let level = dataService.cachedProfile?.townHallLevel, level > 0 { return level }
        return dataService.inferTownHallLevel(from: export)
    }

    private func rebuild() async {
        isLoading = true
        await Task.yield()
        guard !Task.isCancelled else { return }

        guard let raw = dataService.currentProfile?.rawJSON, !raw.isEmpty,
              let export = dataService.decodeExport(from: raw) else {
            sections = []
            hasExport = false
            isLoading = false
            return
        }
        hasExport = true

        let townHall = currentTownHall(for: export)
        let counts = (dataService.cachedTownHallLevels ?? []).first { $0.level == townHall }
        let context = UpgradeSummaryBuilder.Context(
            export: export,
            townHall: townHall,
            goldPass: dataService.goldPassBoost,
            store: store,
            upgrades: dataService.currentProfile?.activeUpgrades ?? dataService.activeUpgrades,
            townHallCounts: counts,
            nameToId: dataService.cachedBuildingNameToId ?? [:],
            showMaxed: showMaxed
        )
        sections = UpgradeSummaryBuilder.build(context: context)
        isLoading = false
    }
}

// MARK: - 카드 / 행 뷰

private extension View {
    func upgradeCardStyle() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.tertiarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.separator).opacity(0.6), lineWidth: 1))
    }
}

private struct UpgradeSectionCard: View {
    let section: UpgradeSectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3.bold())

            ForEach(section.subsections) { subsection in
                VStack(alignment: .leading, spacing: 10) {
                    if let title = subsection.title {
                        Text(title)
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                    }
                    ForEach(subsection.items) { item in
                        UpgradeItemCard(item: item)
                    }
                    if section.subsections.count > 1 {
                        UpgradeTotalsBar(title: "\(subsection.title ?? section.title) 합계", totals: subsection.totals, emphasized: false)
                    }
                }
            }

            UpgradeTotalsBar(title: "\(section.title) 총 시간", totals: section.totals, emphasized: true)
        }
        .upgradeCardStyle()
    }
}

private struct UpgradeItemCard: View {
    let item: UpgradeItemModel

    var body: some View {
        VStack(spacing: 0) {
            Text(item.name)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color(.systemFill))

            ForEach(Array(item.instances.enumerated()), id: \.element.id) { index, instance in
                if index > 0 {
                    Rectangle().fill(Color(.separator)).frame(height: 1)
                }
                UpgradeInstanceRow(instance: instance, shaded: index % 2 == 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
    }
}

private struct UpgradeInstanceRow: View {
    let instance: UpgradeInstanceModel
    let shaded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leftBlock
                .frame(width: 88)
            Rectangle().fill(Color(.separator)).frame(width: 1)
            rightBlock
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var leftBlock: some View {
        VStack(spacing: 1) {
            Image(instance.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .saturation(instance.isMissing ? 0 : 1)
                .opacity(instance.isMissing ? 0.45 : 1)
            Text("\(instance.current)/\(instance.cap)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
            if let label = instance.label {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if instance.isMissing {
                Text("미건설")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
    }

    private var rightBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let progress = instance.progress {
                UpgradeProgressHeader(progress: progress)
            }
            if instance.isMaxed {
                Text("최대 레벨")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if !instance.lines.isEmpty {
                VStack(spacing: 1) {
                    ForEach(instance.lines) { line in
                        UpgradeLevelLineRow(line: line)
                    }
                }
                UpgradeInstanceTotalBar(totals: instance.totals)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct UpgradeProgressHeader: View {
    let progress: UpgradeProgressInfo

    var body: some View {
        let percent = Int((progress.fraction * 100).rounded(.down))
        return VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill))
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat(progress.fraction))
                }
                Text("\(percent)%")
                    .font(.caption.bold())
                    .padding(.leading, 8)
            }
            .frame(height: 18)

            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.bold())
                Text("\(progress.targetLevel) - \(UpgradeFormat.remaining(progress.remaining))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
    }
}

private struct UpgradeLevelLineRow: View {
    let line: UpgradeLevelLine

    var body: some View {
        HStack(spacing: 4) {
            Text("Lv \(line.level):")
                .foregroundColor(.secondary)
                .frame(width: 46, alignment: .leading)
            Text(line.cost.map { UpgradeFormat.cost($0) } ?? "—")
                .fontWeight(.bold)
                .foregroundColor(line.resource.color)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(line.seconds.map { UpgradeFormat.duration($0) } ?? "—")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.system(size: 12).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct UpgradeInstanceTotalBar: View {
    let totals: UpgradeTotals

    var body: some View {
        HStack(spacing: 4) {
            Text("\(totals.levels)레벨")
            Text("-")
            ForEach(Array(totals.costSegments.enumerated()), id: \.offset) { index, segment in
                if index > 0 { Text("+") }
                Text(UpgradeFormat.cost(segment.value))
                    .fontWeight(.bold)
                    .foregroundColor(segment.resource.color)
            }
            Text("-")
            Text(UpgradeFormat.duration(totals.seconds))
        }
        .font(.system(size: 11.5).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct UpgradeTotalsBar: View {
    let title: String
    let totals: UpgradeTotals
    let emphasized: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .foregroundColor(emphasized ? .primary : .secondary)
                Spacer()
                Text(UpgradeFormat.duration(totals.seconds))
                    .fontWeight(.bold)
            }
            .font(emphasized ? .subheadline : .caption)

            if !totals.costSegments.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(totals.costSegments.enumerated()), id: \.offset) { _, segment in
                        HStack(spacing: 4) {
                            Text(segment.resource.koreanName)
                                .foregroundColor(.secondary)
                            Text(UpgradeFormat.cost(segment.value))
                                .fontWeight(.bold)
                                .foregroundColor(segment.resource.color)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
        .padding(emphasized ? 12 : 8)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))
    }
}


// MARK: - 골드패스 남은 시간 (Profile 화면과 동일: 매월 1일 08:00 GMT 초기화)

enum UpgradeGoldPass {
    static func remainingText(from date: Date) -> String {
        let diff = Int(nextResetDate(for: date).timeIntervalSince(date))
        if diff <= 0 { return "Resetting..." }

        let days = diff / 86400
        let hours = (diff % 86400) / 3600
        let minutes = (diff % 3600) / 60
        let seconds = diff % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m \(seconds)s"
        }
    }

    private static func nextResetDate(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month], from: date)

        var resetComponents = DateComponents()
        resetComponents.year = components.year
        resetComponents.month = components.month
        resetComponents.day = 1
        resetComponents.hour = 8
        resetComponents.minute = 0
        resetComponents.second = 0

        let resetThisMonth = calendar.date(from: resetComponents) ?? date
        if date < resetThisMonth {
            return resetThisMonth
        } else {
            return calendar.date(byAdding: .month, value: 1, to: resetThisMonth) ?? resetThisMonth
        }
    }
}

// MARK: - Edit Upgrades Cards (섹션 on/off, 순서, 최대 레벨 표시)

private struct UpgradeCardsEditSheet: View {
    @Binding var order: [String]
    @Binding var hidden: Set<String>
    @Binding var showMaxed: Bool
    @Environment(\.dismiss) private var dismiss

    private func title(for id: String) -> String {
        UpgradeSummaryBuilder.sectionList.first(where: { $0.id == id })?.title ?? id
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Visible Cards") {
                    ForEach(order, id: \.self) { id in
                        HStack {
                            Text(title(for: id))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !hidden.contains(id) },
                                set: { isVisible in
                                    if isVisible {
                                        hidden.remove(id)
                                    } else {
                                        hidden.insert(id)
                                    }
                                }
                            ))
                        }
                    }
                    .onMove { offsets, destination in
                        order.move(fromOffsets: offsets, toOffset: destination)
                    }
                }

                Section {
                    Toggle("Show Max Level", isOn: $showMaxed)
                } footer: {
                    Text("Turn off to hide items that are already at max level.")
                }

                Section {
                    Button("Reset to Default") {
                        order = UpgradeSummaryBuilder.sectionList.map { $0.id }
                        hidden.removeAll()
                        showMaxed = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Upgrades Cards")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
