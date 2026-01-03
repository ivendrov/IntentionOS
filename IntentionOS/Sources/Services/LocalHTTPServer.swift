import Foundation
import Network

/// Local HTTP server for Chrome extension communication
/// Listens on localhost:9999
class LocalHTTPServer {
    static let shared = LocalHTTPServer()

    private var listener: NWListener?
    private let port: UInt16 = 9999
    private let queue = DispatchQueue(label: "com.intention-os.http-server")

    private init() {}

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("HTTP server listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    print("HTTP server failed: \(error)")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            print("Failed to start HTTP server: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let error = error {
                print("Connection error: \(error)")
                connection.cancel()
                return
            }

            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            self?.handleRequest(request, connection: connection)
        }
    }

    private func handleRequest(_ request: String, connection: NWConnection) {
        // Parse HTTP request
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request line"])
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Parse body for POST requests
        var body: [String: Any]?
        if method == "POST", let bodyStart = request.range(of: "\r\n\r\n") {
            let bodyString = String(request[bodyStart.upperBound...])
            if let bodyData = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                body = json
            }
        }

        // Route handling
        switch (method, path) {
        case ("GET", "/status"):
            handleStatus(connection: connection)

        case ("GET", "/intention"):
            handleGetIntention(connection: connection)

        case ("POST", "/check-url"):
            handleCheckURL(connection: connection, body: body)

        case ("POST", "/override"):
            handleOverride(connection: connection, body: body)

        case ("POST", "/end-intention"):
            handleEndIntention(connection: connection)

        case ("OPTIONS", _):
            // CORS preflight
            sendCORSResponse(connection: connection)

        default:
            sendResponse(connection: connection, status: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Endpoints

    private func handleStatus(connection: NWConnection) {
        sendResponse(connection: connection, status: 200, body: [
            "status": "ok",
            "version": "1.0.0"
        ])
    }

    private func handleGetIntention(connection: NWConnection) {
        if let intention = IntentionManager.shared.currentIntention {
            sendResponse(connection: connection, status: 200, body: [
                "active": true,
                "text": intention.text,
                "remaining": intention.remainingFormatted ?? "unlimited",
                "llmFilteringEnabled": intention.llmFilteringEnabled
            ])
        } else {
            sendResponse(connection: connection, status: 200, body: [
                "active": false
            ])
        }
    }

    private func handleCheckURL(connection: NWConnection, body: [String: Any]?) {
        guard let url = body?["url"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing url"])
            return
        }

        let result = IntentionManager.shared.isURLAllowed(url: url)

        sendResponse(connection: connection, status: 200, body: [
            "allowed": result.allowed,
            "reason": result.reason?.rawValue ?? "blocked",
            "message": result.message ?? ""
        ])
    }

    private func handleEndIntention(connection: NWConnection) {
        // End the current intention
        if IntentionManager.shared.currentIntention != nil {
            IntentionManager.shared.endIntention(reason: .newIntention)
        }

        // Show the intention prompt on the main thread
        DispatchQueue.main.async {
            if let appDelegate = AppDelegate.shared {
                appDelegate.showIntentionPrompt()
            }
        }

        sendResponse(connection: connection, status: 200, body: ["success": true])
    }

    private func handleOverride(connection: NWConnection, body: [String: Any]?) {
        guard let url = body?["url"] as? String,
              let phrase = body?["phrase"] as? String else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing url or phrase"])
            return
        }

        let correctPhrase = ConfigManager.shared.appConfig.breakGlassPhrase

        if phrase == correctPhrase {
            // Log the override
            if let intention = IntentionManager.shared.currentIntention {
                DatabaseManager.shared.logAccess(
                    intentionId: intention.id,
                    type: .url,
                    identifier: url,
                    wasAllowed: true,
                    allowedReason: .override,
                    wasOverride: true
                )

                // Check if should learn
                if let shouldLearn = body?["learn"] as? Bool, shouldLearn {
                    let pattern = extractPattern(from: intention.text)
                    DatabaseManager.shared.addLearnedRule(
                        intentionPattern: pattern,
                        type: .url,
                        identifier: extractDomain(from: url),
                        allowed: true
                    )
                }
            }

            sendResponse(connection: connection, status: 200, body: ["success": true])
        } else {
            sendResponse(connection: connection, status: 403, body: ["success": false, "error": "Incorrect phrase"])
        }
    }

    // MARK: - Helpers

    private func sendResponse(connection: NWConnection, status: Int, body: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let statusText = status == 200 ? "OK" : (status == 400 ? "Bad Request" : (status == 403 ? "Forbidden" : "Not Found"))

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        \(jsonString)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendCORSResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func extractPattern(from intentionText: String) -> String {
        let words = intentionText.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        return words.joined(separator: "|")
    }

    private func extractDomain(from url: String) -> String {
        var normalized = url
        if normalized.hasPrefix("https://") {
            normalized = String(normalized.dropFirst(8))
        } else if normalized.hasPrefix("http://") {
            normalized = String(normalized.dropFirst(7))
        }
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }
        if let slashIndex = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIndex])
        }
        return normalized
    }
}
