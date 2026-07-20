import Foundation

struct PulseSnapshot: Codable {
    let generatedAt: Date
    let score: Int
    let host: HostMetrics
    let services: [ServiceHealth]
    let incidents: [Incident]

    static let demo = PulseSnapshot(
        generatedAt: .now,
        score: 96,
        host: HostMetrics(cpuPercent: 18, memoryPercent: 42, diskPercent: 63, uptimeSeconds: 3_283_200),
        services: [
            ServiceHealth(id: "mission-control", name: "Mission Control", status: .healthy, latencyMs: 72, detail: "Orders and production systems are current"),
            ServiceHealth(id: "cortex", name: "Cortex", status: .healthy, latencyMs: 108, detail: "Calendar and capture APIs responding"),
            ServiceHealth(id: "etsy-connector", name: "Etsy Connector", status: .degraded, latencyMs: 391, detail: "3 restarts detected in the last hour"),
            ServiceHealth(id: "hydroponics", name: "Hydroponics", status: .healthy, latencyMs: 31, detail: "Telemetry received 24 seconds ago"),
            ServiceHealth(id: "minecraft", name: "Minecraft", status: .maintenance, latencyMs: nil, detail: "Intentionally stopped")
        ],
        incidents: [
            Incident(id: UUID(), occurredAt: .now.addingTimeInterval(-240), severity: .warning, title: "Etsy Connector restarted", detail: "Health check recovered after container restart"),
            Incident(id: UUID(), occurredAt: .now.addingTimeInterval(-5_400), severity: .info, title: "Mission Control deployed", detail: "Production updated successfully")
        ]
    )
}

struct HostMetrics: Codable {
    let cpuPercent: Double
    let memoryPercent: Double
    let diskPercent: Double
    let uptimeSeconds: TimeInterval
}

struct ServiceHealth: Codable, Identifiable {
    enum Status: String, Codable { case healthy, degraded, offline, maintenance, unknown }
    let id: String
    let name: String
    let status: Status
    let latencyMs: Int?
    let detail: String
}

struct Incident: Codable, Identifiable {
    enum Severity: String, Codable { case info, warning, critical }
    let id: UUID
    let occurredAt: Date
    let severity: Severity
    let title: String
    let detail: String
}

@MainActor
final class PulseStore: ObservableObject {
    @Published var snapshot: PulseSnapshot = .demo
    @Published var isRefreshing = false
    @Published var connectionMessage = "Demo telemetry"

    private let api = PulseAPI()

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await api.fetchSnapshot()
            connectionMessage = "Live · updated now"
        } catch {
            connectionMessage = "Demo mode · live agent unavailable"
        }
    }
}

struct PulseAPI {
    private var baseURL: URL? {
        guard let value = UserDefaults.standard.string(forKey: "pulse.agentURL") else { return nil }
        return URL(string: value)
    }

    func fetchSnapshot() async throws -> PulseSnapshot {
        guard let baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: baseURL.appending(path: "api/v1/snapshot"))
        request.timeoutInterval = 10
        if let token = UserDefaults.standard.string(forKey: "pulse.token"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PulseSnapshot.self, from: data)
    }
}
