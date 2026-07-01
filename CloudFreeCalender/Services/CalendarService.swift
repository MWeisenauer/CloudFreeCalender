import Foundation

// MARK: - Errors

enum CalendarFTPSError: LocalizedError {
    case notConfigured
    case connectionFailed(String)
    case authFailed
    case tlsFailed
    case listingFailed
    case downloadFailed
    case uploadFailed(String)
    case deleteFailed(String)
    case invalidResponse(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConfigured:             return "FTPS nicht konfiguriert – bitte Einstellungen prüfen."
        case .connectionFailed(let m):   return "Verbindungsfehler: \(m)"
        case .authFailed:                return "Anmeldung fehlgeschlagen."
        case .tlsFailed:                 return "TLS-Handshake fehlgeschlagen."
        case .listingFailed:             return "Verzeichnis konnte nicht geladen werden."
        case .downloadFailed:            return "Datei konnte nicht heruntergeladen werden."
        case .uploadFailed(let m):       return "Upload fehlgeschlagen: \(m)"
        case .deleteFailed(let m):       return "Löschen fehlgeschlagen: \(m)"
        case .invalidResponse(let m):    return "Ungültige Serverantwort: \(m)"
        case .notConnected:              return "Nicht verbunden."
        }
    }
}

// MARK: - TLS delegate

