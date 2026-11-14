import AppKit
import Combine

@MainActor
final class Store: ObservableObject {
    @Published var apps: [AppEntry] = [] { didSet { save() } }
    /// Запущені екземпляри: профіль → процес.
    @Published private(set) var running: [UUID: NSRunningApplication] = [:]
    /// Профілі, для яких зараз готується запуск (наприклад, створюється клон).
    @Published private(set) var busy: Set<UUID> = []
    @Published var errorMessage: String?

    private var observers: [NSObjectProtocol] = []

    init() {
        load()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.handleTermination(pid: pid) }
        })
        adoptRunningClones()
    }

    // MARK: Застосунки

    func addApp(at url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            errorMessage = "«\(url.lastPathComponent)» не схожий на застосунок macOS."
            return
        }
        if bundleID == Bundle.main.bundleIdentifier || apps.contains(where: { $0.path == url.path }) { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        var entry = AppEntry(path: url.path, name: name, bundleID: bundleID)
        entry.profiles = [Profile(name: "Профіль 1")]
        apps.append(entry)
    }

    func removeApp(_ app: AppEntry, deleteData: Bool) {
        for profile in app.profiles {
            running[profile.id]?.terminate()
            if deleteData { try? FileManager.default.removeItem(at: Paths.profileDir(profile)) }
        }
        apps.removeAll { $0.id == app.id }
    }

    func setStrategy(_ strategy: LaunchStrategy, for appID: UUID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].strategy = strategy
    }

    // MARK: Профілі

    func addProfile(to appID: UUID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].profiles.append(Profile(name: "Профіль \(apps[i].profiles.count + 1)"))
    }

    func updateProfile(_ profile: Profile, in appID: UUID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }),
              let j = apps[i].profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        apps[i].profiles[j] = profile
    }

    func deleteProfile(_ profile: Profile, in appID: UUID, deleteData: Bool) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        running[profile.id]?.terminate()
        if deleteData { try? FileManager.default.removeItem(at: Paths.profileDir(profile)) }
        apps[i].profiles.removeAll { $0.id == profile.id }
    }

    // MARK: Запуск

    func isRunning(_ profile: Profile) -> Bool { running[profile.id]?.isTerminated == false }

    func launch(_ profile: Profile, of app: AppEntry) {
        if let existing = running[profile.id], !existing.isTerminated {
            existing.activate()
            return
        }
        busy.insert(profile.id)
        Task {
            defer { busy.remove(profile.id) }
            do {
                let proc = try await Launcher.launch(app: app, profile: profile)
                running[profile.id] = proc
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func quit(_ profile: Profile) {
        running[profile.id]?.terminate()
    }

    func launchAll(of app: AppEntry) {
        for profile in app.profiles where !isRunning(profile) { launch(profile, of: app) }
    }

    func revealData(_ profile: Profile) {
        let dir = Paths.profileDir(profile)
        try? Paths.ensure(dir)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    // MARK: Внутрішнє

    private func handleTermination(pid: pid_t?) {
        guard let pid else { return }
        for (key, app) in running where app.processIdentifier == pid { running[key] = nil }
    }

    /// Після перезапуску Parallel підхоплює вже запущені клони за їхнім bundle ID.
    private func adoptRunningClones() {
        let all = NSWorkspace.shared.runningApplications
        for app in apps {
            for profile in app.profiles {
                let id = Launcher.cloneBundleID(app: app, profile: profile)
                if let proc = all.first(where: { $0.bundleIdentifier == id }) { running[profile.id] = proc }
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Paths.store),
              let decoded = try? JSONDecoder().decode([AppEntry].self, from: data) else { return }
        apps = decoded
    }

    private func save() {
        do {
            try Paths.ensure(Paths.root)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(apps).write(to: Paths.store, options: .atomic)
        } catch {
            errorMessage = "Не вдалося зберегти налаштування: \(error.localizedDescription)"
        }
    }
}
