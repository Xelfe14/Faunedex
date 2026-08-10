import Foundation
@preconcurrency import AVFoundation
import CoreLocation
import UIKit
import Observation
import FlaunedexCore

/// A minimal custom camera. AVFoundation is required (not `PhotosPicker`)
/// because only owning the capture callback lets us pair the exact frame with
/// the exact GPS fix — and AVFoundation does **not** embed EXIF GPS on its own,
/// so we inject it before writing the JPEG.
@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.taddeocarpinelli.flaunedex.camera")
    private var captureContinuation: CheckedContinuation<Data, Error>?
    private var pendingLocation: CLLocation?

    private(set) var isConfigured = false
    var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    enum CameraError: Error { case notAuthorized, configurationFailed, captureFailed }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            defer { self.session.commitConfiguration() }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else { return }
            self.session.addInput(input)

            guard self.session.canAddOutput(self.output) else { return }
            self.session.addOutput(self.output)
            self.isConfigured = true
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Capture one photo, embedding `location` as EXIF GPS. Returns JPEG bytes.
    func capture(location: CLLocation?) async throws -> Data {
        pendingLocation = location
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            captureContinuation = cont
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            captureContinuation?.resume(throwing: error)
            captureContinuation = nil
            return
        }
        guard let raw = photo.fileDataRepresentation() else {
            captureContinuation?.resume(throwing: CameraError.captureFailed)
            captureContinuation = nil
            return
        }
        // AVFoundation doesn't embed GPS itself; inject it with the round-tripped
        // ImageIO helper in FlaunedexCore (falling back to the untagged bytes —
        // the coordinate is also stored on the Sighting record regardless).
        let data: Data
        if let location = pendingLocation {
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
        captureContinuation?.resume(returning: data)
        captureContinuation = nil
    }
}
