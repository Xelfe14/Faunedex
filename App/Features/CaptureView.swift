import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import FlaunedexCore

/// The capture screen: a live camera, a shutter that grabs the frame **and** the
/// GPS fix, queues the sighting, and kicks off identification. Fully usable
/// offline — the network work is deferred to the scan queue.
struct CaptureView: View {
    @Environment(ScanCoordinator.self) private var scan
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity
    @Query private var sightings: [Sighting]

    @State private var camera = CameraModel()
    @State private var location = LocationProvider()
    @State private var isCapturing = false
    @State private var toast: String?
    @State private var flash = false

    private var pendingCount: Int {
        sightings.filter { $0.status != .complete && $0.status != .needsReview }.count
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()

            // Shutter flash.
            if flash { Color.white.ignoresSafeArea().transition(.opacity) }

            VStack(spacing: 10) {
                banners
                Spacer()
                if let toast { toastView(toast) }
                shutterRow
            }
            .padding()
        }
        .task {
            _ = await camera.requestAccess()
            location.requestAuthorization()
            camera.configure()
            camera.start()
            await scan.processQueue()
        }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if !keys.hasGeminiKey {
                banner("Ajoutez votre clé Gemini dans Réglages pour identifier vos photos.",
                       systemImage: "key.fill", tint: .orange)
            }
            if !connectivity.isOnline {
                banner("Hors ligne — vos photos seront identifiées au retour du réseau.",
                       systemImage: "wifi.slash", tint: .white)
            }
            if pendingCount > 0 {
                banner("\(pendingCount) photo\(pendingCount > 1 ? "s" : "") en attente d'identification",
                       systemImage: "clock.arrow.circlepath", tint: .white)
            }
        }
    }

    private func banner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, 6)
    }

    private var shutterRow: some View {
        Button {
            Task { await capture() }
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.9), lineWidth: 4).frame(width: 82, height: 82)
                Circle().fill(.white).frame(width: 66, height: 66)
                    .scaleEffect(isCapturing ? 0.86 : 1)
                if isCapturing { ProgressView().tint(.black) }
            }
        }
        .disabled(isCapturing)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturing)
        .padding(.bottom, 18)
    }

    private func capture() async {
        isCapturing = true
        defer { isCapturing = false }

        let fix = await location.currentLocation()
        do {
            let data = try await camera.capture(location: fix)
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeIn(duration: 0.22).delay(0.08)) { flash = false }

            _ = try scan.enqueueCapture(
                imageData: data,
                latitude: fix?.coordinate.latitude ?? 0,
                longitude: fix?.coordinate.longitude ?? 0,
                accuracy: fix?.horizontalAccuracy ?? -1
            )
            show(connectivity.isOnline ? "Photo enregistrée — identification en cours…"
                                       : "Photo enregistrée — en file d'attente.")
            if connectivity.isOnline { await scan.processQueue() }
        } catch {
            show("Échec de la capture.")
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation { toast = nil }
        }
    }
}

/// Wraps `AVCaptureVideoPreviewLayer` for SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
