import Foundation

enum Paths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Parallel", isDirectory: true)
    }()

    static var store: URL { root.appendingPathComponent("apps.json") }

    /// Папка конкретного профілю: тут лежать дані (Electron/Firefox) або клон .app.
    static func profileDir(_ profile: Profile) -> URL {
        root.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }

    static func ensure(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
