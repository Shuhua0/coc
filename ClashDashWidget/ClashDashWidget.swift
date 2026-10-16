//
//  ClashDashWidget.swift
//  ClashDashWidget
//
//  Created by Zachary Buschmann on 1/7/26.
//

import WidgetKit
import SwiftUI
import UIKit
import AppIntents
#if canImport(ControlCenter)
import ControlCenter
#endif

private func trimmedWidgetImage(named name: String) -> Image {
    #if canImport(UIKit)
    if let uiImage = UIImage(named: name) {
        return Image(uiImage: trimWidgetTransparentEdges(uiImage))
    }
    #endif
    return Image(name)
}

private extension Image {
    @ViewBuilder
    func clashWidgetTintAwareRendering() -> some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, visionOS 26.0, *) {
            self.widgetAccentedRenderingMode(.accentedDesaturated)
        } else {
            self
        }
    }
}

private func trimWidgetTransparentEdges(_ image: UIImage) -> UIImage {
    guard let cgImage = image.cgImage else { return image }

    let width = cgImage.width
    let height = cgImage.height

    guard let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data as Data? else {
        return image
    }

    let bytesPerPixel = 4
    let pixelData = [UInt8](data)

    var minX = width
    var maxX = -1
    var minY = height
    var maxY = -1

    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = (y * width + x) * bytesPerPixel
            guard pixelIndex + 3 < pixelData.count else { continue }

            let alpha = pixelData[pixelIndex + 3]
            if alpha > 5 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
    }

    guard minX <= maxX && minY <= maxY && minX < width && minY < height else {
        return image
    }

    let trimRect = CGRect(
        x: CGFloat(minX),
        y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1),
        height: CGFloat(maxY - minY + 1)
    )

    guard let croppedCG = cgImage.cropping(to: trimRect) else { return image }
    return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
}

// MARK: - Widget Configuration Intent
// MARK: - Profile Selection via AppEntity (supports dynamic display names)
struct ProfileEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static var defaultQuery = ProfileEntityQuery()

    var id: String   // UUID string, or "automatic"
    var displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }

    var isAutomatic: Bool { id == "automatic" }

    func profileID() -> UUID? {
        if isAutomatic { return nil }
        return UUID(uuidString: id)
    }

    /// Resolve a saved UserDefaults string to a profile UUID.
    /// Handles both new UUID format and legacy "profileN" format.
    static func resolveProfileID(from savedSelection: String) -> UUID? {
        if savedSelection == "automatic" { return nil }
        // New format: raw UUID string
        if let uuid = UUID(uuidString: savedSelection) { return uuid }
        // Legacy "profileN" format
        let legacyCases = ["profile1", "profile2", "profile3", "profile4", "profile5",
                           "profile6", "profile7", "profile8", "profile9", "profile10"]
        if let index = legacyCases.firstIndex(of: savedSelection),
           let state = PersistentStore.loadState(),
           index < state.profiles.count {
            return state.profiles[index].id
        }
        return nil
    }
}

struct ProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [ProfileEntity.ID]) async throws -> [ProfileEntity] {
        let all = allEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        return allEntities()
    }

    func defaultResult() async -> ProfileEntity? {
        return ProfileEntity(id: "automatic", displayName: "Last Opened Profile")
    }

    private func allEntities() -> [ProfileEntity] {
        var entities = [ProfileEntity(id: "automatic", displayName: "Last Opened Profile")]
        if let state = PersistentStore.loadState() {
            for profile in state.profiles {
                let name: String
                if !profile.displayName.isEmpty {
                    name = profile.displayName
                } else if !profile.tag.isEmpty {
                    name = "#\(profile.tag)"
                } else {
                    name = "Profile"
                }
                entities.append(ProfileEntity(id: profile.id.uuidString, displayName: name))
            }
        }
        return entities
    }
}

struct WidgetProfileIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Profile"
    static let description: IntentDescription = "Choose which profile this widget displays"
    
    @Parameter(title: "Profile", description: "Select a profile or leave empty for automatic")
    var selectedProfile: ProfileEntity?
    
    func perform() async throws -> some IntentResult {
        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        if let defaults = UserDefaults(suiteName: appGroup) {
            if let profile = selectedProfile, !profile.isAutomatic {
                // Save the selected profile UUID
                defaults.set(profile.id, forKey: "widget_profile_selection")
            } else {
                // Clear profile selection (use automatic)
                defaults.removeObject(forKey: "widget_profile_selection")
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}

// MARK: - Closest Upgrade Widget Intent
enum UpgradeTypeSelection: String, AppEnum, CaseDisplayRepresentable {
    case builders = "builders"
    case lab = "lab"
    case pets = "pets"
    case builderBase = "builderBase"
    case starLab = "starLab"
    case homeOverall = "homeOverall"
    case builderBaseOverall = "builderBaseOverall"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Upgrade Type"
    static var caseDisplayRepresentations: [UpgradeTypeSelection: DisplayRepresentation] = [
        .builders: DisplayRepresentation(title: LocalizedStringResource("Builders")),
        .lab: DisplayRepresentation(title: LocalizedStringResource("Lab")),
        .pets: DisplayRepresentation(title: LocalizedStringResource("Pet House")),
        .builderBase: DisplayRepresentation(title: LocalizedStringResource("Builder Base Builders")),
        .starLab: DisplayRepresentation(title: LocalizedStringResource("Star Lab")),
        .homeOverall: DisplayRepresentation(title: LocalizedStringResource("Home Overall (Builder/Lab/Pets)")),
        .builderBaseOverall: DisplayRepresentation(title: LocalizedStringResource("Builder Base Overall (Builder/Star Lab)"))
    ]
}

struct ClosestUpgradeIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Closest Upgrade"
    static let description: IntentDescription = "Show the closest upgrade to finishing"

    @Parameter(title: "Type", description: "Select upgrade type")
    var upgradeType: UpgradeTypeSelection?

    @Parameter(title: "Profile", description: "Select a profile or leave empty for automatic")
    var selectedProfile: ProfileEntity?
}

// MARK: - Import Clipboard Intent (Lock Screen Action)
struct ImportClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Clipboard"
    static let description = IntentDescription("Import village data from clipboard")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        if let defaults = UserDefaults(suiteName: appGroup) {
            defaults.set(true, forKey: "widget_import_requested")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Tap to Refresh
// Per-profile setting (Profile Settings > "Tap widget to refresh").
// ON  -> tapping a widget reloads its timeline in place (no app launch).
// OFF -> tapping opens the app (previous behavior).
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Widget"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private struct WidgetTapActionModifier: ViewModifier {
    let refresh: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if refresh {
            Button(intent: RefreshWidgetIntent()) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content.widgetURL(URL(string: "clashdash://refresh"))
        }
    }
}

private extension View {
    func widgetTapAction(refresh: Bool) -> some View {
        modifier(WidgetTapActionModifier(refresh: refresh))
    }
}

/// Resolves which profile a widget is showing (same rules as the providers).
private func widgetProfile(for configuration: WidgetProfileIntent) -> PlayerAccount? {
    guard let state = PersistentStore.loadState() else { return nil }
    var selectedID: UUID? = nil
    if let selected = configuration.selectedProfile,
       !selected.isAutomatic,
       let id = selected.profileID() {
        selectedID = id
    } else if let defaults = UserDefaults(suiteName: PersistentStore.appGroupIdentifier),
              let saved = defaults.string(forKey: "widget_profile_selection"),
              let id = ProfileEntity.resolveProfileID(from: saved) {
        selectedID = id
    }
    return selectedID.flatMap { id in state.profiles.first(where: { $0.id == id }) } ?? state.currentProfile
}

private func widgetTapRefreshEnabled(for configuration: WidgetProfileIntent) -> Bool {
    widgetProfile(for: configuration)?.widgetTapRefresh ?? true
}

/// "Nickname (#TAG)" using the in-game name when known.
private func widgetNicknameLabel(for configuration: WidgetProfileIntent) -> String {
    widgetNicknameLabel(for: widgetProfile(for: configuration))
}

private func widgetNicknameLabel(for profile: PlayerAccount?) -> String {
    guard let profile else { return "" }
    let tag = profile.tag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
        .uppercased()
    let tagLabel = tag.isEmpty ? "" : "#\(tag)"
    var name = (profile.cachedProfile?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty {
        name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let nameAsTag = name.replacingOccurrences(of: "#", with: "").uppercased()
    if name.isEmpty || nameAsTag == tag { return tagLabel }
    return tagLabel.isEmpty ? name : "\(name) (\(tagLabel))"
}

/// Nickname only (no "(#TAG)" suffix). Falls back to "#TAG" when no in-game name is known. Used by widget 10.
private func widgetNicknameOnly(for profile: PlayerAccount?) -> String {
    guard let profile else { return "" }
    let tag = profile.tag
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
        .uppercased()
    var name = (profile.cachedProfile?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty {
        name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let nameAsTag = name.replacingOccurrences(of: "#", with: "").uppercased()
    if name.isEmpty || nameAsTag == tag { return tag.isEmpty ? "" : "#\(tag)" }
    return name
}

// MARK: - Widget Rendering Mode for Tinted/Clear Modes
// Use desaturated rendering mode to prevent images from becoming solid accent color blobs
struct SimpleEntry: TimelineEntry {
    let date: Date
    let upgrades: [BuildingUpgrade]
    let builderCount: Int
    let totalBuilderUpgradesCount: Int
    let goldPassBoost: Int
    let builderHallLevel: Int
    let debugText: String
    let profileName: String
    let townHallLevel: Int
    let activeBoosts: [ActiveBoost]  // Track active boosts for accurate timer calculations
    let tapToRefresh: Bool  // Profile setting: tapping the widget refreshes it instead of opening the app

    init(date: Date, upgrades: [BuildingUpgrade], builderCount: Int = 5, totalBuilderUpgradesCount: Int = 0, goldPassBoost: Int = 0, builderHallLevel: Int = 0, debugText: String, profileName: String = "", townHallLevel: Int = 0, activeBoosts: [ActiveBoost] = [], tapToRefresh: Bool = true) {
        self.date = date
        self.upgrades = upgrades
        self.builderCount = builderCount
        self.totalBuilderUpgradesCount = totalBuilderUpgradesCount
        self.goldPassBoost = goldPassBoost
        self.builderHallLevel = builderHallLevel
        self.debugText = debugText
        self.profileName = profileName
        self.townHallLevel = townHallLevel
        self.activeBoosts = activeBoosts
        self.tapToRefresh = tapToRefresh
    }

    /// Same data stamped with a different date (used for per-minute entries while a speed boost runs).
    func withDate(_ newDate: Date) -> SimpleEntry {
        SimpleEntry(date: newDate, upgrades: upgrades, builderCount: builderCount, totalBuilderUpgradesCount: totalBuilderUpgradesCount, goldPassBoost: goldPassBoost, builderHallLevel: builderHallLevel, debugText: debugText, profileName: profileName, townHallLevel: townHallLevel, activeBoosts: activeBoosts, tapToRefresh: tapToRefresh)
    }
}

struct Provider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = SimpleEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], builderCount: 5, totalBuilderUpgradesCount: 0, goldPassBoost: 0, debugText: "Placeholder")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> SimpleEntry {
        let (upgrades, builderCount, goldPassBoost, activeBoosts, totalBuilderUpgradesCount) = loadUpgrades(for: configuration)
        let text = loadDebugText(for: configuration)
        let (profileName, townHallLevel) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: builderCount, totalBuilderUpgradesCount: totalBuilderUpgradesCount, goldPassBoost: goldPassBoost, debugText: text, profileName: profileName, townHallLevel: townHallLevel, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, builderCount, goldPassBoost, activeBoosts, totalBuilderUpgradesCount) = loadUpgrades(for: configuration)
        let text = loadDebugText(for: configuration)
        let (profileName, townHallLevel) = loadProfileInfo(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: builderCount, totalBuilderUpgradesCount: totalBuilderUpgradesCount, goldPassBoost: goldPassBoost, debugText: text, profileName: profileName, townHallLevel: townHallLevel, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))

        // Dynamic refresh policy based on active boosts and urgency
        let nextUpdate: Date
        let now = Date()
        
        // Check if any boosts are active that affect these upgrades
        let hasActiveBoosts = activeBoosts.contains { $0.endTime > now }
        
        // Find the closest upgrade completion time (accounting for boosts)
        var minRemaining: TimeInterval = .infinity
        for upgrade in upgrades {
            let remaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: now)
            if remaining > 0 && remaining < minRemaining {
                minRemaining = remaining
            }
        }
        
        if hasActiveBoosts {
            // When boosts are active, refresh more frequently to keep timers accurate
            if minRemaining <= 60 {
                // Very close to completion: refresh every 30 seconds
                nextUpdate = now.addingTimeInterval(30)
            } else if minRemaining <= 300 {
                // Within 5 minutes: refresh every minute
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
            } else {
                // Active boost but not urgent: refresh every 5 minutes
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now)!
            }
        } else {
            // No boosts active, check urgency based on raw time
            if minRemaining <= 300 {
                // Within 5 minutes of completion: refresh every minute
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
            } else {
                // Standard refresh: every 15 minutes
                nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now)!
            }
        }
        
        return widgetTimeline(entry: entry, upgrades: upgrades, activeBoosts: activeBoosts, fallbackNext: nextUpdate)
    }
    
    private func loadUpgrades(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int, Int, [ActiveBoost], Int) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let baseCount = max(profileToUse?.builderCount ?? 5, 0)
            let activeUpgrades = profileToUse?.activeUpgrades ?? []
            let activeBoosts = profileToUse?.activeBoosts ?? []
            let goblinActive = activeUpgrades.contains { $0.category == .builderVillage && $0.usesGoblin }
            let count = baseCount + (goblinActive ? 1 : 0)
            let boost = max(profileToUse?.goldPassBoost ?? 0, 0)
            let totalBuilderUpgradesCount = activeUpgrades.filter { $0.category == .builderVillage }.count
            return (prioritized(upgrades: activeUpgrades, builderCount: count), count, boost, activeBoosts, totalBuilderUpgradesCount)
        }

        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
                    let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
                return ([], 5, 0, [], 0)
        }
        let goblinActive = decoded.contains { $0.category == .builderVillage && $0.usesGoblin }
        let count = 5 + (goblinActive ? 1 : 0)
        let totalBuilderUpgradesCount = decoded.filter { $0.category == .builderVillage }.count
        return (prioritized(upgrades: decoded, builderCount: count), count, 0, [], totalBuilderUpgradesCount)
    }
    
    private func loadDebugText(for configuration: WidgetProfileIntent) -> String {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            if let name = profileToUse?.displayName, !name.isEmpty {
                return name
            }
            if let tag = profileToUse?.tag, !tag.isEmpty {
                return "#\(tag)"
            }
            return "Clashboard"
        }
        let appGroup = "group.Zachary-Buschmann.clash-widgets"
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        return sharedDefaults?.string(forKey: "widget_simple_text") ?? "No dash data"
    }

    private func loadProfileInfo(for configuration: WidgetProfileIntent) -> (profileName: String, townHallLevel: Int) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let profileName = profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
            let townHall = profileToUse?.cachedProfile?.townHallLevel ?? 0
            return (profileName, townHall)
        }
        return ("Profile", 0)
    }

    private func prioritized(upgrades: [BuildingUpgrade], builderCount: Int) -> [BuildingUpgrade] {
        // Hard limit to 6 builders displayed in widget to prevent layout overflow
        let displayLimit = min(builderCount, 6)
        return Array(
            upgrades
                .filter { $0.category == .builderVillage }
                .sorted(by: { $0.endTime < $1.endTime })
                .prefix(max(displayLimit, 0))
        )
    }
}

