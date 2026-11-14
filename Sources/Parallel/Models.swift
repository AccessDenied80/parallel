import Foundation

/// Як саме ізолюється окремий екземпляр застосунку.
enum LaunchStrategy: String, Codable, CaseIterable, Identifiable {
    /// Визначити автоматично за вмістом бандла.
    case auto
    /// Electron / Chromium: `--user-data-dir=<профіль>`.
    case chromium
    /// Firefox і похідні: `-no-remote -profile <профіль>`.
    case firefox
    /// Копія .app зі зміненим bundle ID і ad-hoc підписом — окремі налаштування, контейнер, Keychain-записи.
    case clone
    /// Просто новий процес (`open -n`) без ізоляції даних.
    case plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Автоматично"
        case .chromium: "Electron / Chromium"
        case .firefox: "Firefox"
        case .clone: "Клон застосунку"
        case .plain: "Без ізоляції"
        }
    }

    var hint: String {
        switch self {
        case .auto: "Метод підбирається за вмістом застосунку."
        case .chromium: "Окрема папка даних через --user-data-dir."
        case .firefox: "Окремий профіль Firefox через -profile."
        case .clone: "Копія .app з власним bundle ID: окремі налаштування й дані."
        case .plain: "Новий процес, але дані спільні з основною копією."
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Додаткові аргументи командного рядка (через пробіл).
    var extraArguments: String = ""
}

struct AppEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var path: String
    var name: String
    var bundleID: String
    var strategy: LaunchStrategy = .auto
    var profiles: [Profile] = []

    var url: URL { URL(fileURLWithPath: path) }
}
