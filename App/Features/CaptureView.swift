import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import UIKit
import FlaunedexCore

/// The capture screen: a live camera, a shutter that grabs the frame **and** the
/// GPS fix, queues the sighting, and kicks off identification. Fully usable
/// offline — the network work is deferred to the scan queue.
///
/// The shutter never waits: the GPS is warmed up while the camera is open, and
/// a position that arrives after the photo is attached to it then. Once the
/// photo is saved, `onCaptured` hands it over: the tab bar goes back where the
/// user came from and opens its analysis on top.
///
/// The camera zooms with a pinch or the lens buttons, and a photo can come from
/// the library instead, with the place and date it was taken.
struct CaptureView: View {
    /// Whether this screen is really the one in front of the user: its tab is
    /// selected and its app is on screen. Decided by the tab bar rather than by
    /// appearance, because a tab view may build this screen, and run its tasks,
    /// before it is ever shown; the camera must not run then.
    var isVisible = true
    /// Called with the sighting once the photo is safely queued.
    var onCaptured: (Sighting) -> Void = { _ in }

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

    /// How the camera zooms; nil until it is set up, and without a camera.
    @State private var zoom: CameraZoom?
    /// The device factor the camera is at.
    @State private var zoomFactor: Double = 1
    /// The factor when the current pinch began.
    @State private var pinchStart: Double?

    @State private var libraryItem: PhotosPickerItem?
    @State private var isImporting = false

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
                if let zoom { zoomButtons(zoom) }
                shutterRow
            }
            .padding()
        }
        .background(Color.black)
        .toolbarBackground(.visible, for: .tabBar)
        .simultaneousGesture(pinchToZoom)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task { await importFromLibrary(item) }
        }
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
            if let state = await camera.configure() {
                zoom = state.zoom
                zoomFactor = state.factor
            }
            #if DEBUG
            // The simulator has no camera: show the buttons of a three-lens one.
            if zoom == nil, CommandLine.arguments.contains("capture") {
                zoom = CameraZoom(minFactor: 1, maxFactor: 123, switchOverFactors: [2, 10], hasUltraWide: true)
                zoomFactor = 2
            }
            #endif
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

    // MARK: Zoom

    /// One button per lens, as in the Camera app: the one in use shows the
    /// exact zoom ("1,4×").
    private func zoomButtons(_ zoom: CameraZoom) -> some View {
        let shown = zoom.displayed(zoomFactor)
        let active = zoom.activePreset(for: shown)
        return HStack(spacing: 6) {
            ForEach(zoom.presets, id: \.self) { preset in
                let isActive = preset == active
                Button {
                    setZoom(zoom.factor(forDisplayed: preset), animated: true)
                } label: {
                    Text(isActive ? CameraZoom.label(shown) + "×" : CameraZoom.label(preset))
                        .font(.system(size: isActive ? 13 : 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(isActive ? .yellow : .white)
                        .frame(width: isActive ? 40 : 32, height: isActive ? 40 : 32)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom \(CameraZoom.label(preset))×")
            }
        }
        .padding(4)
        .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: active)
    }

    private var pinchToZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let zoom else { return }
                let start = pinchStart ?? zoomFactor
                pinchStart = start
                setZoom(start * Double(value.magnification), animated: false)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// `animated` for a lens button, which glides there with a tick; a pinch
    /// follows the fingers.
    private func setZoom(_ factor: Double, animated: Bool) {
        guard let zoom else { return }
        let factor = min(max(factor, zoom.minFactor), zoom.maxFactor)
        if animated { UISelectionFeedbackGenerator().selectionChanged() }
        zoomFactor = factor
        camera.setZoom(factor, animated: animated)
    }

    // MARK: Shutter

    private var shutterRow: some View {
        HStack {
            libraryButton
            Spacer()
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
            .disabled(isCapturing || isImporting)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCapturing)
            Spacer()
            // Balances the library button, so the shutter stays centred.
            Color.clear.frame(width: 52, height: 52)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 18)
    }

    /// Opens the photo library. Its photos need no permission: the system
    /// picker hands over only the one chosen.
    private var libraryButton: some View {
        PhotosPicker(selection: $libraryItem, matching: .images, preferredItemEncoding: .current) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                if isImporting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 52, height: 52)
        }
        .disabled(isCapturing || isImporting)
        .accessibilityLabel("Choisir une photo dans la bibliothèque")
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
            onCaptured(sighting)
            if connectivity.isOnline { await scan.processQueue() }
        } catch {
            show("Échec de la capture.")
        }
    }

    /// Bring in a photo from the library and send it through the same queue as
    /// a capture. It keeps the place and date it was taken, read from the
    /// photo; one with no place goes to "Photos sans position", to be placed
    /// on the map. The current position is never used: the photo may be from
    /// anywhere.
    private func importFromLibrary(_ item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let photo = await Task.detached(priority: .userInitiated, operation: { LibraryPhoto(data) }).value
            else {
                show("Cette image n'a pas pu être lue.")
                return
            }
            let sighting = try scan.enqueueCapture(
                imageData: photo.jpeg,
                latitude: photo.latitude ?? 0,
                longitude: photo.longitude ?? 0,
                accuracy: photo.horizontalAccuracy ?? -1,
                capturedAt: photo.takenAt ?? .now
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCaptured(sighting)
            if connectivity.isOnline { await scan.processQueue() }
        } catch {
            show("Import impossible.")
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