// MARK: - Views
struct ClashDashWidgetEntryView : View {
    var entry: Provider.Entry
    
    var columns: [GridItem] {
        // 4 builders → 2x2 grid, 5-6 builders → 3 columns
        let columnCount = entry.builderCount == 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Dynamic grid: 2x2 for 4 builders, 3x2 for 5-6 builders
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<max(min(entry.builderCount, 6), 0), id: \.self) { index in
                    builderCell(for: index)
                        .frame(minHeight: 68)
                }
            }
            // Center align bottom row for exactly 5 builders
            .frame(maxWidth: .infinity, alignment: entry.builderCount == 5 ? .center : .leading)
            .padding(.horizontal, 6)
            
            // Status line (always visible) - with extra padding on bottom to avoid widget edge
            HStack {
                Spacer()
                if entry.totalBuilderUpgradesCount >= entry.builderCount {
                    let statusText = "All Builders Busy"
                    if !entry.profileName.isEmpty {
                        Text(statusText + " • " + entry.profileName)
                            .font(.caption2)
                            .foregroundColor(Color.green)
                            .bold()
                            .lineLimit(1)
                    } else {
                        Text(statusText)
                            .font(.caption2)
                            .foregroundColor(Color.green)
                            .bold()
                            .lineLimit(1)
                    }
                } else {
                    let free = max(entry.builderCount - entry.totalBuilderUpgradesCount, 0)
                    let noun = free == 1 ? "builder" : "builders"
                    let statusText = "\(free) \(noun) free"
                    if !entry.profileName.isEmpty {
                        Text(statusText + " • " + entry.profileName)
                            .font(.caption2)
                            .foregroundColor(Color.orange)
                            .bold()
                            .lineLimit(1)
                    } else {
                        Text(statusText + "!")
                            .font(.caption2)
                            .foregroundColor(Color.orange)
                            .bold()
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .frame(minHeight: 16)
            .padding(.bottom, 8)
        }
        .padding(12)
        .widgetTapAction(refresh: entry.tapToRefresh)
    }
    
    @ViewBuilder
    private func builderCell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]

                // Name spans full width at top
                HStack(spacing: 2) {
                    Text(koName(upgrade.name))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    if upgrade.showsSuperchargeIcon {
                        Image("extras/supercharge")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Icon on left, Level + Time on right (same row)
                HStack(spacing: 6) {
                    trimmedWidgetImage(named: iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .clashWidgetTintAwareRendering()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(upgrade.levelDisplayText)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        LiveUpgradeTimeText(upgrade: upgrade, activeBoosts: entry.activeBoosts, referenceDate: entry.date)
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                    
                    Spacer()
                }

                // progress bar (thin)
                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 4)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green.opacity(0.7))
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Builder \(index + 1)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.6))
                        Text("Available")
                            .font(.system(size: 8))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: entry.goldPassBoost, referenceDate: entry.date)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "builder_base"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        
        var variations: [String] = []
        
        // SPECIAL CASE: seasonal defenses (IDs 103000000-104000000) should try crafted_defenses folder first
        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(sanitizedName)")
        }
        
        // Try category-specific folder
        variations.append("\(folder)/\(sanitizedName)")
        
        // Try direct sanitized name
        variations.append(sanitizedName)

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(sanitizedName)" // Default fallback
    }
}

struct ClashDashWidget: Widget {
    let kind: String = "ClashDashWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                ClashDashWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClashDashWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Clash Builders")
        .description("Track Building Upgrades with the widget.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Lock Screen Closest Upgrade Widget
struct ClosestUpgradeEntry: TimelineEntry {
    let date: Date
    let upgrade: BuildingUpgrade?
    let typeLabel: String
    let activeBoosts: [ActiveBoost]  // Track active boosts for accurate timer calculations
}

struct ClosestUpgradeProvider: AppIntentTimelineProvider {
    typealias Intent = ClosestUpgradeIntent
    typealias Entry = ClosestUpgradeEntry

    func placeholder(in context: Context) -> ClosestUpgradeEntry {
        ClosestUpgradeEntry(date: Date(), upgrade: nil, typeLabel: "Builders", activeBoosts: [])
    }

    func snapshot(for configuration: ClosestUpgradeIntent, in context: Context) async -> ClosestUpgradeEntry {
        let upgrade = loadClosestUpgrade(for: configuration)
        let activeBoosts = loadActiveBoosts(for: configuration)
        return ClosestUpgradeEntry(date: Date(), upgrade: upgrade, typeLabel: label(for: configuration.upgradeType ?? .builders), activeBoosts: activeBoosts)
    }

    func timeline(for configuration: ClosestUpgradeIntent, in context: Context) async -> Timeline<ClosestUpgradeEntry> {
        let upgrade = loadClosestUpgrade(for: configuration)
        let activeBoosts = loadActiveBoosts(for: configuration)
        let entry = ClosestUpgradeEntry(date: Date(), upgrade: upgrade, typeLabel: label(for: configuration.upgradeType ?? .builders), activeBoosts: activeBoosts)
        
        // Adjust refresh rate based on boost activity
        let hasActiveBoosts = !activeBoosts.isEmpty
        let minutes = hasActiveBoosts ? 1 : 15  // Refresh every 1 min with boosts, 15 min otherwise
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadClosestUpgrade(for configuration: ClosestUpgradeIntent) -> BuildingUpgrade? {
        guard let state = PersistentStore.loadState() else { return nil }

        let profileToUse: PlayerAccount?
        var selectedProfileID: UUID? = nil
        if let selectedProfile = configuration.selectedProfile,
           !selectedProfile.isAutomatic,
           let profileID = selectedProfile.profileID() {
            selectedProfileID = profileID
        } else {
            let appGroup = "group.Zachary-Buschmann.clash-widgets"
            if let defaults = UserDefaults(suiteName: appGroup),
               let savedSelection = defaults.string(forKey: "widget_profile_selection"),
               let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                selectedProfileID = profileID
            }
        }

        if let selectedID = selectedProfileID {
            profileToUse = state.profiles.first(where: { $0.id == selectedID })
        } else {
            profileToUse = state.currentProfile
        }

        let upgrades = profileToUse?.activeUpgrades ?? []
        let type = configuration.upgradeType ?? .builders
        let filtered = upgrades.filter { matchesType($0, type: type) }
        return filtered.sorted(by: { $0.endTime < $1.endTime }).first
    }
    
    private func loadActiveBoosts(for configuration: ClosestUpgradeIntent) -> [ActiveBoost] {
        guard let state = PersistentStore.loadState() else { return [] }

        let profileToUse: PlayerAccount?
        var selectedProfileID: UUID? = nil
        if let selectedProfile = configuration.selectedProfile,
           !selectedProfile.isAutomatic,
           let profileID = selectedProfile.profileID() {
            selectedProfileID = profileID
        } else {
            let appGroup = "group.Zachary-Buschmann.clash-widgets"
            if let defaults = UserDefaults(suiteName: appGroup),
               let savedSelection = defaults.string(forKey: "widget_profile_selection"),
               let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                selectedProfileID = profileID
            }
        }

        if let selectedID = selectedProfileID {
            profileToUse = state.profiles.first(where: { $0.id == selectedID })
        } else {
            profileToUse = state.currentProfile
        }

        return profileToUse?.activeBoosts ?? []
    }

    private func matchesType(_ upgrade: BuildingUpgrade, type: UpgradeTypeSelection) -> Bool {
        switch type {
        case .builders:
            return upgrade.category == .builderVillage
        case .lab:
            return upgrade.category == .lab
        case .pets:
            return upgrade.category == .pets
        case .builderBase:
            return upgrade.category == .builderBase
        case .starLab:
            return upgrade.category == .starLab
        case .homeOverall:
            return upgrade.category == .builderVillage || upgrade.category == .lab || upgrade.category == .pets
        case .builderBaseOverall:
            return upgrade.category == .builderBase || upgrade.category == .starLab
        }
    }

    private func label(for type: UpgradeTypeSelection) -> String {
        switch type {
        case .builders: return "Builders"
        case .lab: return "Lab"
        case .pets: return "Pet House"
        case .builderBase: return "Builder Base"
        case .starLab: return "Star Lab"
        case .homeOverall: return "Home Overall"
        case .builderBaseOverall: return "Builder Base Overall"
        }
    }
}

struct ClosestUpgradeWidgetEntryView: View {
    var entry: ClosestUpgradeEntry

