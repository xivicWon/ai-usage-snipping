// ClaudeMonitor/Data/ProfileStore.swift
import Foundation
import Combine

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var claudeHomePath: String   // e.g. "/Users/alice/.claude"

    var projectsURL: URL {
        URL(fileURLWithPath: claudeHomePath).appendingPathComponent("projects")
    }

    static func defaultProfile() -> Profile {
        Profile(
            id: UUID(),
            name: "기본",
            claudeHomePath: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".claude").path
        )
    }
}

final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfileId: UUID

    private let defaults = UserDefaults.standard
    private let profilesKey = "profiles_v1"
    private let activeKey = "active_profile_id"

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileId }
    }

    private init() {
        // Load persisted profiles
        if let data = defaults.data(forKey: profilesKey),
           let saved = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = saved
        }
        // Load active id
        if let raw = defaults.string(forKey: activeKey),
           let uuid = UUID(uuidString: raw) {
            activeProfileId = uuid
        } else {
            activeProfileId = UUID() // will be fixed below
        }
        // Ensure at least one profile exists
        if profiles.isEmpty {
            let def = Profile.defaultProfile()
            profiles = [def]
            activeProfileId = def.id
            persist()
        } else if profiles.first(where: { $0.id == activeProfileId }) == nil {
            activeProfileId = profiles[0].id
        }
    }

    func add(name: String, claudeHomePath: String) {
        let p = Profile(id: UUID(), name: name, claudeHomePath: claudeHomePath)
        profiles.append(p)
        persist()
    }

    func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id ?? UUID()
        }
        persist()
    }

    func activate(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        defaults.set(id.uuidString, forKey: activeKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(activeProfileId.uuidString, forKey: activeKey)
    }
}
