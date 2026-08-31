import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct TelegramLoginQRCodeView: View {
    let url: URL

    private static let context = CIContext(options: [
        .useSoftwareRenderer: false
    ])

    var body: some View {
        Group {
            if let image = qrCode {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(34)
            }
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var qrCode: CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return Self.context.createCGImage(scaled, from: scaled.extent)
    }
}