    var body: some View {
        if let upgrade = entry.upgrade {
            HStack(spacing: 8) {
                trimmedWidgetImage(named: iconName(for: upgrade))
                    .resizable()
                    .clashWidgetTintAwareRendering()
                    .scaledToFit()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.typeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(koName(upgrade.name))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(formatBoostedTimeRemaining(for: upgrade, activeBoosts: entry.activeBoosts))
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    ProgressView(value: progressFraction(for: upgrade))
                        .progressViewStyle(.linear)
                }
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.typeLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("No active upgrades")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "builder_base"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        var variations: [String] = []

        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(sanitizedName)")
        }
        variations.append("\(folder)/\(sanitizedName)")
        variations.append(sanitizedName)

        for variant in variations {
            if UIImage(named: variant) != nil { return variant }
        }
        return "\(folder)/\(sanitizedName)"
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: 0)
    }
}

struct ClosestUpgradeWidget: Widget {
    let kind: String = "ClosestUpgradeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ClosestUpgradeIntent.self, provider: ClosestUpgradeProvider()) { entry in
            if #available(iOS 17.0, *) {
                ClosestUpgradeWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClosestUpgradeWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Closest Upgrade")
        .description("Shows the closest upgrade to finishing for a selected type and profile.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock Screen Import Toggle Widget
// Import action is exposed as a Control (not a widget)

// MARK: - Clan War Lock Screen Widget
struct WarStatusEntry: TimelineEntry {
    let date: Date
    let war: WarDetails?
}

struct WarStatusProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    
    func placeholder(in context: Context) -> WarStatusEntry {
        WarStatusEntry(date: Date(), war: nil)
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) -> WarStatusEntry {
        WarStatusEntry(date: Date(), war: loadWar(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<WarStatusEntry> {
        let entry = WarStatusEntry(date: Date(), war: loadWar(for: configuration))
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadWar(for configuration: WidgetProfileIntent) -> WarDetails? {
        let defaults = UserDefaults(suiteName: "group.Zachary-Buschmann.clash-widgets")
        
        // Get the profile ID to load war data for
        let profileID: UUID? = {
            if let selected = configuration.selectedProfile, !selected.isAutomatic {
                return selected.profileID()
            }
            return nil
        }()
        
        // If specific profile is selected, load its war data
        if let profileID = profileID,
           let state = PersistentStore.loadState(),
           let profile = state.profiles.first(where: { $0.id == profileID }),
           let warData = defaults?.data(forKey: "war_json_\(profile.tag)") {
            return try? JSONDecoder().decode(WarDetails.self, from: warData)
        }
        
        // Otherwise, fall back to current war data
        guard let data = defaults?.data(forKey: "current_war_json") else { return nil }
        return try? JSONDecoder().decode(WarDetails.self, from: data)
    }
}

struct WarStatusWidgetEntryView: View {
    var entry: WarStatusEntry

    var body: some View {
        if let war = entry.war,
           let clan = war.clan,
           let opponent = war.opponent {
            let phase = warPhase(for: war)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(clan.name)
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text("\(clan.stars ?? 0)-\(opponent.stars ?? 0)")
                        .font(.caption)
                        .bold()
                }
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    if let timer = warTimerLabel(for: war, referenceDate: context.date) {
                        Text(timer)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(phase.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            Text("No war data")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private struct WarPhaseInfo {
        let label: String
        let progress: Double
    }

    private func warPhase(for war: WarDetails) -> WarPhaseInfo {
        let now = Date()
        let prepStart = parseWarDate(war.preparationStartTime)
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let prepStart, let start, now < start {
            let total = max(start.timeIntervalSince(prepStart), 1)
            let progress = min(max(now.timeIntervalSince(prepStart) / total, 0), 1)
            return WarPhaseInfo(label: "Preparation", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(label: "Battle", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(label: "Ended", progress: 1)
        }
        return WarPhaseInfo(label: "Status", progress: 0)
    }

    private func warTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let now = referenceDate
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, now < start {
            let remaining = start.timeIntervalSince(now)
            return formatTimeRemaining(remaining, label: "Prep")
        }
        if let start, let end, now >= start, now < end {
            let remaining = end.timeIntervalSince(now)
            return formatTimeRemaining(remaining, label: "Battle")
        }
        if let end, now >= end {
            return "War Ended"
        }
        return nil
    }

    private func formatTimeRemaining(_ seconds: TimeInterval, label: String) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if days > 0 {
            return "\(label) - \(days)d \(hours)h"
        } else if hours > 0 {
            return "\(label) - \(hours)h \(minutes)m"
        } else {
            return "\(label) - \(minutes)m"
        }
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }
}

struct WarStatusWidget: Widget {
    let kind: String = "WarStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: WarStatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                WarStatusWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WarStatusWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Clan War Status")
        .description("Shows the current clan war status and progress.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock Screen War Widget (2x2 variant)
struct WarStatusSmallWidgetEntryView: View {
    var entry: WarStatusEntry

    var body: some View {
        if let war = entry.war,
           let clan = war.clan,
           let opponent = war.opponent {
            let phase = warPhase(for: war)
            VStack(alignment: .center, spacing: 3) {
                HStack(spacing: 2) {
                    Text(String(clan.name.prefix(1)))
                        .font(.caption2)
                        .bold()
                    Spacer()
                    Text("\(clan.stars ?? 0)-\(opponent.stars ?? 0)")
                        .font(.caption2)
                        .bold()
                    Spacer()
                    Text(String(opponent.name.prefix(1)))
                        .font(.caption2)
                        .bold()
                }
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 4)
                
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    if let timer = warTimerLabel(for: war, referenceDate: context.date) {
                        Text(timer)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(phase.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(6)
        } else {
            Text("No war")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private struct WarPhaseInfo {
        let label: String
        let progress: Double
    }

    private func warPhase(for war: WarDetails) -> WarPhaseInfo {
        let now = Date()
        let prepStart = parseWarDate(war.preparationStartTime)
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let prepStart, let start, now < start {
            let total = max(start.timeIntervalSince(prepStart), 1)
            let progress = min(max(now.timeIntervalSince(prepStart) / total, 0), 1)
            return WarPhaseInfo(label: "Prep", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(label: "Battle", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(label: "Ended", progress: 1)
        }
        return WarPhaseInfo(label: "Status", progress: 0)
    }

    private func warTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let now = referenceDate
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, now < start {
            let remaining = start.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        if let start, let end, now >= start, now < end {
            let remaining = end.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        return nil
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }
}

struct WarStatusSmallWidget: Widget {
    let kind: String = "WarStatusSmallWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: WarStatusProvider()) { entry in
            if #available(iOS 17.0, *) {
                WarStatusSmallWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                WarStatusSmallWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Clan War (Compact)")
        .description("Shows clan war in a compact 2x2 lock screen format.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Control Center Import Control (iOS 18+)
#if canImport(ControlCenter)
@available(iOS 18.0, *)
struct ImportClipboardControlProvider: AppIntentControlValueProvider {
    typealias Intent = ImportClipboardIntent
    typealias Value = Bool

    func value(for configuration: ImportClipboardIntent) async throws -> Bool {
        false
    }
}

@available(iOS 18.0, *)
struct ImportClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "ImportClipboardControl",
            provider: ImportClipboardControlProvider()
        ) { _ in
            ControlWidgetButton(intent: ImportClipboardIntent()) {
                ZStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 22, weight: .semibold))
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .offset(x: 10, y: 10)
                }
            }
        }
        .displayName("Import Clipboard")
        .description("Paste & import your village data.")
    }
}
#endif

// MARK: - Boost-Aware Time Calculations

/// Calculate effective remaining time accounting for active boosts (potions, clock tower, helpers)
/// This ensures widget timers match the boosted times shown in the app
private func effectiveRemainingSeconds(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], referenceDate: Date) -> TimeInterval {
    upgrade.remainingSeconds(activeBoosts: activeBoosts, referenceDate: referenceDate)
}

private func effectiveCompletionDate(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], referenceDate: Date = Date()) -> Date {
    upgrade.projectedCompletionDate(activeBoosts: activeBoosts, referenceDate: referenceDate)
}

/// Format time remaining with boost calculations applied
private func formatBoostedTimeRemaining(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], referenceDate: Date = Date()) -> String {
    let remaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
    if remaining <= 0 { return "Complete" }
    
    let days = Int(remaining) / 86400
    let hours = (Int(remaining) % 86400) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    
    if days > 0 {
        return "\(days)d \(hours)h"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        let seconds = (Int(remaining) % 60)
        return String(format: "%dm %02ds", minutes, seconds)
    } else {
        let seconds = max(Int(remaining.rounded()), 0)
        return "\(seconds)s"
    }
}

/// Calculate boost-aware progress fraction for progress bars
/// Uses the boosted remaining time to show accurate progress when potions/helpers are active
private func boostedProgressFraction(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], goldPassBoost: Int = 0, referenceDate: Date = Date()) -> Double {
    // Get the boost-adjusted remaining time
    let boostedRemaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
    
    // Calculate the effective total duration (with gold pass applied)
    let effectiveTotal = upgrade.effectiveTotalDuration(goldPassBoost: goldPassBoost)
    
    // Calculate elapsed time based on boosted remaining
    let elapsed = max(effectiveTotal - boostedRemaining, 0)
    
    return min(max(elapsed / effectiveTotal, 0.0), 1.0)
}

private func goldPassProgressFraction(for upgrade: BuildingUpgrade, boost: Int, referenceDate: Date = Date()) -> Double {
    let total = goldPassBoostedTotalDuration(for: upgrade, boost: boost)
    let remaining = goldPassEffectiveRemaining(for: upgrade, referenceDate: referenceDate, totalDuration: total)
    let elapsed = max(total - remaining, 0)
    return min(max(elapsed / total, 0.0), 1.0)
}

private func goldPassBoostedTotalDuration(for upgrade: BuildingUpgrade, boost: Int) -> TimeInterval {
    upgrade.effectiveTotalDuration(goldPassBoost: boost)
}

private func goldPassEffectiveRemaining(for upgrade: BuildingUpgrade, referenceDate: Date, totalDuration: TimeInterval) -> TimeInterval {
    let actualRemaining = max(0, upgrade.endTime.timeIntervalSince(referenceDate))
    return min(actualRemaining, totalDuration)
}

#Preview(as: .systemMedium) {
    ClashDashWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Preview")
}


// MARK: - Small Widgets

struct LabPetProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = SimpleEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "LabPet")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> SimpleEntry {
        let (upgrades, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, debugText: "LabPet", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, debugText: "LabPet", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
        
        // Adjust refresh rate based on boost activity
        let hasActiveBoosts = !activeBoosts.isEmpty
        let minutes = hasActiveBoosts ? 1 : 15  // Refresh every 1 min with boosts, 15 min otherwise
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        return widgetTimeline(entry: entry, upgrades: upgrades, activeBoosts: activeBoosts, fallbackNext: nextUpdate)
    }

    private func loadUpgradesAndBoosts(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], [ActiveBoost]) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let upgrades = profileToUse?.activeUpgrades ?? []
            let activeBoosts = profileToUse?.activeBoosts ?? []
            return (filtered(upgrades: upgrades), activeBoosts)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return ([], [])
        }
        return (filtered(upgrades: decoded), [])
    }

    private func loadUpgrades(for configuration: WidgetProfileIntent) -> [BuildingUpgrade] {
        return loadUpgradesAndBoosts(for: configuration).0
    }

    private func filtered(upgrades: [BuildingUpgrade]) -> [BuildingUpgrade] {
        let filtered = upgrades.filter { $0.category == .lab || $0.category == .pets }
            .sorted(by: { $0.endTime < $1.endTime })
        return Array(filtered.prefix(2))
    }

    private func loadProfileInfo(for configuration: WidgetProfileIntent) -> (profileName: String, townHallLevel: Int) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let profileName = profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
            let townHall = profileToUse?.cachedProfile?.townHallLevel ?? 0
            return (profileName, townHall)
        }
        return ("Profile", 0)
    }
}

// Helper cooldown small widget
struct HelperCooldownStatus: Identifiable {
    let id: Int
    let name: String
    let iconName: String
    let level: Int
    let cooldownSeconds: Int
    let expiresAt: Date?

