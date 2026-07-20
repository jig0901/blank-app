import SwiftUI

struct CommandCenterView: View {
    @EnvironmentObject private var store: PulseStore
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    metrics
                    services
                    incidents
                }
                .padding()
            }
            .background(background)
            .navigationTitle("Pulse")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                            .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                    }
                }
            }
            .task {
                pulse = true
                await store.refresh()
            }
        }
        .tint(.cyan)
    }

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [.cyan.opacity(0.16), .clear], center: .top, startRadius: 20, endRadius: 430)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(.cyan.opacity(0.18), lineWidth: 16)
                    .frame(width: 190, height: 190)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                    .opacity(pulse ? 0.15 : 0.6)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

                Circle()
                    .trim(from: 0, to: Double(store.snapshot.score) / 100)
                    .stroke(.cyan.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 160, height: 160)

                VStack(spacing: 0) {
                    Text("\(store.snapshot.score)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                    Text("SYSTEM HEALTH")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Text(store.snapshot.score > 89 ? "Infrastructure is humming" : "Pulse needs attention")
                .font(.title3.bold())
            Text(store.connectionMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassCard()
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricTile(title: "CPU", value: store.snapshot.host.cpuPercent)
            MetricTile(title: "RAM", value: store.snapshot.host.memoryPercent)
            MetricTile(title: "DISK", value: store.snapshot.host.diskPercent)
        }
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("SYSTEMS", icon: "server.rack")
            ForEach(store.snapshot.services) { service in
                HStack(spacing: 12) {
                    Circle()
                        .fill(color(for: service.status))
                        .frame(width: 10, height: 10)
                        .shadow(color: color(for: service.status), radius: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name).font(.headline)
                        Text(service.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if let latency = service.latencyMs {
                        Text("\(latency) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text(service.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding()
        .glassCard()
    }

    private var incidents: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("ACTIVITY", icon: "waveform.path.ecg")
            ForEach(store.snapshot.incidents) { incident in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: incident.severity == .critical ? "exclamationmark.triangle.fill" : incident.severity == .warning ? "bolt.trianglebadge.exclamationmark.fill" : "checkmark.circle.fill")
                        .foregroundStyle(incident.severity == .critical ? .red : incident.severity == .warning ? .orange : .green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(incident.title).font(.subheadline.bold())
                        Text(incident.detail).font(.caption).foregroundStyle(.secondary)
                        Text(incident.occurredAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .glassCard()
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(.cyan)
    }

    private func color(for status: ServiceHealth.Status) -> Color {
        switch status {
        case .healthy: .green
        case .degraded: .orange
        case .offline: .red
        case .maintenance: .blue
        case .unknown: .gray
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            Text("\(Int(value))%")
                .font(.title2.bold().monospacedDigit())
            ProgressView(value: value, total: 100)
                .tint(value > 85 ? .orange : .cyan)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassCard()
    }
}

private extension View {
    func glassCard() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.08)))
    }
}
