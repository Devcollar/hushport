#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

struct PairingScannerView: UIViewControllerRepresentable {
    let isScanningEnabled: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        controller.setScanningEnabled(isScanningEnabled)
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.onScan = onScan
        uiViewController.setScanningEnabled(isScanningEnabled)
    }
}

final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var isEnabled = true
    private var didScan = false

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            didScan = false
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard isEnabled,
              !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }

        didScan = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onScan?(value)
    }
}

final class ScannerViewController: UIViewController {
    var onScan: ((String) -> Void)? {
        didSet {
            metadataDelegate.onScan = { [weak self] value in
                self?.onScan?(value)
            }
        }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.hushport.camera-session", qos: .userInitiated)
    private let metadataDelegate = MetadataDelegate()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var scanningEnabled = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        configureSessionIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSessionIfNeeded()
    }

    func setScanningEnabled(_ enabled: Bool) {
        scanningEnabled = enabled
        metadataDelegate.setEnabled(enabled)
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }

        session.addOutput(output)
        output.setMetadataObjectsDelegate(metadataDelegate, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        metadataDelegate.onScan = { [weak self] value in
            guard let self, self.scanningEnabled else { return }
            self.onScan?(value)
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview
        view.layer.insertSublayer(preview, at: 0)

        isConfigured = true
        startSessionIfNeeded()
    }

    private func startSessionIfNeeded() {
        guard isConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func stopSessionIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}
#endif
