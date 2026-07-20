import SwiftUI
import Charts

struct RootView: View {
    @EnvironmentObject private var store: PulseStore

    var body: some View {
        TabView {
            CommandCenterView()
                .tabItem { Label("Pulse", systemImage: "waveform.path.ecg") }

            SystemsView()
                .tabItem { Label("Systems", systemImage: "server.rack") }

            TopologyView()
                .tabItem { Label("Map", systemImage: "point.3.connected.trianglepath.dotted") }

            ChaosLabView()
                .tabItem { Label("Chaos", systemImage: "flask.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.cyan)
    }
}

struct SystemsView: View {
    @EnvironmentObject private var store: PulseStore

    var body: some View {
        NavigationStack {
            List {
                Section("Host") {
                    NavigationLink {
                        HostDetailView(metrics: store.snapshot.host)
                    } label: {
                        Label("Ubuntu Server", systemImage: "server.rack")
                    }
                }

                Section("Services") {
                    ForEach(store.snapshot.services) { service in
                        NavigationLink {
                            ServiceDetailView(service: service)
                        } label: {
                            HStack {
                                Circle().fill(service.status.color).frame(width: 10, height: 10)
                                VStack(alignment: .leading) {
                                    Text(service.name)
                                    Text(service.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if let latency = service.latencyMs { Text("\(latency) ms").font(.caption.monospacedDigit()) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Systems")
        }
    }
}

struct HostDetailView: View {
    let metrics: HostMetrics
    private var samples: [(String, Double)] { [("CPU", metrics.cpuPercent), ("Memory", metrics.memoryPercent), ("Disk", metrics.diskPercent)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Chart(samples, id: \.0) { item in
                    BarMark(x: .value("Resource", item.0), y: .value("Percent", item.1))
                        .cornerRadius(8)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 260)

                Text("Uptime")
                    .font(.headline)
                Text(Duration.seconds(metrics.uptimeSeconds).formatted(.time(pattern: .dayHourMinute)))
                    .font(.title2.monospacedDigit())
            }
            .padding()
        }
        .navigationTitle("Ubuntu Server")
    }
}

struct ServiceDetailView: View {
    let service: ServiceHealth
    private var history: [Int] {
        let base = service.latencyMs ?? 0
        return [base + 18, base + 6, base + 30, base + 4, base + 12, base]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Circle().fill(service.status.color).frame(width: 16, height: 16)
                    Text(service.status.rawValue.capitalized).font(.title2.bold())
                }
                Text(service.detail).foregroundStyle(.secondary)

                if service.latencyMs != nil {
                    Text("Recent latency").font(.headline)
                    Chart(Array(history.enumerated()), id: \.offset) { point in
                        LineMark(x: .value("Check", point.offset), y: .value("Latency", point.element))
                        AreaMark(x: .value("Check", point.offset), y: .value("Latency", point.element)).opacity(0.15)
                    }
                    .frame(height: 220)
                }
            }
            .padding()
        }
        .navigationTitle(service.name)
    }
}

struct TopologyView: View {
    @EnvironmentObject private var store: PulseStore

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(store.snapshot.services.enumerated()), id: \.element.id) { index, service in
                        Path { path in
                            path.move(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2))
                            let angle = Double(index) / Double(max(store.snapshot.services.count, 1)) * .pi * 2
                            path.addLine(to: CGPoint(x: proxy.size.width / 2 + cos(angle) * 130, y: proxy.size.height / 2 + sin(angle) * 190))
                        }
                        .stroke(service.status.color.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }

                    Circle().fill(.cyan.gradient).frame(width: 110, height: 110)
                        .overlay(VStack { Image(systemName: "server.rack"); Text("Pulse Core").font(.caption.bold()) })
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    ForEach(Array(store.snapshot.services.enumerated()), id: \.element.id) { index, service in
                        let angle = Double(index) / Double(max(store.snapshot.services.count, 1)) * .pi * 2
                        VStack(spacing: 4) {
                            Circle().fill(service.status.color).frame(width: 52, height: 52).overlay(Image(systemName: "shippingbox.fill"))
                            Text(service.name).font(.caption2.bold()).frame(width: 90).multilineTextAlignment(.center)
                        }
                        .position(x: proxy.size.width / 2 + cos(angle) * 130, y: proxy.size.height / 2 + sin(angle) * 190)
                    }
                }
            }
            .navigationTitle("Infrastructure Map")
        }
    }
}

struct ChaosLabView: View {
    @EnvironmentObject private var store: PulseStore
    @State private var simulated = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Simulation only", systemImage: "shield.checkered")
                    Text("Chaos Lab never touches Docker or production. It lets us test incident UI, haptics, and recovery flows safely.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Scenarios") {
                    Button("Simulate Etsy Connector outage") {
                        store.simulateIncident(serviceID: "etsy-connector")
                        simulated = true
                    }
                    Button("Restore demo telemetry") {
                        store.restoreDemo()
                        simulated = false
                    }
                }
                if simulated { Section { Label("Incident simulation active", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
            }
            .navigationTitle("Chaos Lab")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: PulseStore
    @State private var agentURL = UserDefaults.standard.string(forKey: "pulse.agentURL") ?? ""
    @State private var token = KeychainStore.read("pulse.agentToken") ?? ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Pulse Agent") {
                    TextField("https://example.com/pulse/", text: $agentURL)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                    SecureField("Bearer token", text: $token)
                    Button("Save and test") {
                        UserDefaults.standard.set(agentURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "pulse.agentURL")
                        KeychainStore.save(token, key: "pulse.agentToken")
                        saved = true
                        Task { await store.refresh() }
                    }
                }
                Section("Connection") {
                    LabeledContent("Status", value: store.connectionMessage)
                    if saved { Label("Settings saved securely", systemImage: "checkmark.shield.fill").foregroundStyle(.green) }
                }
                Section("Build") {
                    LabeledContent("Version", value: "0.2.0")
                    LabeledContent("Delivery", value: "GitHub Runner")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

extension ServiceHealth.Status {
    var color: Color {
        switch self {
        case .healthy: .green
        case .degraded: .orange
        case .offline: .red
        case .maintenance: .blue
        case .unknown: .gray
        }
    }
}
