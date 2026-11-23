#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import UIKit

/// Tombol SOS SwiftUI siap pakai: tahan N detik (default dari portal), cincin progres, getar, teks status.
///
/// ```swift
/// SOSButton(client: sos, category: "kriminal") { result in ... }
/// ```
@available(iOS 15.0, *)
public struct SOSButton: View {
    let client: SiagaSOS
    let category: String
    let message: String?
    let color: Color
    let onResult: ((Result<ActiveReport, SiagaSOSError>) -> Void)?

    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var sending = false
    @State private var report: ActiveReport?
    @State private var config: SdkConfig?
    @State private var listenerId: UUID?

    public init(client: SiagaSOS, category: String = "general", message: String? = nil, color: Color = Color(red: 0.86, green: 0.15, blue: 0.15),
                onResult: ((Result<ActiveReport, SiagaSOSError>) -> Void)? = nil) {
        self.client = client; self.category = category; self.message = message; self.color = color; self.onResult = onResult
    }

    private var holdSeconds: Double { Double(config?.holdSeconds ?? 3) }
    private var active: Bool { report.map { !$0.status.isTerminal } ?? false }

    private var statusText: String {
        if sending { return "Mengirim…" }
        guard let r = report else { return "Tahan \(Int(holdSeconds)) detik" }
        if let m = r.statusMessage { return m }
        switch r.status {
        case .queued: return "Menunggu sinyal…"
        case .open: return "Terkirim. Menunggu petugas…"
        case .acknowledged: return "Petugas menerima laporan"
        case .inProgress: return "Petugas menangani"
        case .resolved: return "Selesai"
        case .cancelled: return "Dibatalkan"
        case .falseAlarm: return "Alarm palsu"
        }
    }

    public var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                Circle().fill(active ? Color.gray : color).padding(22).shadow(color: color.opacity(0.45), radius: 16)
                if sending { ProgressView().tint(.white) } else {
                    Text(active ? statusText : (config?.buttonText ?? "SOS"))
                        .font(active ? .subheadline.bold() : .system(size: 34, weight: .heavy)).foregroundColor(.white).multilineTextAlignment(.center).padding(36)
                }
            }
            .frame(width: 190, height: 190)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in start() }.onEnded { _ in release() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tombol darurat. Tahan \(Int(holdSeconds)) detik untuk mengirim laporan SOS.")
            .accessibilityValue(statusText)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { fire() }

            if !active { Text(statusText).font(.callout).foregroundColor(.secondary) }
            if client.mode == .test { Text("MODE TEST").font(.caption2.bold()).foregroundColor(.orange) }
            if report?.status == .open, let r = report {
                Button("Batalkan (salah tekan)") { Task { _ = try? await client.cancel(r.localId, reason: "Salah tekan") } }.font(.callout)
            }
            if let t = config?.recipientText, !t.isEmpty { Text(t).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center) }
        }
        .task {
            config = try? await client.getConfig()
            listenerId = client.addListener(SosListener(onStatus: { r in if report == nil || report?.localId == r.localId { report = r } }))
        }
        .onDisappear { if let id = listenerId { client.removeListener(id) } }
    }

    private func start() {
        guard !holding, !active, !sending else { return }
        holding = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.linear(duration: holdSeconds)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) { if holding { fire() } }
    }

    private func release() {
        holding = false
        if !sending { withAnimation(.easeOut(duration: 0.2)) { progress = 0 } }
    }

    private func fire() {
        guard !sending else { return }
        holding = false
        sending = true
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        Task {
            do {
                let r = try await client.trigger(category: category, message: message)
                report = r
                onResult?(.success(r))
            } catch let e as SiagaSOSError {
                onResult?(.failure(e))
            } catch {}
            sending = false
            progress = 0
        }
    }
}
#endif
