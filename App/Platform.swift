import HTSCore
import SwiftUI
import UIKit

/** System sheets and apps: sharing a file, links, the Files app. */
@MainActor
enum Platform {
    static func share(_ url: URL) {
        guard var top = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad shows the sheet as a popover, which needs an anchor
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                                                 width: 0, height: 0)
        top.present(sheet, animated: true)
    }

    static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        UIApplication.shared.open(url)
    }

    /** The folder in the Files app ("На iPhone → McSkill"). */
    static func openInFiles(_ dir: URL) -> Bool {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let path = dir.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "shareddocuments://" + path) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

/** The face of a Minecraft skin (with the hat layer), pixel-sharp, cached on disk for 6 hours. */
struct SkinHead: View {
    let username: String
    let skinURL: String
    var size: CGFloat = 24

    @State private var face: UIImage?

    var body: some View {
        Group {
            if let face {
                Image(uiImage: face).interpolation(.none).resizable()
            } else {
                Icon("ic_user", Theme.text2, size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: username + skinURL) {
            face = await SkinHead.load(username: username, skinURL: skinURL)
        }
    }

    static func load(username: String, skinURL: String) async -> UIImage? {
        guard !username.isEmpty || !skinURL.isEmpty else { return nil }
        let link = skinURL.isEmpty ? "https://skins.mcskill.net/MinecraftSkins/\(username).png" : skinURL
        guard let url = URL(string: link) else { return nil }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cache = caches.appendingPathComponent("skin_\(stableHash(link)).png")
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            .map { Date().timeIntervalSince($0) } ?? .infinity
        if age > 6 * 3600 {
            if let answer = try? await URLSession.shared.data(from: url),
               (answer.1 as? HTTPURLResponse)?.statusCode == 200 {
                try? answer.0.write(to: cache, options: .atomic)
            }
        }
        guard let data = try? Data(contentsOf: cache), let skin = UIImage(data: data)?.cgImage else { return nil }
        return face(of: skin)
    }

    private static func face(of skin: CGImage) -> UIImage? {
        let unit = skin.width / 64
        guard unit > 0,
              let head = skin.cropping(to: CGRect(x: 8 * unit, y: 8 * unit, width: 8 * unit, height: 8 * unit)),
              let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        let rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        context.draw(head, in: rect)
        if let hat = skin.cropping(to: CGRect(x: 40 * unit, y: 8 * unit, width: 8 * unit, height: 8 * unit)) {
            context.draw(hat, in: rect)
        }
        return context.makeImage().map { UIImage(cgImage: $0) }
    }

    /** Same name across launches (String.hashValue is seeded per process). */
    private static func stableHash(_ s: String) -> String {
        var h: UInt64 = 5381
        for byte in s.utf8 { h = (h &* 33) &+ UInt64(byte) }
        return String(h, radix: 16)
    }
}
