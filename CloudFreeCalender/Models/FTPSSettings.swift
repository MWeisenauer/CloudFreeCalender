import Foundation

nonisolated struct FTPSSettings: Codable, Sendable {
    var host: String = ""
    var port: Int = 21
    var username: String = ""
    var password: String = ""
    var remotePath: String = "/kalender/"
    var trustSelfSignedCertificates: Bool = true

    private static let userDefaultsKey = "ftps_calendar_settings_v1"
    private static let keychainAccount = "ftps_calendar_password_v1"

    static func load() -> FTPSSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var settings = try? JSONDecoder().decode(FTPSSettings.self, from: data) else {
            return FTPSSettings()
        }
        if let stored = KeychainStore.string(for: keychainAccount) {
            settings.password = stored
        }
        return settings
    }

    func save() {
        KeychainStore.setString(password, for: FTPSSettings.keychainAccount)
        var sanitized = self
        sanitized.password = ""
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: FTPSSettings.userDefaultsKey)
        }
    }

    var isConfigured: Bool { !host.isEmpty && !username.isEmpty }
}
