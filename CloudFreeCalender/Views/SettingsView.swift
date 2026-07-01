import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: CalendarStore

    @State private var host = ""
    @State private var port = "21"
    @State private var username = ""
    @State private var password = ""
    @State private var remotePath = "/kalender/"
    @State private var trustSelfSigned = true
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("FritzBox FTPS") {
                    TextField("Host (z.B. fritz.box)", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Benutzername", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Passwort", text: $password)
                }

                Section("Verzeichnis") {
                    TextField("Pfad auf FritzBox", text: $remotePath)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Sicherheit") {
                    Toggle("Selbstsignierte Zertifikate akzeptieren", isOn: $trustSelfSigned)
                }

                Section {
                    Button(isTesting ? "Teste..." : "Verbindung testen") {
                        testConnection()
                    }
                    .disabled(isTesting || host.isEmpty)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("Verbunden") ? .green : .red)
                    }
                }

                Section {
                    Button("Einstellungen sichern") {
                        saveSettings()
                    }
                    .disabled(host.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear { loadFromStore() }
        }
    }

    private func loadFromStore() {
        let s = store.settings
        host = s.host; port = "\(s.port)"; username = s.username
        password = s.password; remotePath = s.remotePath
        trustSelfSigned = s.trustSelfSignedCertificates
    }

    private func saveSettings() {
        var s = FTPSSettings()
        s.host = host; s.port = Int(port) ?? 21; s.username = username
        s.password = password; s.remotePath = remotePath
        s.trustSelfSignedCertificates = trustSelfSigned
        store.saveSettings(s)
    }

    private func testConnection() {
        saveSettings()
        isTesting = true; testResult = nil
        let svc = CalendarService(settings: store.settings)
        Task {
            do {
                testResult = try await svc.testConnection()
            } catch {
                testResult = error.localizedDescription
            }
            isTesting = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CalendarStore())
        .preferredColorScheme(.dark)
}
