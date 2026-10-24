import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import FlaunedexCore

/// The capture screen: a live camera, a shutter that grabs the frame **and** the
/// GPS fix, queues the sighting, and kicks off identification. Fully usable
/// offline — the network work is deferred to the scan queue.
///
/// The shutter never waits: the GPS is warmed up while the camera is open, and
/// a position that arrives after the photo is attached to it then. Once the
/// photo is saved, `onCaptured` takes the user back where they came from, and
/// the status pill follows the identification from there.
struct CaptureView: View {
    /// Whether this screen is really the one in front of the user: its tab is
    /// selected and its app is on screen. Decided by the tab bar rather than by
    /// appearance, because a tab view may build this screen, and run its tasks,
    /// before it is ever shown; the camera must not run then.
    var isVisible = true
    /// Called once a photo is safely queued.
    var onCaptured: () -> Void = {}

    @Environment(ScanCoordinator.self) private var scan
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity
    @Environment(\.openURL) private var openURL
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
            // Kept clear of the tab bar, which stays readable on top of a
            // live picture instead of fading into it.
            CameraPreview(session: camera.session)

            // Shutter flash.
            if flash { Color.white.transition(.opacity) }

            VStack(spacing: 10) {
                banners
                Spacer()
                if let toast { toastView(toast) }
                positionIndicator
                shutterRow
            }
            .padding()
        }
        .background(Color.black)
        .toolbarBackground(.visible, for: .tabBar)
        // Runs again whenever the screen is shown or hidden, including when
        // Cuisine or Savoirs is opened on top of it.
        .task(id: isVisible) {
            guard isVisible else {
                camera.stop()
                location.stopWarmingUp()
                return
            }
            _ = await camera.requestAccess()
            location.startWarmingUp()
            camera.configure()
            camera.start()
            // Not tied to this screen: leaving it must not cancel an
            // identification half way through.
            Task { await scan.processQueue() }
        }
        .onDisappear {
            camera.stop()
            location.stopWarmingUp()
        }
    }

    /// Whether the photo will land on the map.
    @ViewBuilder private var positionIndicator: some View {
        if !location.isDenied {
            Group {
                if location.hasFix {
                    Label("Position trouvée", systemImage: "location.fill")
                } else {
                    Label("Recherche de la position…", systemImage: "location")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if !keys.hasGeminiKey {
                banner("Ajoutez votre clé Gemini dans Réglages (la roue dentée en haut à droite) pour identifier vos photos.",
                       systemImage: "key.fill", tint: .orange)
            }
            if location.isDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    banner("Localisation refusée : vos photos ne seront pas placées sur la carte. Touchez pour l'autoriser.",
                           systemImage: "location.slash.fill", tint: .orange)
                }
                .buttonStyle(.plain)
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

        let fix = location.recentFix()
        do {
            let data = try await camera.capture(location: fix)
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeIn(duration: 0.22).delay(0.08)) { flash = false }

            let sighting = try scan.enqueueCapture(
                imageData: data,
                latitude: fix?.coordinate.latitude ?? 0,
                longitude: fix?.coordinate.longitude ?? 0,
                accuracy: fix?.horizontalAccuracy ?? -1
            )
            if fix == nil && !location.isDenied {
                attachLateFix(to: sighting)
            }
            onCaptured()
            if connectivity.isOnline { await scan.processQueue() }
        } catch {
            show("Échec de la capture.")
        }
    }

    /// The GPS hadn't found the position yet when the photo was taken: keep
    /// listening, and place the sighting when it does.
    private func attachLateFix(to sighting: Sighting) {
        let provider = location
        Task {
            guard let late = await provider.waitForFix() else { return }
            await scan.setLocation(latitude: late.coordinate.latitude,
                                   longitude: late.coordinate.longitude,
                                   accuracy: late.horizontalAccuracy,
                                   for: sighting)
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
