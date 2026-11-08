import Foundation
@preconcurrency import AVFoundation
import CoreLocation
import UIKit
import FlaunedexCore

/// A minimal custom camera. AVFoundation is required (not `PhotosPicker`)
/// because only owning the capture callback lets us pair the exact frame with
/// the exact GPS fix, and AVFoundation does **not** embed EXIF GPS on its own,
/// so we inject it before writing the JPEG.
///
/// Concurrency: three different execution contexts touch this object. The views
/// call it from the main actor, configuration and start/stop run on
/// `sessionQueue`, and `AVCapturePhotoOutput` delivers its delegate callback on
/// a queue of its own choosing. The mutable state is therefore split
/// deliberately: `isConfigured` and `device` are only ever read or written on `sessionQueue`,
/// and the pending continuation plus its location are guarded by `lock`. That
/// discipline is what `@unchecked Sendable` is asserting here.
final class CameraModel: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.taddeocarpinelli.flaunedex.camera")

    /// Guards `captureContinuation` and `pendingLocation`, which are written on
    /// the main actor and read on AVFoundation's delivery queue.
    private let lock = NSLock()
    private var captureContinuation: CheckedContinuation<Data, Error>?
    private var pendingLocation: CLLocation?

    /// Only touched on `sessionQueue`.
    private var isConfigured = false
    private var device: AVCaptureDevice?

    var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    enum CameraError: Error { case notAuthorized, configurationFailed, captureFailed }

    /// The zoom the camera offers, and where it is now.
    struct ZoomState: Sendable {
        let zoom: CameraZoom
        let factor: Double
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Set the session up once, and say how it can zoom. Nil without a camera
    /// (the simulator) or before access is granted.
    func configure() async -> ZoomState? {
        await withCheckedContinuation { (cont: CheckedContinuation<ZoomState?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { return cont.resume(returning: nil) }
                if !self.isConfigured { self.setUp() }
                cont.resume(returning: self.device.map {
                    ZoomState(zoom: Self.zoom(of: $0), factor: Double($0.videoZoomFactor))
                })
            }
        }
    }

    /// On `sessionQueue`.
    private func setUp() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        // The multi-lens camera when there is one, so zooming moves on to the
        // telephoto (or back to the ultra-wide) by itself, as in the Camera app.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: .back
        )
        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Open on the main lens, not on the ultra-wide a multi-lens camera's
        // factor 1 stands for.
        let main = Self.zoom(of: device).mainFactor
        if main != 1, (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = CGFloat(main)
            device.unlockForConfiguration()
        }
        self.device = device
        isConfigured = true
    }

    private static func zoom(of device: AVCaptureDevice) -> CameraZoom {
        CameraZoom(
            minFactor: Double(device.minAvailableVideoZoomFactor),
            maxFactor: Double(device.maxAvailableVideoZoomFactor),
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map(\.doubleValue),
            hasUltraWide: device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        )
    }

    /// Zoom to a device factor, gliding there for a button, at once for a pinch.
    func setZoom(_ factor: Double, animated: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            let target = CGFloat(min(max(factor, Double(device.minAvailableVideoZoomFactor)),
                                     Double(device.maxAvailableVideoZoomFactor)))
            if animated {
                device.ramp(toVideoZoomFactor: target, withRate: 8)
            } else {
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = target
            }
        }
    }

    func start() {
        let session = self.session
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        let session = self.session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Capture one photo, embedding `location` as EXIF GPS. Returns JPEG bytes.
    func capture(location: CLLocation?) async throws -> Data {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        let output = self.output
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            lock.lock()
            // A shutter tap while a capture is still in flight would otherwise
            // strand the first continuation.
            if let pending = captureContinuation {
                captureContinuation = nil
                lock.unlock()
                pending.resume(throwing: CameraError.captureFailed)
                lock.lock()
            }
            captureContinuation = cont
            pendingLocation = location
            lock.unlock()

            sessionQueue.async { [weak self] in
                guard let self else { return }
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        lock.lock()
        let cont = captureContinuation
        let location = pendingLocation
        captureContinuation = nil
        pendingLocation = nil
        lock.unlock()

        guard let cont else { return }

        if let error {
            cont.resume(throwing: error)
            return
        }
        guard let raw = photo.fileDataRepresentation() else {
            cont.resume(throwing: CameraError.captureFailed)
            return
        }
        // AVFoundation doesn't embed GPS itself; inject it with the round-tripped
        // ImageIO helper in FlaunedexCore, falling back to the untagged bytes.
        // The coordinate is also stored on the Sighting record regardless.
        let data: Data
        if let location {
            data = ExifGPS.inject(
                into: raw,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                timestamp: location.timestamp
            ) ?? raw
        } else {
            data = raw
        }
        cont.resume(returning: data)
    }
}
