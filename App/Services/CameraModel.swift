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
/// deliberately: `isConfigured` is only ever read or written on `sessionQueue`,
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

    var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    enum CameraError: Error { case notAuthorized, configurationFailed, captureFailed }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func configure() {
        let session = self.session
        let output = self.output
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            session.beginConfiguration()
            session.sessionPreset = .photo
            defer { session.commitConfiguration() }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            self.isConfigured = true
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
