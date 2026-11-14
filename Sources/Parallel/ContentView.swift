import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: UUID?
    @State private var appToRemove: AppEntry?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.apps) { app in
                    AppRow(app: app)
                        .tag(app.id)
                        .contextMenu {
                            Button("Показати у Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([app.url])
                            }
                            Divider()
                            Button("Видалити…", role: .destructive) { appToRemove = app }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .overlay {
                if store.apps.isEmpty {
                    ContentUnavailableView("Немає застосунків",
                                           systemImage: "square.on.square.dashed",
                                           description: Text("Натисніть «+» або перетягніть .app у вікно."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { pickApps(store) } label: { Label("Додати застосунок", systemImage: "plus") }
                }
            }
        } detail: {
            if let id = selection, let app = store.apps.first(where: { $0.id == id }) {
                AppDetailView(app: app)
            } else {
                ContentUnavailableView("Оберіть застосунок", systemImage: "sidebar.left")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension == "app" }
            apps.forEach(store.addApp(at:))
            if let last = apps.last { selection = store.apps.first { $0.path == last.path }?.id }
            return !apps.isEmpty
        }
        .onAppear { if selection == nil { selection = store.apps.first?.id } }
        .confirmationDialog("Видалити «\(appToRemove?.name ?? "")» зі списку?",
                            isPresented: Binding(get: { appToRemove != nil }, set: { if !$0 { appToRemove = nil } }),
                            titleVisibility: .visible) {
            Button("Видалити разом із даними профілів", role: .destructive) {
                if let app = appToRemove { store.removeApp(app, deleteData: true) }
            }
            Button("Лише прибрати зі списку") {
                if let app = appToRemove { store.removeApp(app, deleteData: false) }
            }
        } message: {
            Text("Сам застосунок не видаляється. Дані профілів (клони, папки даних) можна залишити.")
        }
        .alert("Помилка", isPresented: Binding(get: { store.errorMessage != nil },
                                               set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private struct AppRow: View {
    @EnvironmentObject private var store: Store
    let app: AppEntry

    var body: some View {
        let count = app.profiles.filter(store.isRunning).count
        HStack(spacing: 8) {
            AppIcon(path: app.path, size: 24)
            Text(app.name).lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.green.opacity(0.25), in: Capsule())
            }
        }
    }
}

struct AppIcon: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

private struct AppDetailView: View {
    @EnvironmentObject private var store: Store
    let app: AppEntry

    var body: some View {
        let effective = Launcher.effectiveStrategy(for: app)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                AppIcon(path: app.path, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.title2.bold())
                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Picker("Ізоляція", selection: Binding(get: { app.strategy },
                                                              set: { store.setStrategy($0, for: app.id) })) {
                            ForEach(LaunchStrategy.allCases) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        if app.strategy == .auto {
                            Text("→ \(effective.title)").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    Text(effective.hint).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Button { store.launchAll(of: app) } label: { Label("Запустити всі", systemImage: "play.fill") }
                        .disabled(app.profiles.isEmpty)
                    Button { store.addProfile(to: app.id) } label: { Label("Новий профіль", systemImage: "plus") }
                }
            }
            .padding(20)

            if effective == .clone {
                Label("Перший запуск профілю створює копію застосунку (може зайняти кілька секунд). " +
                      "Застосунки з прив'язкою до iCloud або ліцензії App Store можуть у копії не працювати.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }

            Divider()

            List {
                ForEach(app.profiles) { profile in
                    ProfileRow(app: app, profile: profile)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ProfileRow: View {
    @EnvironmentObject private var store: Store
    let app: AppEntry
    let profile: Profile
    @State private var confirmDelete = false

    private func binding<T>(_ keyPath: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { profile[keyPath: keyPath] },
                set: { var p = profile; p[keyPath: keyPath] = $0; store.updateProfile(p, in: app.id) })
    }

    var body: some View {
        let running = store.isRunning(profile)
        let busy = store.busy.contains(profile.id)
        HStack(spacing: 12) {
            Circle()
                .fill(running ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
                .help(running ? "Запущено" : "Не запущено")
            VStack(alignment: .leading, spacing: 4) {
                TextField("Назва профілю", text: binding(\.name))
                    .textFieldStyle(.plain).font(.headline)
                TextField("Додаткові аргументи (необов'язково)", text: binding(\.extraArguments))
                    .textFieldStyle(.plain).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if running {
                Button("Показати") { store.launch(profile, of: app) }
                Button("Завершити") { store.quit(profile) }
            } else {
                Button { store.launch(profile, of: app) } label: { Label("Запустити", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }
            Menu {
                Button("Відкрити папку даних") { store.revealData(profile) }
                Divider()
                Button("Видалити профіль…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 6)
        .confirmationDialog("Видалити профіль «\(profile.name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Видалити разом із даними", role: .destructive) {
                store.deleteProfile(profile, in: app.id, deleteData: true)
            }
            Button("Лише прибрати зі списку") {
                store.deleteProfile(profile, in: app.id, deleteData: false)
            }
        } message: {
            Text("Дані профілю зберігаються в ~/Library/Application Support/Parallel/Profiles. " +
                 "Налаштування клонів у ~/Library/Preferences і ~/Library/Containers залишаться в будь-якому разі.")
        }
    }
}