    func remainingSeconds(referenceDate: Date = Date()) -> Int {
        if let expiresAt = expiresAt {
            return max(0, Int(expiresAt.timeIntervalSince(referenceDate)))
        }
        return max(0, cooldownSeconds)
    }

    func cooldownText(referenceDate: Date = Date()) -> String {
        let remaining = remainingSeconds(referenceDate: referenceDate)
        if remaining <= 0 { return "Helper ready to work" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

struct HelperCooldownWidgetEntry: TimelineEntry {
    let date: Date
    let helpers: [HelperCooldownStatus]
    let profileName: String
    var tapToRefresh: Bool = true
}

struct HelperCooldownProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = HelperCooldownWidgetEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> HelperCooldownWidgetEntry {
        HelperCooldownWidgetEntry(date: Date(), helpers: placeholderHelpers(), profileName: "")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> HelperCooldownWidgetEntry {
        let profileName = loadProfileName(for: configuration)
        return HelperCooldownWidgetEntry(date: Date(), helpers: loadHelpers(for: configuration), profileName: profileName, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<HelperCooldownWidgetEntry> {
        let profileName = loadProfileName(for: configuration)
        let entry = HelperCooldownWidgetEntry(date: Date(), helpers: loadHelpers(for: configuration), profileName: profileName, tapToRefresh: widgetTapRefreshEnabled(for: configuration))

        // Schedule next update based on active helper cooldowns so the widget stays responsive.
        let remainingValues = entry.helpers.map { $0.remainingSeconds() }
        let minRemaining = remainingValues.min() ?? -1
        let nextUpdate: Date
        if minRemaining < 0 {
            // No active helpers: refresh every 15 minutes
            nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        } else if minRemaining <= 30 {
            // Near expiry (within 30 seconds): refresh every 30 seconds to respect widget budget
            nextUpdate = Date().addingTimeInterval(30)
        } else {
            // Active but not urgent: refresh every 5 minutes to respect widget refresh budget
            nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        }

        // Switch to the live countdown right when the longest cooldown drops under 1 hour
        var helperNext = nextUpdate
        if let longest = entry.helpers.map({ $0.remainingSeconds() }).max(), longest > 3600 {
            helperNext = min(helperNext, Date().addingTimeInterval(Double(longest - 3600 + 1)))
        }
        return Timeline(entries: [entry], policy: .after(helperNext))
    }

    private func loadHelpers(for configuration: WidgetProfileIntent) -> [HelperCooldownStatus] {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            if let rawJSON = profileToUse?.rawJSON, !rawJSON.isEmpty,
               let helpers = parseHelpers(rawJSON: rawJSON) {
                return helpers
            }
        }
        let sharedDefaults = UserDefaults(suiteName: appGroup)
        if let rawJSON = sharedDefaults?.string(forKey: "saved_raw_json"), !rawJSON.isEmpty,
           let helpers = parseHelpers(rawJSON: rawJSON) {
            return helpers
        }
        return []
    }

    private func parseHelpers(rawJSON: String) -> [HelperCooldownStatus]? {
        guard let data = rawJSON.data(using: .utf8),
              let export = try? JSONDecoder().decode(CoCExport.self, from: data) else {
            return nil
        }
        let helpers = export.helpers ?? []

        // Derive an export timestamp if available so helper expiry can be calculated
        let exportDate: Date
        if let ts = export.timestamp {
            exportDate = Date(timeIntervalSince1970: TimeInterval(ts))
        } else {
            exportDate = Date()
        }

        let mapped = helpers.compactMap { helper -> HelperCooldownStatus? in
            let rawSeconds = max(helper.helperCooldown ?? 0, 0)
            let expiresAt = exportDate.addingTimeInterval(TimeInterval(rawSeconds))
            let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))

            switch helper.data {
            case 93000000:
                return HelperCooldownStatus(id: helper.data, name: "견습 장인", iconName: "profile/apprentice_builder", level: helper.lvl, cooldownSeconds: remaining, expiresAt: expiresAt)
            case 93000001:
                return HelperCooldownStatus(id: helper.data, name: "연구소 조수", iconName: "profile/lab_assistant", level: helper.lvl, cooldownSeconds: remaining, expiresAt: expiresAt)
            case 93000002:
                return HelperCooldownStatus(id: helper.data, name: "연금술사", iconName: "profile/alchemist", level: helper.lvl, cooldownSeconds: remaining, expiresAt: expiresAt)
            default:
                return nil
            }
        }
        return mapped.sorted { $0.id < $1.id }
    }

    private func placeholderHelpers() -> [HelperCooldownStatus] {
        [
            HelperCooldownStatus(id: 93000000, name: "견습 장인", iconName: "profile/apprentice_builder", level: 1, cooldownSeconds: 0, expiresAt: nil),
            HelperCooldownStatus(id: 93000001, name: "연구소 조수", iconName: "profile/lab_assistant", level: 1, cooldownSeconds: 0, expiresAt: nil),
            HelperCooldownStatus(id: 93000002, name: "연금술사", iconName: "profile/alchemist", level: 1, cooldownSeconds: 0, expiresAt: nil)
        ]
    }

    private func loadProfileName(for configuration: WidgetProfileIntent) -> String {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            return profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
        }
        return ""
    }
}

struct HelperCooldownWidgetEntryView: View {
    var entry: HelperCooldownWidgetEntry

    var body: some View {
        let cooldownSeconds = entry.helpers.map { $0.cooldownSeconds }.max() ?? 0
        let totalSeconds = 23 * 60 * 60
        let remaining = max(min(cooldownSeconds, totalSeconds), 0)
        let progress = max(0, min(1, 1 - (Double(remaining) / Double(totalSeconds))))
        let helperEnd = entry.helpers.compactMap { $0.expiresAt }.max() ?? Date.distantPast

        return VStack(spacing: 6) {
            HStack {
                Spacer()
                Image("buildings_home/helper_hut")
                    .resizable()
                    .clashWidgetTintAwareRendering()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                Spacer()
            }

            Text("도우미 오두막")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            if remaining > 0 && remaining <= 3600 {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    let remainingNow = entry.helpers.map { helper in
                        helper.remainingSeconds(referenceDate: context.date)
                    }.max() ?? 0
                    let clamped = max(min(remainingNow, totalSeconds), 0)
                    let progressNow = max(0, min(1, 1 - (Double(clamped) / Double(totalSeconds))))

                    VStack(spacing: 3) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green)
                                    .frame(width: geo.size.width * CGFloat(progressNow), height: 6)
                            }
                        }
                        .frame(height: 6)

