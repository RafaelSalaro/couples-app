@preconcurrency import AVFoundation
import CoreImage.CIFilterBuiltins
import DesignSystem
import SwiftUI
import UIKit

/// Renders a QR code for a string.
public enum QRImage {
    public static func make(_ string: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A QR code on a white card (codes need a light quiet zone to scan in dark mode too).
public struct QRCodeView: View {
    let string: String
    let accessibilityText: String

    public init(_ string: String, accessibilityText: String) {
        self.string = string
        self.accessibilityText = accessibilityText
    }

    public var body: some View {
        Group {
            if let image = QRImage.make(string) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(Color.black)
            }
        }
        .padding(Spacing.md)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }
}

/// Camera scanner with a guide frame. Where there is no camera (the Simulator) or access was
/// declined it explains what to do instead; `sample` offers a stand-in code in demo builds and UI tests.
public struct QRScannerView: View {
    let onScan: (String) -> Void
    let sample: (() -> String?)?
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)

    public init(sample: (() -> String?)? = nil, onScan: @escaping (String) -> Void) {
        self.sample = sample
        self.onScan = onScan
    }

    private var hasCamera: Bool { AVCaptureDevice.default(for: .video) != nil }

    public var body: some View {
        ZStack {
            Color.dusk
            if hasCamera, access == .authorized {
                CameraPreview(onScan: onScan)
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .strokeBorder(Color.onDusk.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.onDusk)
                        .accessibilityHidden(true)
                    Text(message)
                        .textRole(.body)
                        .foregroundStyle(Color.onDusk)
                        .multilineTextAlignment(.center)
                    if hasCamera, access == .denied || access == .restricted, let url = URL(string: UIApplication.openSettingsURLString) {
                        Link(L("Open Settings"), destination: url)
                            .textRole(.heading)
                            .foregroundStyle(Color.glow)
                    }
                    if let sample {
                        Button(L("Use a sample code")) {
                            if let value = sample() { onScan(value) }
                        }
                        .buttonStyle(.ds(.onDusk, fullWidth: false))
                        .accessibilityIdentifier("scanner.sample")
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .task {
            if hasCamera, access == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                access = granted ? .authorized : .denied
            }
        }
    }

    private var message: String {
        if !hasCamera { return L("This device has no camera to scan with.") }
        if access == .notDetermined { return L("Allow the camera to scan your partner's code.") }
        return L("Camera access is off. You can turn it on in Settings.")
    }
}

private struct CameraPreview: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onScan = onScan
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var lastValue: String?
    private var lastTime = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        MainActor.assumeIsolated {
            // The camera reports the same code many times a second; pass each one on once.
            guard value != lastValue || Date().timeIntervalSince(lastTime) > 2 else { return }
            lastValue = value
            lastTime = Date()
            onScan?(value)
        }
    }
}