private final class CalendarFTPSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let allowSelfSigned: Bool
    nonisolated(unsafe) var dataChannelMode = false
    init(allowSelfSigned: Bool) { self.allowSelfSigned = allowSelfSigned }

    nonisolated func urlSession(_ session: URLSession,
                                didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        if allowSelfSigned || dataChannelMode {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - FTPS actor

actor CalendarService {
    private let settings: FTPSSettings

    private var controlTask: URLSessionStreamTask?
    private var urlSession: URLSession?
    private var ftpDelegate: CalendarFTPSDelegate?
    private var readBuffer = Data()
    private var encryptDataChannel = false

    private let commandTimeout: TimeInterval = 30
    private let readTimeout: TimeInterval    = 30
    private let dataTimeout: TimeInterval    = 120

    init(settings: FTPSSettings) { self.settings = settings }

    // MARK: - Public API

    func fetchAllEvents() async throws -> [CalendarEvent] {
        guard settings.isConfigured else { throw CalendarFTPSError.notConfigured }
        try await connect()
        defer { disconnect() }
        let filenames = try await listFiles()
        var events: [CalendarEvent] = []
        for filename in filenames {
            if let event = try? await fetchEvent(filename: filename) {
                events.append(event)
            }
        }
        return events.sorted { $0.startDate < $1.startDate }
    }

    func uploadEvent(_ event: CalendarEvent) async throws {
        guard settings.isConfigured else { throw CalendarFTPSError.notConfigured }
        guard let data = CalendarEvent.encode(event).data(using: .utf8) else {
            throw CalendarFTPSError.uploadFailed("Termin konnte nicht kodiert werden.")
        }
        try await connect()
        defer { disconnect() }
        try await storeFile(filename: event.remoteFilename, data: data)
    }

    func deleteEvent(filename: String) async throws {
        guard settings.isConfigured else { throw CalendarFTPSError.notConfigured }
        try await connect()
        defer { disconnect() }
        guard let controlTask else { throw CalendarFTPSError.notConnected }
        try await send("DELE \(filename)\r\n", to: controlTask)
        let resp = try await readResponse(from: controlTask)
        guard resp.hasPrefix("2") else { throw CalendarFTPSError.deleteFailed(resp) }
    }

    func testConnection() async throws -> String {
        guard settings.isConfigured else { throw CalendarFTPSError.notConfigured }
        try await connect()
        defer { disconnect() }
        let files = try await listFiles()
        return "Verbunden! \(files.count) Termin(e) im Verzeichnis."
    }

    // MARK: - Connection

    private func connect() async throws {
        let delegate = CalendarFTPSDelegate(allowSelfSigned: settings.trustSelfSignedCertificates)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = commandTimeout
        config.timeoutIntervalForResource = dataTimeout
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        ftpDelegate = delegate; urlSession = session; readBuffer = Data(); encryptDataChannel = false

        let task = session.streamTask(withHostName: settings.host, port: settings.port)
        task.resume()

        let banner = try await readResponse(from: task)
        guard banner.hasPrefix("220") else { throw CalendarFTPSError.connectionFailed("Kein FTP-Banner: \(banner)") }

        try await send("AUTH TLS\r\n", to: task)
        guard (try await readResponse(from: task)).hasPrefix("234") else { throw CalendarFTPSError.tlsFailed }
        task.startSecureConnection()

        try await send("USER \(settings.username)\r\n", to: task)
        let userResp = try await readResponse(from: task)
        if userResp.hasPrefix("331") {
            try await send("PASS \(settings.password)\r\n", to: task)
            guard (try await readResponse(from: task)).hasPrefix("230") else { throw CalendarFTPSError.authFailed }
        } else if !userResp.hasPrefix("230") { throw CalendarFTPSError.authFailed }

        try await send("PBSZ 0\r\n", to: task); _ = try await readResponse(from: task)
        try await send("PROT C\r\n", to: task); _ = try await readResponse(from: task)

        let path = settings.remotePath.isEmpty ? "/" : settings.remotePath
        if path != "/" {
            try await send("CWD \(path)\r\n", to: task)
            let cwd = try await readResponse(from: task)
            guard cwd.hasPrefix("2") else { throw CalendarFTPSError.connectionFailed("Verzeichnis nicht gefunden: \(path)") }
        }
        controlTask = task
    }

    private func disconnect() {
        controlTask?.cancel(); controlTask = nil
        urlSession?.invalidateAndCancel(); urlSession = nil
        ftpDelegate = nil
    }

    // MARK: - FTP operations

    private func listFiles() async throws -> [String] {
        guard let controlTask, let urlSession else { throw CalendarFTPSError.notConnected }
        try await send("TYPE A\r\n", to: controlTask); _ = try await readResponse(from: controlTask)

        var dataTask = try await openDataChannel(controlTask: controlTask, session: urlSession)
        try await send("NLST\r\n", to: controlTask)
        var reply = try await readResponse(from: controlTask)

        if reply.hasPrefix("425") {
            dataTask.cancel()
            try await upgradeToProtP(controlTask: controlTask)
            dataTask = try await openDataChannel(controlTask: controlTask, session: urlSession)
            try await send("NLST\r\n", to: controlTask)
            reply = try await readResponse(from: controlTask)
        }
        // 226/250 = transfer complete (empty dir), anything other than 125/150 = treat as empty
        // (Fritz!Box sometimes returns 450/451 for an empty directory instead of 226)
        if !reply.hasPrefix("125") && !reply.hasPrefix("150") { dataTask.cancel(); return [] }

        let data = try await readAll(from: dataTask)
        _ = try? await readResponse(from: controlTask)
        let listing = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return listing.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased().hasSuffix(".txt") }
    }

    private func fetchEvent(filename: String) async throws -> CalendarEvent {
        guard let controlTask, let urlSession else { throw CalendarFTPSError.notConnected }
        try await send("TYPE I\r\n", to: controlTask); _ = try await readResponse(from: controlTask)

        var dataTask = try await openDataChannel(controlTask: controlTask, session: urlSession)
        try await send("RETR \(filename)\r\n", to: controlTask)
        var reply = try await readResponse(from: controlTask)

        if reply.hasPrefix("425") {
            dataTask.cancel()
            try await upgradeToProtP(controlTask: controlTask)
            dataTask = try await openDataChannel(controlTask: controlTask, session: urlSession)
            try await send("RETR \(filename)\r\n", to: controlTask)
            reply = try await readResponse(from: controlTask)
        }
        guard reply.hasPrefix("125") || reply.hasPrefix("150") else { dataTask.cancel(); throw CalendarFTPSError.downloadFailed }

        let data = try await readAll(from: dataTask)
        _ = try? await readResponse(from: controlTask)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let event = CalendarEvent.decode(text, filename: filename) else {
            throw CalendarFTPSError.downloadFailed
        }
        return event
    }

    private func storeFile(filename: String, data: Data) async throws {
        guard let controlTask, let urlSession else { throw CalendarFTPSError.notConnected }
        try await send("TYPE I\r\n", to: controlTask); _ = try await readResponse(from: controlTask)

        var dataTask = try await openDataChannel(controlTask: controlTask, session: urlSession)
        try await send("STOR \(filename)\r\n", to: controlTask)
        var storResp = try await readResponse(from: controlTask)

        if storResp.hasPrefix("425") {
            dataTask.cancel()
            try await upgradeToProtP(controlTask: controlTask)
            dataTask = try await openDataChannel(controlTask: controlTask, session: urlSession)
            try await send("STOR \(filename)\r\n", to: controlTask)
            storResp = try await readResponse(from: controlTask)
        }
        guard storResp.hasPrefix("125") || storResp.hasPrefix("150") else { dataTask.cancel(); throw CalendarFTPSError.uploadFailed("STOR abgelehnt: \(storResp)") }

        try await writeData(data, to: dataTask)
        dataTask.closeWrite()
        _ = try? await readResponse(from: controlTask)
    }

    private func upgradeToProtP(controlTask: URLSessionStreamTask) async throws {
        encryptDataChannel = true
        try await send("PROT P\r\n", to: controlTask); _ = try await readResponse(from: controlTask)
    }

    private func openDataChannel(controlTask: URLSessionStreamTask, session: URLSession) async throws -> URLSessionStreamTask {
        try await send("PASV\r\n", to: controlTask)
        let pasvResp = try await readResponse(from: controlTask)
        guard pasvResp.hasPrefix("227") else { throw CalendarFTPSError.connectionFailed("PASV fehlgeschlagen: \(pasvResp)") }
        let (_, port) = try parsePASV(pasvResp)
        ftpDelegate?.dataChannelMode = encryptDataChannel
        let dataTask = session.streamTask(withHostName: settings.host, port: port)
        dataTask.resume()
        if encryptDataChannel { dataTask.startSecureConnection() }
        return dataTask
    }

    // MARK: - Low-level I/O

    private func send(_ cmd: String, to task: URLSessionStreamTask) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.write(Data(cmd.utf8), timeout: commandTimeout) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private func writeData(_ data: Data, to task: URLSessionStreamTask) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.write(data, timeout: dataTimeout) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private func readResponse(from task: URLSessionStreamTask) async throws -> String {
        while true {
            let line = try await readLine(from: task)
            guard line.count >= 4 else { continue }
            if line[line.index(line.startIndex, offsetBy: 3)] == " " { return line }
        }
    }

    private func readLine(from task: URLSessionStreamTask) async throws -> String {
        while true {
            if let range = readBuffer.range(of: Data("\r\n".utf8)) {
                let line = String(data: readBuffer[..<range.lowerBound], encoding: .utf8) ?? ""
                readBuffer.removeSubrange(..<range.upperBound); return line
            }
            if let range = readBuffer.range(of: Data("\n".utf8)) {
                var line = String(data: readBuffer[..<range.lowerBound], encoding: .utf8) ?? ""
                if line.hasSuffix("\r") { line.removeLast() }
                readBuffer.removeSubrange(..<range.upperBound); return line
            }
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                task.readData(ofMinLength: 1, maxLength: 4096, timeout: readTimeout) { data, _, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume(returning: data ?? Data()) }
                }
            }
            readBuffer.append(chunk)
        }
    }

    private func readAll(from task: URLSessionStreamTask) async throws -> Data {
        var result = Data()
        while true {
            let (chunk, eof): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                task.readData(ofMinLength: 1, maxLength: 65536, timeout: dataTimeout) { data, atEOF, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume(returning: (data, atEOF)) }
                }
            }
            if let chunk { result.append(chunk) }
            if eof { break }
        }
        return result
    }

    private func parsePASV(_ response: String) throws -> (String, Int) {
        guard let open = response.firstIndex(of: "("), let close = response.firstIndex(of: ")") else {
            throw CalendarFTPSError.invalidResponse("PASV-Format ungültig")
        }
        let inner = String(response[response.index(after: open)..<close])
        let parts = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 6 else { throw CalendarFTPSError.invalidResponse("PASV-Parameter ungültig") }
        return ("\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])", parts[4] * 256 + parts[5])
    }
}