                        // Status on separate line
                        LiveCountdownText(
                            endDate: helperEnd,
                            fallback: entry.helpers.first?.cooldownText(referenceDate: context.date) ?? (clamped <= 0 ? "Ready to Work" : "0s"),
                            referenceDate: entry.date,
                            alignment: .center,
                            width: 60
                        )
                            .font(.system(size: 10))
                            .foregroundColor(clamped > 0 ? .orange : .green)
                    }
                }
            } else {
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    // Status on separate line
                    LiveCountdownText(
                        endDate: helperEnd,
                        fallback: formatHelperCooldown(remaining),
                        referenceDate: entry.date,
                        alignment: .center,
                        width: 60
                    )
                        .font(.system(size: 10))
                        .foregroundColor(remaining > 0 ? .orange : .green)
                }
            }

            if entry.helpers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("No helper data")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            
            // Profile name at bottom
            if !entry.profileName.isEmpty {
                Text(entry.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .widgetTapAction(refresh: entry.tapToRefresh)
    }

    private func formatHelperCooldown(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready to Work" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}

struct HelperCooldownWidget: Widget {
    let kind: String = "HelperCooldownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: HelperCooldownProvider()) { entry in
            if #available(iOS 17.0, *) {
                HelperCooldownWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                HelperCooldownWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Helper Cooldowns")
        .description("Track helper cooldown timers,hoose profile or set to last opened profile.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Clan War Home Screen Widget (2x2)
struct ClanWarWidgetEntry: TimelineEntry {
    let date: Date
    let war: WarDetails?
    let isInCWL: Bool
    let profileName: String
}

struct ClanWarWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = ClanWarWidgetEntry
    
    func placeholder(in context: Context) -> ClanWarWidgetEntry {
        ClanWarWidgetEntry(date: Date(), war: nil, isInCWL: false, profileName: "")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) -> ClanWarWidgetEntry {
        let (war, isInCWL) = loadWarData(for: configuration)
        let profileName = loadProfileName(for: configuration)
        return ClanWarWidgetEntry(date: Date(), war: war, isInCWL: isInCWL, profileName: profileName)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<ClanWarWidgetEntry> {
        let (war, isInCWL) = loadWarData(for: configuration)
        let profileName = loadProfileName(for: configuration)
        let entry = ClanWarWidgetEntry(date: Date(), war: war, isInCWL: isInCWL, profileName: profileName)
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadWarData(for configuration: WidgetProfileIntent) -> (war: WarDetails?, isInCWL: Bool) {
        let defaults = UserDefaults(suiteName: "group.Zachary-Buschmann.clash-widgets")
        guard let state = PersistentStore.loadState() else { return (nil, false) }
        
        // Determine which profile to use
        var profileToUse: PlayerAccount? = nil
        
        // First check if a profile is selected in the configuration
        if let selectedProfile = configuration.selectedProfile,
           !selectedProfile.isAutomatic,
           let profileID = selectedProfile.profileID() {
            profileToUse = state.profiles.first(where: { $0.id == profileID })
        } else {
            // If no profile selected, try to read from UserDefaults (saved preference)
            if let savedSelection = defaults?.string(forKey: "widget_profile_selection"),
               let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                profileToUse = state.profiles.first(where: { $0.id == profileID })
            }
        }
        
        // Fall back to current profile if needed
        if profileToUse == nil {
            profileToUse = state.currentProfile
        }
        
        var war: WarDetails? = nil
        var isInCWL = false
        
        // Load war data using the profile's tag as cache key
        if let profile = profileToUse, !profile.tag.isEmpty {
            // Try profile-specific war data first
            let cacheKey = "war_json_\(profile.tag)"
            if let data = defaults?.data(forKey: cacheKey) {
                war = try? JSONDecoder().decode(WarDetails.self, from: data)
            }
            
            // Check CWL status for this profile
            let cwlKey = "is_in_cwl_\(profile.tag)"
            isInCWL = defaults?.bool(forKey: cwlKey) ?? false
        } else {
            // Fallback to generic current war data
            if let data = defaults?.data(forKey: "current_war_json") {
                war = try? JSONDecoder().decode(WarDetails.self, from: data)
            }
            isInCWL = defaults?.bool(forKey: "is_in_cwl") ?? false
        }
        
        return (war, isInCWL)
    }

    private func loadProfileName(for configuration: WidgetProfileIntent) -> String {
        guard let state = PersistentStore.loadState() else { return "" }
        
        // Determine which profile to use
        var profileToUse: PlayerAccount? = nil
        
        // First check if a profile is selected in the configuration
        if let selectedProfile = configuration.selectedProfile,
           !selectedProfile.isAutomatic,
           let profileID = selectedProfile.profileID() {
            profileToUse = state.profiles.first(where: { $0.id == profileID })
        } else {
            // If no profile selected, try to read from UserDefaults (saved preference)
            let defaults = UserDefaults(suiteName: "group.Zachary-Buschmann.clash-widgets")
            if let savedSelection = defaults?.string(forKey: "widget_profile_selection"),
               let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                profileToUse = state.profiles.first(where: { $0.id == profileID })
            }
        }
        
        // Fall back to current profile if needed
        if profileToUse == nil {
            profileToUse = state.currentProfile
        }
        
        return profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
    }
}

struct ClanWarWidgetEntryView: View {
    var entry: ClanWarWidgetEntry

    var body: some View {
        if entry.isInCWL {
            // Show CWL message
            VStack(alignment: .center, spacing: 8) {
                Text("Clan War League")
                    .font(.headline)
                    .bold()
                Spacer()
                Text("Currently in Clan War League")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let war = entry.war,
                  let clan = war.clan,
                  let opponent = war.opponent {
            // Show current war details
            VStack(alignment: .leading, spacing: 10) {
                // Teams comparison with badges
                HStack(alignment: .top, spacing: 8) {
                    // Our Clan
                    VStack(alignment: .center, spacing: 6) {
                        // Badge image or colored circle fallback
                        if !clan.badgeUrls.small.isEmpty {
                            AsyncImage(url: URL(string: clan.badgeUrls.small)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 44, height: 44)
                                case .failure, .empty:
                                    Circle()
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(String(clan.name.prefix(2)))
                                                .font(.caption)
                                                .bold()
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(Color.blue.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                }
                            }
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(clan.name.prefix(2)))
                                        .font(.caption)
                                        .bold()
                                )
                        }
                        Text(clan.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text("★ \(clan.stars ?? 0)")
                            .font(.caption2)
                            .bold()
                    }
                    
                    // VS
                    VStack(spacing: 4) {
                        Text("VS")
                            .font(.caption2)
                            .bold()
                        Text("\(war.teamSize)v\(war.teamSize)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Opponent
                    VStack(alignment: .center, spacing: 6) {
                        // Badge image or colored circle fallback
                        if !opponent.badgeUrls.small.isEmpty {
                            AsyncImage(url: URL(string: opponent.badgeUrls.small)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 44, height: 44)
                                case .failure, .empty:
                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text(String(opponent.name.prefix(2)))
                                                .font(.caption)
                                                .bold()
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                }
                            }
                        } else {
                            Circle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(opponent.name.prefix(2)))
                                        .font(.caption)
                                        .bold()
                                )
                        }
                        Text(opponent.name)
                            .font(.caption)
                            .lineLimit(1)
                        Text("★ \(opponent.stars ?? 0)")
                            .font(.caption2)
                            .bold()
                    }
                }
                
                // War phase progress bar
                let phase = warPhase(for: war)
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(phase.progress), height: 8)
                        }
                    }
                    .frame(height: 8)
                    
                    // Timer and phase label
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        HStack {
                            if let timer = warTimerLabel(for: war, referenceDate: context.date) {
                                Text(timer)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(phase.label)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let percentage = warDestructionPercentage(for: war) {
                                Text("\(percentage)% destroyed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Profile name at bottom
                if !entry.profileName.isEmpty {
                    HStack {
                        Text(entry.profileName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(12)
        } else {
            VStack(alignment: .center, spacing: 8) {
                Text("Clan War")
                    .font(.headline)
                    .bold()
                Spacer()
                Text("No active war")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !entry.profileName.isEmpty {
                    Text(entry.profileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func warDestructionPercentage(for war: WarDetails) -> Int? {
        guard let clan = war.clan, let opponent = war.opponent else { return nil }
        let clanDest = Int(clan.destructionPercentage ?? 0)
        let oppDest = Int(opponent.destructionPercentage ?? 0)
        return max(clanDest, oppDest)
    }

    private struct WarPhaseInfo {
        let label: String
        let progress: Double
    }

    private func warPhase(for war: WarDetails) -> WarPhaseInfo {
        let now = Date()
        let prepStart = parseWarDate(war.preparationStartTime)
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let prepStart, let start, now < start {
            let total = max(start.timeIntervalSince(prepStart), 1)
            let progress = min(max(now.timeIntervalSince(prepStart) / total, 0), 1)
            return WarPhaseInfo(label: "Preparation", progress: progress)
        }
        if let start, let end, now >= start, now < end {
            let total = max(end.timeIntervalSince(start), 1)
            let progress = min(max(now.timeIntervalSince(start) / total, 0), 1)
            return WarPhaseInfo(label: "Battle", progress: progress)
        }
        if let end, now >= end {
            return WarPhaseInfo(label: "Ended", progress: 1)
        }
        return WarPhaseInfo(label: "Status", progress: 0)
    }

    private func warTimerLabel(for war: WarDetails, referenceDate: Date) -> String? {
        let now = referenceDate
        let start = parseWarDate(war.startTime)
        let end = parseWarDate(war.endTime)

        if let _ = parseWarDate(war.preparationStartTime), let start, now < start {
            let remaining = start.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        if let start, let end, now >= start, now < end {
            let remaining = end.timeIntervalSince(now)
            return formatTimeRemaining(remaining)
        }
        return nil
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func parseWarDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS'Z'"
        return formatter.date(from: value)
    }
}

struct ClanWarWidget: Widget {
    let kind: String = "ClanWarWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: ClanWarWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                ClanWarWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ClanWarWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Clan War")
        .description("Shows current clan war status, opponent, and war timer.")
        .supportedFamilies([.systemMedium])
    }
}

struct LabPetWidgetEntryView: View {
    var entry: LabPetProvider.Entry
    let maxSlots = 2
    var tracksHomeBuilders = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<maxSlots, id: \.self) { index in
                cell(for: index)
            }

            HStack {
                Spacer()
                if (tracksHomeBuilders ? entry.totalBuilderUpgradesCount >= entry.builderCount : entry.upgrades.count >= maxSlots) {
                    Text("All Busy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green)
                } else {
                    let free = tracksHomeBuilders
                        ? max(0, entry.builderCount - entry.totalBuilderUpgradesCount)
                        : maxSlots - entry.upgrades.count
                    Text("\(free) free")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer()
            }
            .padding(.top, 2)
            
            // Profile name at bottom
            if !entry.profileName.isEmpty {
                Text(entry.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .widgetTapAction(refresh: entry.tapToRefresh)
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                HStack(spacing: 6) {
                    trimmedWidgetImage(named: iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .clashWidgetTintAwareRendering()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(koName(upgrade.name))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if upgrade.showsSuperchargeIcon {
                                Image("extras/supercharge")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 8, height: 8)
                            }
                        }
                        Text(upgrade.levelDisplayText)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // Time remaining on separate line
                LiveUpgradeTimeText(upgrade: upgrade, activeBoosts: entry.activeBoosts, referenceDate: entry.date)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)

                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 3)
            } else {
                HStack {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Available")
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.7))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: entry.goldPassBoost, referenceDate: entry.date)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "builder_base"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        
        var variations: [String] = []
        
        // SPECIAL CASE: seasonal defenses (IDs 103000000-104000000) should try crafted_defenses folder first
        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(sanitizedName)")
        }
        
        // Try category-specific folder
        variations.append("\(folder)/\(sanitizedName)")
        
        // Try direct sanitized name
        variations.append(sanitizedName)

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(sanitizedName)" // Default fallback
    }
}

// Home Village builders use the same settings, timeline and two-row layout as the other widgets.
struct HomeBuilderWidget: Widget {
    let kind = "HomeBuilderWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: Provider()) { entry in
            LabPetWidgetEntryView(entry: entry, tracksHomeBuilders: true)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Home Builders")
        .description("Track your two closest Home Village builder upgrades, choose a profile or use the last opened profile.")
        .supportedFamilies([.systemSmall])
    }
}

struct LabPetWidget: Widget {
    let kind: String = "LabPetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: LabPetProvider()) { entry in
            if #available(iOS 17.0, *) {
                LabPetWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                LabPetWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Lab & Pets")
        .description("Track your laboratory and pet house upgrades, choose profile or set to last opened profile.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    LabPetWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Preview")
}

// Builder Base small widget (up to 3 slots)
struct BuilderBaseProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = SimpleEntry
    
    let appGroup = "group.Zachary-Buschmann.clash-widgets"

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "BuilderBase")
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> SimpleEntry {
        let (upgrades, builderHallLevel, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let (upgrades, builderHallLevel, activeBoosts) = loadUpgradesAndBoosts(for: configuration)
        let (profileName, _) = loadProfileInfo(for: configuration)
        let entry = SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
        
        // Adjust refresh rate based on boost activity
        let hasActiveBoosts = !activeBoosts.isEmpty
        let minutes = hasActiveBoosts ? 1 : 15  // Refresh every 1 min with boosts, 15 min otherwise
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date())!
        return widgetTimeline(entry: entry, upgrades: upgrades, activeBoosts: activeBoosts, fallbackNext: nextUpdate)
    }

    private func loadUpgradesAndBoosts(for configuration: WidgetProfileIntent, maxBuilders: Int = 2) -> ([BuildingUpgrade], Int, [ActiveBoost]) {
        let (decoded, builderHallLevel, activeBoosts) = loadUpgradesBuilderHallAndBoosts(for: configuration)
        let builderSlots = builderHallLevel >= 6 ? maxBuilders : 1
        let labSlots = builderHallLevel >= 6 ? 1 : 0

        let builderUpgrades = decoded
            .filter { $0.category == .builderBase }
            .sorted(by: { $0.endTime < $1.endTime })
        let labUpgrades = decoded
            .filter { $0.category == .starLab }
            .sorted(by: { $0.endTime < $1.endTime })

        let selectedBuilders = Array(builderUpgrades.prefix(builderSlots))
        let selectedLab = Array(labUpgrades.prefix(labSlots))
        return (selectedBuilders + selectedLab, builderHallLevel, activeBoosts)
    }

    /// Overview widget 6: up to 3 builders + 1 Star Lab upgrade.
    func overviewSnapshot(for configuration: WidgetProfileIntent) -> SimpleEntry {
        let (upgrades, builderHallLevel, activeBoosts) = loadUpgradesAndBoosts(for: configuration, maxBuilders: 3)
        let (profileName, _) = loadProfileInfo(for: configuration)
        return SimpleEntry(date: Date(), upgrades: upgrades, builderCount: 5, builderHallLevel: builderHallLevel, debugText: "BuilderBase", profileName: profileName, townHallLevel: 0, activeBoosts: activeBoosts, tapToRefresh: widgetTapRefreshEnabled(for: configuration))
    }

    private func loadUpgrades(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int) {
        let (upgrades, builderHallLevel, _) = loadUpgradesAndBoosts(for: configuration)
        return (upgrades, builderHallLevel)
    }

    private func loadUpgradesBuilderHallAndBoosts(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int, [ActiveBoost]) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let builderHall = profileToUse?.cachedProfile?.builderHallLevel ?? 0
            let activeBoosts = profileToUse?.activeBoosts ?? []
            return (profileToUse?.activeUpgrades ?? [], builderHall, activeBoosts)
        }

        let sharedDefaults = UserDefaults(suiteName: appGroup)
        guard let data = sharedDefaults?.data(forKey: "saved_upgrades"),
              let decoded = try? JSONDecoder().decode([BuildingUpgrade].self, from: data) else {
            return ([], 0, [])
        }
        return (decoded, 0, [])
    }

    private func loadUpgradesAndBuilderHall(for configuration: WidgetProfileIntent) -> ([BuildingUpgrade], Int) {
        let (upgrades, builderHallLevel, _) = loadUpgradesBuilderHallAndBoosts(for: configuration)
        return (upgrades, builderHallLevel)
    }

    private func loadProfileInfo(for configuration: WidgetProfileIntent) -> (profileName: String, townHallLevel: Int) {
        if let state = PersistentStore.loadState() {
            // Determine which profile to use
            let profileToUse: PlayerAccount?
            
            // First check if a profile is selected in the configuration
            var selectedProfileID: UUID? = nil
            if let selectedProfile = configuration.selectedProfile,
               !selectedProfile.isAutomatic,
               let profileID = selectedProfile.profileID() {
                selectedProfileID = profileID
            } else {
                // If no profile selected, try to read from UserDefaults (saved preference)
                let appGroup = "group.Zachary-Buschmann.clash-widgets"
                if let defaults = UserDefaults(suiteName: appGroup),
                   let savedSelection = defaults.string(forKey: "widget_profile_selection"),
                   let profileID = ProfileEntity.resolveProfileID(from: savedSelection) {
                    selectedProfileID = profileID
                }
            }
            
            // Load the selected profile or use current
            if let selectedID = selectedProfileID {
                profileToUse = state.profiles.first(where: { $0.id == selectedID })
            } else {
                profileToUse = state.currentProfile
            }
            
            let profileName = profileToUse?.displayName ?? (profileToUse?.tag ?? "Profile")
            let townHall = profileToUse?.cachedProfile?.townHallLevel ?? 0
            return (profileName, townHall)
        }
        return ("Profile", 0)
    }
}

struct BuilderBaseWidgetEntryView: View {
    var entry: BuilderBaseProvider.Entry
    var maxSlots: Int { entry.builderHallLevel >= 6 ? 3 : 1 }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<maxSlots, id: \.self) { index in
                cell(for: index)
            }

            HStack {
                Spacer()
                if entry.upgrades.count >= maxSlots {
                    Text("All Busy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.green)
                } else {
                    let free = maxSlots - entry.upgrades.count
                    Text("\(free) free")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.orange)
                }
                Spacer()
            }
            .padding(.top, 2)
            
            // Profile name at bottom
            if !entry.profileName.isEmpty {
                Text(entry.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .widgetTapAction(refresh: entry.tapToRefresh)
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if index < entry.upgrades.count {
                let upgrade = entry.upgrades[index]
                HStack(spacing: 6) {
                    trimmedWidgetImage(named: iconName(for: upgrade))
                        .interpolation(.none)
                        .resizable()
                        .clashWidgetTintAwareRendering()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(koName(upgrade.name))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if upgrade.showsSuperchargeIcon {
                                Image("extras/supercharge")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 8, height: 8)
                            }
                        }
                        Text(upgrade.levelDisplayText)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }

                // Time remaining on separate line
                LiveUpgradeTimeText(upgrade: upgrade, activeBoosts: entry.activeBoosts, referenceDate: entry.date)
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .bold()

                ProgressView(value: progressFraction(for: upgrade))
                    .progressViewStyle(LinearProgressViewStyle(tint: .green))
                    .frame(height: 2)
            } else {
                HStack {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Available")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.6))
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func progressFraction(for upgrade: BuildingUpgrade) -> Double {
        boostedProgressFraction(for: upgrade, activeBoosts: entry.activeBoosts, goldPassBoost: entry.goldPassBoost, referenceDate: entry.date)
    }

    private func iconName(for upgrade: BuildingUpgrade) -> String {
        let folder: String
        switch upgrade.category {
        case .builderVillage: folder = "buildings_home"
        case .lab: folder = "lab"
        case .starLab: folder = "builder_base"
        case .pets: folder = "pets"
        case .builderBase: folder = "builder_base"
        }

        func sanitize(_ s: String) -> String {
            return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                .lowercased()
        }

        let sanitizedName = sanitize(upgrade.name)
        
        var variations: [String] = []
        
        // SPECIAL CASE: seasonal defenses (IDs 103000000-104000000) should try crafted_defenses folder first
        if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
            variations.append("crafted_defenses/\(sanitizedName)")
        }
        
        // Try category-specific folder
        variations.append("\(folder)/\(sanitizedName)")
        
        // Try direct sanitized name
        variations.append(sanitizedName)

        for variant in variations {
            if UIImage(named: variant) != nil {
                return variant
            }
        }
        
        return "\(folder)/\(sanitizedName)" // Default fallback
    }
}

struct BuilderBaseWidget: Widget {
    let kind: String = "BuilderBaseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: BuilderBaseProvider()) { entry in
            if #available(iOS 17.0, *) {
                BuilderBaseWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                BuilderBaseWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Builder Base")
        .description("Track your Builder Base builders and Star Laboratory upgrades, choose profile or set to last opened profile.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    BuilderBaseWidget()
} timeline: {
    SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Preview")
}


/// While a speed boost (potion, helper, clock tower...) is running, in-app timers run faster than real time.
/// A widget cannot tick faster than 1x by itself, so we hand WidgetKit one pre-computed entry per minute
/// (up to 1 hour or until the boost ends). Each entry is rendered with its own `entry.date`.
private func boostEntryDates(upgrades: [BuildingUpgrade], activeBoosts: [ActiveBoost], now: Date) -> [Date] {
    let boostEnds: [Date] = activeBoosts.compactMap { boost in
        guard boost.endTime > now, let type = boost.boostType else { return nil }
        guard upgrades.contains(where: { type.affectedCategories.contains($0.category) }) else { return nil }
        return boost.endTime
    }
    guard let lastEnd = boostEnds.max() else { return [now] }
    let horizon = min(lastEnd.timeIntervalSince(now), 60 * 60)
    var dates: [Date] = []
    var offset: TimeInterval = 0
    while offset < horizon {
        dates.append(now.addingTimeInterval(offset))
        offset += 60
    }
    dates.append(now.addingTimeInterval(horizon))
    return dates
}

private func widgetTimeline(entry: SimpleEntry, upgrades: [BuildingUpgrade], activeBoosts: [ActiveBoost], fallbackNext: Date) -> Timeline<SimpleEntry> {
    let dates = boostEntryDates(upgrades: upgrades, activeBoosts: activeBoosts, now: entry.date)
    if dates.count > 1, let last = dates.last {
        return Timeline(entries: dates.map { entry.withDate($0) }, policy: .after(last))
    }
    return Timeline(
        entries: [entry],
        policy: .after(widgetBoundaryAdjusted(fallbackNext, upgrades: upgrades, activeBoosts: activeBoosts, now: entry.date))
    )
}

/// True when a speed boost is running for this upgrade at `date` (then the countdown is not 1x).
private func hasRunningBoost(for upgrade: BuildingUpgrade, activeBoosts: [ActiveBoost], at date: Date) -> Bool {
    activeBoosts.contains { boost in
        guard let type = boost.boostType, type.affectedCategories.contains(upgrade.category) else { return false }
        if type == .builderApprentice || type == .labAssistant,
           let target = boost.targetUpgradeId, target != upgrade.id { return false }
        return boost.endTime > date
    }
}

/// Pulls a timeline refresh earlier so the display switches tiers right when an upgrade
/// crosses the 1-hour mark (static -> live) and when it finishes.
private func widgetBoundaryAdjusted(_ next: Date, upgrades: [BuildingUpgrade], activeBoosts: [ActiveBoost], now: Date = Date()) -> Date {
    var result = next
    for upgrade in upgrades {
        let remaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: now)
        if remaining > 3600 {
            result = min(result, now.addingTimeInterval(remaining - 3600 + 1))
        } else if remaining > 0 {
            result = min(result, now.addingTimeInterval(remaining + 1))
        }
    }
    return max(result, now.addingTimeInterval(10))
}

// MARK: - Live countdown text
// Text(timerInterval:) is rendered by iOS itself and ticks every second without a timeline reload.
// Display tiers:
//   1 day or more      -> "Nd Nh"   (static)
//   1 hour to 1 day    -> "Nh Nm"   (static)
//   under 1 hour       -> live "mm:ss" countdown (iOS cannot draw "Nm Ns" with unit letters live).
// Set this to false to show a static "Nm Ns" under 1 hour instead (updates on widget refresh only).
private let widgetLiveCountdownUnderOneHour = true

private struct LiveCountdownText: View {
    let endDate: Date
    let fallback: String
    var referenceDate: Date = Date()
    var alignment: Alignment = .leading
    var width: CGFloat = 38
    /// Widget 10 only: right-align the digits inside the box (Text(timerInterval:) otherwise left-aligns them).
    var trailingText: Bool = false

    private var remaining: TimeInterval { endDate.timeIntervalSince(referenceDate) }

    var body: some View {
        if widgetLiveCountdownUnderOneHour && remaining > 0 && remaining < 3600 {
            Text(timerInterval: referenceDate...endDate, pauseTime: nil, countsDown: true, showsHours: false)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(trailingText ? .trailing : .leading)
                .frame(width: width, alignment: alignment)
        } else {
            Text(fallback)
        }
    }
}

private struct LiveUpgradeTimeText: View {
    let upgrade: BuildingUpgrade
    let activeBoosts: [ActiveBoost]
    var referenceDate: Date = Date()
    var alignment: Alignment = .leading
    var trailingText: Bool = false

    var body: some View {
        let fallback = formatBoostedTimeRemaining(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
        if hasRunningBoost(for: upgrade, activeBoosts: activeBoosts, at: referenceDate) {
            // Boosted time runs faster than 1x, so a live 1x countdown would disagree with the app.
            // The per-minute timeline entries keep this text in step with the app instead.
            Text(fallback)
        } else {
            LiveCountdownText(
                endDate: effectiveCompletionDate(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate),
                fallback: fallback,
                referenceDate: referenceDate,
                alignment: alignment,
                trailingText: trailingText
            )
        }
    }
}

// MARK: - Combined Overview Widget (2x1): Builders + Builder Base + Helper's Hut

private func widgetIconName(for upgrade: BuildingUpgrade) -> String {
    let folder: String
    switch upgrade.category {
    case .builderVillage: folder = "buildings_home"
    case .lab: folder = "lab"
    case .starLab: folder = "builder_base"
    case .pets: folder = "pets"
    case .builderBase: folder = "builder_base"
    }

    func sanitize(_ s: String) -> String {
        return s.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .lowercased()
    }

    let sanitizedName = sanitize(upgrade.name)
    var variations: [String] = []
    if upgrade.isSeasonalDefense == true || (upgrade.dataId ?? 0 >= 103_000_000 && upgrade.dataId ?? 0 < 104_000_000) {
        variations.append("crafted_defenses/\(sanitizedName)")
    }
    variations.append("\(folder)/\(sanitizedName)")
    variations.append(sanitizedName)

    for variant in variations {
        if UIImage(named: variant) != nil {
            return variant
        }
    }
    return "\(folder)/\(sanitizedName)"
}

struct CombinedWidgetEntry: TimelineEntry {
    let date: Date
    let home: SimpleEntry
    let labPet: SimpleEntry
    let builderBase: SimpleEntry
    let helpers: HelperCooldownWidgetEntry
    let tapToRefresh: Bool
    let nickname: String
    var bedtime: BedtimeSettings = BedtimeSettings.load()
}

struct CombinedProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetProfileIntent
    typealias Entry = CombinedWidgetEntry

    func placeholder(in context: Context) -> CombinedWidgetEntry {
        let empty = SimpleEntry(date: Date(), upgrades: [], builderCount: 5, debugText: "Placeholder")
        return CombinedWidgetEntry(
            date: Date(),
            home: empty,
            labPet: empty,
            builderBase: empty,
            helpers: HelperCooldownWidgetEntry(date: Date(), helpers: [], profileName: ""),
            tapToRefresh: true,
            nickname: ""
        )
    }

    func snapshot(for configuration: WidgetProfileIntent, in context: Context) async -> CombinedWidgetEntry {
        await build(for: configuration, in: context)
    }

    func timeline(for configuration: WidgetProfileIntent, in context: Context) async -> Timeline<CombinedWidgetEntry> {
        let entry = await build(for: configuration, in: context)
        let now = entry.date

        // Speed boost running: one entry per minute so the widget follows the accelerated in-app clock.
        let allUpgrades = entry.home.upgrades + entry.labPet.upgrades + entry.builderBase.upgrades
        let allBoosts = entry.home.activeBoosts + entry.labPet.activeBoosts + entry.builderBase.activeBoosts
        let boostDates = boostEntryDates(upgrades: allUpgrades, activeBoosts: allBoosts, now: now)
        if boostDates.count > 1, let last = boostDates.last {
            let entries = boostDates.map { d in
                CombinedWidgetEntry(
                    date: d,
                    home: entry.home,
                    labPet: entry.labPet,
                    builderBase: entry.builderBase,
                    helpers: entry.helpers,
                    tapToRefresh: entry.tapToRefresh,
                    nickname: entry.nickname,
                    bedtime: entry.bedtime
                )
            }
            return Timeline(entries: entries, policy: .after(last))
        }

        // Default: 15 minutes. Tighten when something is boosted or about to finish.
        var next = now.addingTimeInterval(15 * 60)

        let boostsActive = [entry.home, entry.labPet, entry.builderBase]
            .contains { $0.activeBoosts.contains { $0.endTime > now } }
        if boostsActive {
            next = min(next, now.addingTimeInterval(5 * 60))
        }

        var upgradeRemaining: [TimeInterval] = []
        for part in [entry.home, entry.labPet, entry.builderBase] {
            for upgrade in part.upgrades {
                upgradeRemaining.append(effectiveRemainingSeconds(for: upgrade, activeBoosts: part.activeBoosts, referenceDate: now))
            }
        }
        if let soonest = upgradeRemaining.filter({ $0 > 0 }).min() {
            next = min(next, now.addingTimeInterval(max(soonest + 1, 15)))
            if soonest <= 300 {
                next = min(next, now.addingTimeInterval(60))
            }
        }

        if let helperRemaining = entry.helpers.helpers.map({ $0.remainingSeconds(referenceDate: now) }).filter({ $0 > 0 }).min() {
            next = min(next, now.addingTimeInterval(helperRemaining <= 30 ? 30 : 5 * 60))
        }

        // Re-render exactly when something drops under 1 hour (static -> live countdown) or finishes.
        for part in [entry.home, entry.labPet, entry.builderBase] {
            next = widgetBoundaryAdjusted(next, upgrades: part.upgrades, activeBoosts: part.activeBoosts, now: now)
        }
        if let longestHelper = entry.helpers.helpers.map({ $0.remainingSeconds(referenceDate: now) }).max(), longestHelper > 3600 {
            next = min(next, now.addingTimeInterval(Double(longestHelper - 3600 + 1)))
        }

        return Timeline(entries: [entry], policy: .after(next))
    }

    /// Reuses the existing providers so profile selection / boost / helper logic stays identical.
    private func build(for configuration: WidgetProfileIntent, in context: Context) async -> CombinedWidgetEntry {
        let home = await Provider().snapshot(for: configuration, in: context)
        let labPet = await LabPetProvider().snapshot(for: configuration, in: context)
        let builderBase = BuilderBaseProvider().overviewSnapshot(for: configuration)
        let helpers = await HelperCooldownProvider().snapshot(for: configuration, in: context)
        return CombinedWidgetEntry(
            date: Date(),
            home: home,
            labPet: labPet,
            builderBase: builderBase,
            helpers: helpers,
            tapToRefresh: home.tapToRefresh,
            nickname: widgetNicknameLabel(for: configuration)
        )
    }
}

/// Color schemes for the combined widgets.
/// standard: widgets 6/7 (system background). lavender: widgets 8/9 (#E6E6FA background).
enum CombinedStyle {
    case standard
    case lavender

    private static let lavenderBackground = Color(red: 230.0 / 255.0, green: 230.0 / 255.0, blue: 250.0 / 255.0)
    private static let ink = Color(red: 30.0 / 255.0, green: 27.0 / 255.0, blue: 75.0 / 255.0)
    private static let darkOrange = Color(red: 154.0 / 255.0, green: 59.0 / 255.0, blue: 0.0)
    private static let darkGreen = Color(red: 22.0 / 255.0, green: 101.0 / 255.0, blue: 52.0 / 255.0)

    var isLavender: Bool { self == .lavender }
    var background: Color? { isLavender ? Self.lavenderBackground : nil }
    /// "Builders", "Lab & Pets", "Builder Base"
    var sectionTitleColor: Color { isLavender ? Self.ink : Self.lavenderBackground }
    /// Upgrade names, helper's hut name, nickname
    var nameColor: Color { isLavender ? Self.ink : .primary }
    var nicknameColor: Color { isLavender ? Self.ink : .secondary }
    var timerColor: Color { isLavender ? Self.darkOrange : .orange }
    /// "Complete" and "{n} free"
    var doneColor: Color { isLavender ? Self.darkGreen : .green }
    var emptyLabelColor: Color { isLavender ? Self.darkGreen : Color.green.opacity(0.7) }
    var noDataColor: Color { isLavender ? Self.ink.opacity(0.6) : .secondary }
    /// Moon icon for upgrades that finish during bedtime
    var moonColor: Color {
        isLavender
            ? Color(red: 67.0 / 255.0, green: 56.0 / 255.0, blue: 202.0 / 255.0)
            : Color(red: 139.0 / 255.0, green: 124.0 / 255.0, blue: 246.0 / 255.0)
    }
    var dividerColor: Color { Color.gray.opacity(isLavender ? 0.5 : 0.35) }
}

private struct CombinedProgressBar: View {
    let fraction: Double
    var height: CGFloat = 2
    var tint: Color = .green

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

private struct CombinedUpgradeRow: View {
    let upgrade: BuildingUpgrade
    let activeBoosts: [ActiveBoost]
    let goldPassBoost: Int
    var referenceDate: Date = Date()
    var rowHeight: CGFloat = 17
    var style: CombinedStyle = .standard
    var bedtime: BedtimeSettings = BedtimeSettings()
    var trailingTimer: Bool = false

    var body: some View {
        let completion = effectiveCompletionDate(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate)
        let finishesDuringBedtime = bedtime.contains(completion)
        let isDone = effectiveRemainingSeconds(for: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate) <= 0
        HStack(spacing: 5) {
            trimmedWidgetImage(named: widgetIconName(for: upgrade))
                .interpolation(.none)
                .resizable()
                .clashWidgetTintAwareRendering()
                .scaledToFit()
                .frame(width: rowHeight - 1, height: rowHeight - 1)

            Text(koName(upgrade.name))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(style.nameColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 2)

            if finishesDuringBedtime && !isDone {
                Image(systemName: "moon.fill")
                    .font(.system(size: 8))
                    .foregroundColor(style.moonColor)
            }

            LiveUpgradeTimeText(upgrade: upgrade, activeBoosts: activeBoosts, referenceDate: referenceDate, alignment: .trailing, trailingText: trailingTimer)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isDone ? style.doneColor : style.timerColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) {
            CombinedProgressBar(
                fraction: boostedProgressFraction(for: upgrade, activeBoosts: activeBoosts, goldPassBoost: goldPassBoost, referenceDate: referenceDate),
                tint: style.isLavender ? style.doneColor : .green
            )
        }
    }
}

private struct CombinedEmptyRow: View {
    let label: String
    var rowHeight: CGFloat = 17
    var style: CombinedStyle = .standard

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(style.emptyLabelColor)
                .frame(width: rowHeight - 1, height: rowHeight - 1)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(style.emptyLabelColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: rowHeight)
    }
}

private struct CombinedSectionHeader: View {
    let title: String
    let status: String
    let allBusy: Bool
    var style: CombinedStyle = .standard

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(style.sectionTitleColor)
                .lineLimit(1)
            Spacer(minLength: 2)
            // "All busy" is hidden; only "{n} free" is shown.
            if !allBusy {
                Text(status)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(style.doneColor)
                    .lineLimit(1)
            }
        }
    }
}

