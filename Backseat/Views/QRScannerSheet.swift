import CoreImage
import PhotosUI
import SwiftUI
import VisionKit

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    let onCode: (String) -> Void

    private var cameraAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if cameraAvailable {
                    CameraQRScanner { code in deliver(code) }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent, lineWidth: 2))
                    Text("Point the camera at a playlist QR code.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Camera scanning unavailable", systemImage: "qrcode.viewfinder",
                                           description: Text("This device can't scan with the camera. Pick a screenshot or photo of the QR code instead."))
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose a QR image from Photos", systemImage: "photo")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding()
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    if let data, let code = Self.decodeQR(data) { deliver(code) } else { error = "No QR code found in that image." }
                }
            }
        }
    }

    private func deliver(_ code: String) {
        onCode(code)
        dismiss()
    }

    static func decodeQR(_ data: Data) -> String? {
        guard let image = CIImage(data: data),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

private struct CameraQRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        DispatchQueue.main.async { try? vc.startScanning() }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for case .barcode(let code) in items {
                if let value = code.payloadStringValue {
                    delivered = true
                    onCode(value)
                    return
                }
            }
        }
    }
}

/// Turns a scanned QR payload into form values. Xtream "get.php" links fill in the login fields.
enum ScannedSource {
    case m3u(url: String)
    case xtream(server: String, username: String, password: String)

    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: text), let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = comps.host else { return nil }
        let items = comps.queryItems ?? []
        let user = items.first { $0.name == "username" }?.value
        let pass = items.first { $0.name == "password" }?.value
        if let user, let pass, comps.path.hasSuffix("get.php") || comps.path.hasSuffix("player_api.php") {
            let port = comps.port.map { ":\($0)" } ?? ""
            self = .xtream(server: "\(scheme)://\(host)\(port)", username: user, password: pass)
        } else {
            self = .m3u(url: text)
        }
    }
}
