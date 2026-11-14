import AppKit

enum LauncherError: LocalizedError {
    case appMissing(String)
    case command(String, String)
    case badInfoPlist

    var errorDescription: String? {
        switch self {
        case .appMissing(let p): "Застосунок не знайдено: \(p)"
        case .command(let cmd, let out): "Команда «\(cmd)» завершилась з помилкою:\n\(out)"
        case .badInfoPlist: "Не вдалося прочитати або змінити Info.plist."
        }
    }
}

enum Launcher {
    // MARK: Визначення стратегії

    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "com.yandex.desktop.yandex-browser",
    ]

    static func detect(appURL: URL, bundleID: String) -> LaunchStrategy {
        if chromiumBundleIDs.contains(bundleID) { return .chromium }
        if bundleID.hasPrefix("org.mozilla.") || bundleID.hasPrefix("net.waterfox") || bundleID.hasPrefix("app.zen-browser") {
            return .firefox
        }
        let frameworks = appURL.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        if names.contains(where: { $0.contains("Electron") || $0.contains("Chrom") }) { return .chromium }
        return .clone
    }

    static func effectiveStrategy(for app: AppEntry) -> LaunchStrategy {
        app.strategy == .auto ? detect(appURL: app.url, bundleID: app.bundleID) : app.strategy
    }

    // MARK: Запуск

    /// Запускає окремий екземпляр і повертає запущений процес.
    static func launch(app: AppEntry, profile: Profile) async throws -> NSRunningApplication {
        guard FileManager.default.fileExists(atPath: app.path) else { throw LauncherError.appMissing(app.path) }

        let dir = Paths.profileDir(profile)
        try Paths.ensure(dir)

        var target = app.url
        var args: [String] = []

        switch effectiveStrategy(for: app) {
        case .chromium:
            let data = dir.appendingPathComponent("data", isDirectory: true)
            try Paths.ensure(data)
            args = ["--user-data-dir=\(data.path)"]
        case .firefox:
            let data = dir.appendingPathComponent("firefox", isDirectory: true)
            try Paths.ensure(data)
            args = ["-no-remote", "-profile", data.path]
        case .clone:
            target = try await Task.detached(priority: .userInitiated) {
                try prepareClone(app: app, profile: profile, in: dir)
            }.value
        case .plain, .auto:
            break
        }

        args += splitArguments(profile.extraArguments)

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = args
        config.activates = true
        return try await NSWorkspace.shared.openApplication(at: target, configuration: config)
    }

    // MARK: Клонування

    private struct CloneMarker: Codable, Equatable {
        var sourcePath: String
        var sourceStamp: String
        var profileName: String
    }

    static func cloneURL(app: AppEntry, profile: Profile) -> URL {
        Paths.profileDir(profile).appendingPathComponent(app.url.lastPathComponent)
    }

    static func cloneBundleID(app: AppEntry, profile: Profile) -> String {
        "\(app.bundleID).parallel.\(profile.id.uuidString.prefix(8).lowercased())"
    }

    /// Готує (або перевикористовує) копію .app з унікальним bundle ID. Клон перестворюється,
    /// коли оригінал оновився або профіль перейменовано.
    private static func prepareClone(app: AppEntry, profile: Profile, in dir: URL) throws -> URL {
        let fm = FileManager.default
        let dest = cloneURL(app: app, profile: profile)
        let markerURL = dir.appendingPathComponent("clone.json")
        let marker = CloneMarker(sourcePath: app.path, sourceStamp: sourceStamp(app.url), profileName: profile.name)

        if fm.fileExists(atPath: dest.path),
           let data = try? Data(contentsOf: markerURL),
           let old = try? JSONDecoder().decode(CloneMarker.self, from: data),
           old == marker {
            return dest
        }

        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try run("/usr/bin/ditto", [app.path, dest.path])

        let plistURL = dest.appendingPathComponent("Contents/Info.plist")
        guard let raw = try? Data(contentsOf: plistURL),
              var plist = try PropertyListSerialization.propertyList(from: raw, format: nil) as? [String: Any]
        else { throw LauncherError.badInfoPlist }

        let displayName = "\(app.name) (\(profile.name))"
        plist["CFBundleIdentifier"] = cloneBundleID(app: app, profile: profile)
        plist["CFBundleName"] = displayName
        plist["CFBundleDisplayName"] = displayName
        // Автооновлення клону (Sparkle) лише зламало б підпис.
        plist["SUEnableAutomaticChecks"] = false
        plist["SUFeedURL"] = nil
        let out = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try out.write(to: plistURL)

        // Чек App Store прив'язаний до старого bundle ID — прибираємо, інакше застосунок може не стартувати.
        try? fm.removeItem(at: dest.appendingPathComponent("Contents/_MASReceipt"))

        _ = try? run("/usr/bin/xattr", ["-cr", dest.path])
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", dest.path])

        try JSONEncoder().encode(marker).write(to: markerURL)
        return dest
    }

    private static func sourceStamp(_ appURL: URL) -> String {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        let attrs = try? FileManager.default.attributesOfItem(atPath: plist.path)
        let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let info = NSDictionary(contentsOf: plist)
        let v = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v)@\(Int(date))"
    }

    // MARK: Допоміжне

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else {
            throw LauncherError.command(([tool] + args).joined(separator: " "), text)
        }
        return text
    }

    /// Розбиває рядок аргументів з урахуванням лапок.
    static func splitArguments(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        for ch in s {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