/// Right-hand column variants.
enum CombinedLayout {
    /// Widget 5: Lab & Pets + Helper's Hut
    case labPetHelper
    /// Widget 6: Lab & Pets + Helper's Hut + Builder Base, nickname centered at the bottom
    case labPetHelperBuilderBase
}

struct CombinedWidgetEntryView: View {
    var entry: CombinedWidgetEntry
    var layout: CombinedLayout = .labPetHelper
    var style: CombinedStyle = .standard

    private var isFull: Bool { layout == .labPetHelperBuilderBase }
    private var rightRowHeight: CGFloat { isFull ? 14 : 17 }
    // Nickname now sits at the bottom center in both layouts, so 6 builders need slightly shorter rows.
    private var leftRowHeight: CGFloat { isFull ? 14 : (homeSlots >= 6 ? 15 : 17) }
    private var homeSlots: Int { max(min(entry.home.builderCount, 6), 0) }
    private var labPetSlots: Int { 2 }

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                homeColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 1)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: isFull ? 4 : 6) {
                    labPetSection
                    if isFull {
                        builderBaseSection
                    } else {
                        helperSection()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // Fill the full widget height so the center divider and the nickname sit at the same
            // position in every layout (widgets 6-9), regardless of how much content each one has.
            .frame(maxHeight: .infinity, alignment: .top)

            if !entry.home.profileName.isEmpty {
                Text(entry.home.profileName)
                    .font(.system(size: 8))
                    .foregroundColor(style.nicknameColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .widgetTapAction(refresh: entry.tapToRefresh)
    }

    // MARK: Home village builders (left column, shared by both layouts)
    private var homeColumn: some View {
        let busy = entry.home.totalBuilderUpgradesCount
        let allBusy = busy >= entry.home.builderCount
        let free = max(entry.home.builderCount - busy, 0)

        return VStack(alignment: .leading, spacing: homeSlots >= 6 ? 1 : 3) {
            CombinedSectionHeader(
                title: "Builders",
                status: allBusy ? "All busy" : "\(free) free",
                allBusy: allBusy,
                style: style
            )
            ForEach(0..<homeSlots, id: \.self) { index in
                if index < entry.home.upgrades.count {
                    CombinedUpgradeRow(
                        upgrade: entry.home.upgrades[index],
                        activeBoosts: entry.home.activeBoosts,
                        goldPassBoost: entry.home.goldPassBoost,
                        referenceDate: entry.date,
                        rowHeight: leftRowHeight,
                        style: style,
                        bedtime: entry.bedtime
                    )
                } else {
                    CombinedEmptyRow(label: "Builder \(index + 1) available", rowHeight: leftRowHeight, style: style)
                }
            }
            Spacer(minLength: 0)
            if isFull {
                helperSection()
            }
        }
    }

    // MARK: Lab & Pets
    private var labPetSection: some View {
        let used = entry.labPet.upgrades.count
        let allBusy = used >= labPetSlots
        let free = max(labPetSlots - used, 0)

        return VStack(alignment: .leading, spacing: 2) {
            CombinedSectionHeader(
                title: "Lab & Pets",
                status: allBusy ? "All busy" : "\(free) free",
                allBusy: allBusy,
                style: style
            )
            ForEach(0..<labPetSlots, id: \.self) { index in
                if index < entry.labPet.upgrades.count {
                    CombinedUpgradeRow(
                        upgrade: entry.labPet.upgrades[index],
                        activeBoosts: entry.labPet.activeBoosts,
                        goldPassBoost: entry.labPet.goldPassBoost,
                        referenceDate: entry.date,
                        rowHeight: rightRowHeight,
                        style: style,
                        bedtime: entry.bedtime
                    )
                } else {
                    CombinedEmptyRow(label: "Available", rowHeight: rightRowHeight, style: style)
                }
            }
        }
    }

    // MARK: Builder Base (widget 6 only) - 3 builders + 1 Star Lab
    private var builderBaseSection: some View {
        let hallUnlocked = entry.builderBase.builderHallLevel >= 6
        let builderSlots = hallUnlocked ? 3 : 1
        let builderUpgrades = entry.builderBase.upgrades.filter { $0.category == .builderBase }
        let labUpgrades = entry.builderBase.upgrades.filter { $0.category == .starLab }
        let used = min(builderUpgrades.count, builderSlots)
        let allBusy = used >= builderSlots
        let free = max(builderSlots - used, 0)

        return VStack(alignment: .leading, spacing: 2) {
            CombinedSectionHeader(
                title: "Builder Base",
                status: allBusy ? "All busy" : "\(free) free",
                allBusy: allBusy,
                style: style
            )
            ForEach(0..<builderSlots, id: \.self) { index in
                if index < builderUpgrades.count {
                    CombinedUpgradeRow(
                        upgrade: builderUpgrades[index],
                        activeBoosts: entry.builderBase.activeBoosts,
                        goldPassBoost: entry.builderBase.goldPassBoost,
                        referenceDate: entry.date,
                        rowHeight: rightRowHeight,
                        style: style,
                        bedtime: entry.bedtime
                    )
                } else {
                    CombinedEmptyRow(label: "Available", rowHeight: rightRowHeight, style: style)
                }
            }
            if hallUnlocked {
                if let labUpgrade = labUpgrades.first {
                    CombinedUpgradeRow(
                        upgrade: labUpgrade,
                        activeBoosts: entry.builderBase.activeBoosts,
                        goldPassBoost: entry.builderBase.goldPassBoost,
                        referenceDate: entry.date,
                        rowHeight: rightRowHeight,
                        style: style,
                        bedtime: entry.bedtime
                    )
                } else {
                    CombinedEmptyRow(label: "Available", rowHeight: rightRowHeight, style: style)
                }
            }
        }
    }

    // MARK: Helper's Hut (same icon / font / row height as the other rows, separated by a solid line above)
    private func helperSection() -> some View {
        let totalSeconds = 23 * 60 * 60
        let remaining = max(min(entry.helpers.helpers.map { $0.cooldownSeconds }.max() ?? 0, totalSeconds), 0)
        let progress = max(0, min(1, 1 - (Double(remaining) / Double(totalSeconds))))
        let hasData = !entry.helpers.helpers.isEmpty
        let statusText: String = {
            if !hasData { return "No data" }
            if remaining <= 0 { return "Ready" }
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            let seconds = remaining % 60
            if hours > 0 { return "\(hours)h \(minutes)m" }
            if minutes > 0 { return "\(minutes)m \(seconds)s" }
            return "\(seconds)s"
        }()
        let statusColor: Color = !hasData ? style.noDataColor : (remaining > 0 ? style.timerColor : style.doneColor)
        let helperEnd = entry.helpers.helpers.compactMap { $0.expiresAt }.max() ?? Date.distantPast
        let helperRowHeight = isFull ? leftRowHeight : rightRowHeight

        return VStack(alignment: .leading, spacing: 2) {
            Rectangle()
                .fill(style.dividerColor)
                .frame(height: 1)
            HStack(spacing: 5) {
                trimmedWidgetImage(named: "buildings_home/helper_hut")
                    .interpolation(.none)
                    .resizable()
                    .clashWidgetTintAwareRendering()
                    .scaledToFit()
                    .frame(width: helperRowHeight - 1, height: helperRowHeight - 1)
                Text("도우미 오두막")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(style.nameColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                LiveCountdownText(
                    endDate: helperEnd,
                    fallback: statusText,
                    referenceDate: entry.date,
                    alignment: .trailing,
                    width: 38
                )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: helperRowHeight)
            .overlay(alignment: .bottom) {
                CombinedProgressBar(
                    fraction: hasData ? progress : 0,
                    tint: style.isLavender ? style.doneColor : .green
                )
            }
        }
    }
}

/// Widget 5: Builders | Lab & Pets + Helper's Hut
struct CombinedWidget: Widget {
    let kind: String = "CombinedWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: CombinedProvider()) { entry in
            CombinedWidgetEntryView(entry: entry, layout: .labPetHelper)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Overview")
        .description("Builders, Lab & Pets and Helper's Hut in one widget. Choose a profile or use the last opened one.")
        .supportedFamilies([.systemMedium])
    }
}

/// Widget 6: Builders | Lab & Pets + Helper's Hut + Builder Base, nickname at the bottom
struct CombinedFullWidget: Widget {
    let kind: String = "CombinedFullWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: CombinedProvider()) { entry in
            CombinedWidgetEntryView(entry: entry, layout: .labPetHelperBuilderBase)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Overview + Builder Base")
        .description("Builders, Lab & Pets, Helper's Hut and Builder Base with your nickname.")
        .supportedFamilies([.systemMedium])
    }
}

/// Widget 8: same as widget 6 (Overview) with a #E6E6FA background and high-contrast text colors
struct CombinedLavenderWidget: Widget {
    let kind: String = "CombinedLavenderWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: CombinedProvider()) { entry in
            CombinedWidgetEntryView(entry: entry, layout: .labPetHelper, style: .lavender)
                .containerBackground(for: .widget) {
                    CombinedStyle.lavender.background ?? Color.clear
                }
        }
        .configurationDisplayName("Overview (Lavender)")
        .description("Overview widget on a lavender background. Choose a profile or use the last opened one.")
        .supportedFamilies([.systemMedium])
    }
}

