import UIKit

enum LiveActivityImagePublisher {
    static let faintedIsisFileName = "isis_fainted_live"

    static func publishStaticImages() {
        publishAsset(named: "isis_fainted", fileName: faintedIsisFileName)
    }

    private static func publishAsset(named assetName: String, fileName: String) {
        guard let image = UIImage(named: assetName),
              let resizedImage = image.resizedForLiveActivity(maxPixelLength: 260),
              let data = resizedImage.pngData(),
              let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SharedStorage.appGroupID
              )
        else {
            return
        }

        let fileURL = groupURL.appendingPathComponent("\(fileName).png")

        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.none],
                ofItemAtPath: fileURL.path
            )
        } catch {
            print("Unable to publish Live Activity image \(fileName): \(error.localizedDescription)")
        }
    }
}

private extension UIImage {
    func resizedForLiveActivity(maxPixelLength: CGFloat) -> UIImage? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, maxPixelLength / longestSide)
        let targetSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