/// Widget 9: same as widget 7 (Overview + Builder Base) with a #E6E6FA background and high-contrast text colors
struct CombinedFullLavenderWidget: Widget {
    let kind: String = "CombinedFullLavenderWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetProfileIntent.self, provider: CombinedProvider()) { entry in
            CombinedWidgetEntryView(entry: entry, layout: .labPetHelperBuilderBase, style: .lavender)
                .containerBackground(for: .widget) {
                    CombinedStyle.lavender.background ?? Color.clear
                }
        }
        .configurationDisplayName("Overview + Builder Base (Lavender)")
        .description("Overview + Builder Base widget on a lavender background with your nickname.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Dual Profile Widget (2x1): profile 1 | profile 2

/// Profile choice for the dual widget (no "automatic" entry: an unset slot falls back to the 1st / 2nd profile).
struct DualProfileEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Profile")
    static var defaultQuery = DualProfileEntityQuery()

    var id: String   // profile UUID string
    var displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}

struct DualProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [DualProfileEntity.ID]) async throws -> [DualProfileEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DualProfileEntity] {
        allEntities()
    }

    private func allEntities() -> [DualProfileEntity] {
        guard let state = PersistentStore.loadState() else { return [] }
        return state.profiles.map { profile in
            let name: String
            if !profile.displayName.isEmpty {
                name = profile.displayName
            } else if !profile.tag.isEmpty {
                name = "#\(profile.tag)"
            } else {
                name = "Profile"
            }
            return DualProfileEntity(id: profile.id.uuidString, displayName: name)
        }
    }
}

struct DualProfileIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Profiles"
    static let description: IntentDescription = "Choose the profiles shown on the left and right. Leave empty to use the 1st and 2nd profile."

    @Parameter(title: "Left Profile", description: "Leave empty to use the 1st profile")
    var leftProfile: DualProfileEntity?

    @Parameter(title: "Right Profile", description: "Leave empty to use the 2nd profile")
    var rightProfile: DualProfileEntity?

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

/// Everything one half of the dual widget needs.
struct DualProfileSide {
    var nickname: String = ""
    var upgrades: [BuildingUpgrade] = []
    var activeBoosts: [ActiveBoost] = []
    var goldPassBoost: Int = 0
    var lastUpdated: Date? = nil
    /// Profile setting "Tap widget to refresh" (an empty slot has no profile, so it counts as off).
    var tapToRefresh: Bool = false
}

struct DualProfileEntry: TimelineEntry {
    let date: Date
    let left: DualProfileSide
    let right: DualProfileSide
    var bedtime: BedtimeSettings = BedtimeSettings.load()

    /// Same behavior as widgets 6-9: tap refreshes in place; app opens only when no shown profile has it on.
    var tapToRefresh: Bool { left.tapToRefresh || right.tapToRefresh }
}

struct DualProfileProvider: AppIntentTimelineProvider {
    typealias Intent = DualProfileIntent
    typealias Entry = DualProfileEntry

    func placeholder(in context: Context) -> DualProfileEntry {
        DualProfileEntry(date: Date(), left: DualProfileSide(), right: DualProfileSide())
    }

    func snapshot(for configuration: DualProfileIntent, in context: Context) async -> DualProfileEntry {
        build(for: configuration, date: Date())
    }

    func timeline(for configuration: DualProfileIntent, in context: Context) async -> Timeline<DualProfileEntry> {
        let first = build(for: configuration, date: Date())
        // One entry per minute for the next hour so the timers and sorting stay current, plus an entry
        // exactly when a profile's "last updated" crosses 1 hour (live m:ss -> static "Nh Nm").
        let end = first.date.addingTimeInterval(3600)
        var dates: [Date] = (0..<60).map { first.date.addingTimeInterval(Double($0) * 60) }
        for last in [first.left.lastUpdated, first.right.lastUpdated].compactMap({ $0 }) {
            let boundary = last.addingTimeInterval(3600)
            if boundary > first.date && boundary < end { dates.append(boundary) }
        }
        // Re-render exactly when an upgrade drops under 1 hour (static -> live countdown) and when it
        // finishes ("Complete"), same as widgets 6-9.
        for side in [first.left, first.right] {
            for upgrade in side.upgrades {
                let remaining = effectiveRemainingSeconds(for: upgrade, activeBoosts: side.activeBoosts, referenceDate: first.date)
                if remaining > 3600 {
                    dates.append(first.date.addingTimeInterval(remaining - 3600 + 1))
                }
                if remaining > 0 {
                    dates.append(first.date.addingTimeInterval(remaining + 1))
                }
            }
        }
        dates = dates.filter { $0 >= first.date && $0 < end }
        dates.sort()
        let entries: [DualProfileEntry] = dates.map { d in
            DualProfileEntry(date: d, left: first.left, right: first.right, bedtime: first.bedtime)
        }
        return Timeline(entries: entries, policy: .after(end))
    }

    private func build(for configuration: DualProfileIntent, date: Date) -> DualProfileEntry {
        let profiles = PersistentStore.loadState()?.profiles ?? []
        func resolve(_ entity: DualProfileEntity?, fallbackIndex: Int) -> PlayerAccount? {
            if let entity, let id = UUID(uuidString: entity.id),
               let match = profiles.first(where: { $0.id == id }) {
                return match
            }
            return profiles.indices.contains(fallbackIndex) ? profiles[fallbackIndex] : nil
        }
        func side(for profile: PlayerAccount?) -> DualProfileSide {
            guard let profile else { return DualProfileSide() }
            return DualProfileSide(
                nickname: widgetNicknameOnly(for: profile),
                upgrades: profile.activeUpgrades,
                activeBoosts: profile.activeBoosts,
                goldPassBoost: max(profile.goldPassBoost, 0),
                lastUpdated: profile.lastImportDate,
                tapToRefresh: profile.widgetTapRefresh
            )
        }
        return DualProfileEntry(
            date: date,
            left: side(for: resolve(configuration.leftProfile, fallbackIndex: 0)),
            right: side(for: resolve(configuration.rightProfile, fallbackIndex: 1))
        )
    }
}

/// "Last updated" label: under 1 hour a live "m:ss" count-up (ticks every second by itself),
/// 1 hour or more a static "Nh Nm" (also for 1 day or more, no seconds).
private struct DualUpdatedText: View {
    let last: Date?
    let now: Date

    var body: some View {
        if let last {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 3600 {
                let total = Int(elapsed)
                Text("\(total / 3600)h \((total % 3600) / 60)m")
            } else {
                let start = min(last, now)
                Text(timerInterval: start...start.addingTimeInterval(86400), pauseTime: nil, countsDown: false, showsHours: false)
                    .monospacedDigit()
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 38, alignment: .trailing)
            }
        } else {
            Text("--")
        }
    }
}

private struct DualProfileColumn: View {
    let side: DualProfileSide
    let date: Date
    let bedtime: BedtimeSettings
    private let rowHeight: CGFloat = 16

    var body: some View {
        // The 5 upgrades with the least time left (Helper's Hut is not an upgrade, so it never shows here).
        let rows = Array(
            side.upgrades
                .sorted {
                    effectiveRemainingSeconds(for: $0, activeBoosts: side.activeBoosts, referenceDate: date)
                        < effectiveRemainingSeconds(for: $1, activeBoosts: side.activeBoosts, referenceDate: date)
                }
                .prefix(5)
        )

        VStack(spacing: 3) {
            Text(side.nickname)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, upgrade in
                    CombinedUpgradeRow(
                        upgrade: upgrade,
                        activeBoosts: side.activeBoosts,
                        goldPassBoost: side.goldPassBoost,
                        referenceDate: date,
                        rowHeight: rowHeight,
                        bedtime: bedtime,
                        trailingTimer: true
                    )
                }
            }

            Spacer(minLength: 0)

            DualUpdatedText(last: side.lastUpdated, now: date)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct DualProfileEntryView: View {
    var entry: DualProfileEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DualProfileColumn(side: entry.left, date: entry.date, bedtime: entry.bedtime)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            DualProfileColumn(side: entry.right, date: entry.date, bedtime: entry.bedtime)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .widgetTapAction(refresh: entry.tapToRefresh)
    }
}

/// Widget 10: two profiles side by side
struct DualProfileWidget: Widget {
    let kind: String = "DualProfileWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DualProfileIntent.self, provider: DualProfileProvider()) { entry in
            DualProfileEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dual Profiles")
        .description("Two profiles side by side with their 5 soonest upgrades and last update time.")
        .supportedFamilies([.systemMedium])
    }
}
