import SwiftUI
import UIKit

/// A small in-repo snapshot helper (no third-party library; see decisions log E4).
///
/// Renders a SwiftUI view to a PNG and compares it with a reference stored in
/// `__Snapshots__/` next to the test file. A missing reference is recorded and reported
/// as `.recorded`. To re-record, delete the PNG and run the test again.
///
/// References are only comparable on the iOS major version they were recorded on
/// (text rendering changes between releases); on another version the result is `.skipped`.
public enum Snapshot {
    public enum Result: Equatable, Sendable {
        case matched
        case recorded
        case skipped(String)
        case mismatch(String)

        /// True unless the image differs from its reference.
        public var isAcceptable: Bool {
            if case .mismatch = self { return false }
            return true
        }
    }

    public struct Variant: Sendable, Hashable {
        public let name: String
        public let colorScheme: ColorScheme
        public let dynamicType: DynamicTypeSize

        public static let light = Variant(name: "light", colorScheme: .light, dynamicType: .large)
        public static let dark = Variant(name: "dark", colorScheme: .dark, dynamicType: .large)
        public static let largeText = Variant(name: "xxxl", colorScheme: .light, dynamicType: .accessibility3)
        public static let themes: [Variant] = [.light, .dark]
        public static let all: [Variant] = [.light, .dark, .largeText]
    }

    /// Fraction of pixels allowed to differ (anti-aliasing noise).
    public static let tolerance = 0.005
    private static let scale: CGFloat = 2

    @MainActor
    public static func render<V: View>(_ view: V, variant: Variant, width: CGFloat, height: CGFloat? = nil) -> UIImage? {
        let content = view
            .frame(width: width, height: height)
            .fixedSize(horizontal: false, vertical: height == nil)
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.dynamicTypeSize, variant.dynamicType)
        let controller = UIHostingController(rootView: content)
        controller.overrideUserInterfaceStyle = variant.colorScheme == .dark ? .dark : .light
        controller.view.backgroundColor = .clear
        let target = controller.sizeThatFits(in: CGSize(width: width, height: height ?? .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: max(1, ceil(height ?? target.height)))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            controller.view.layer.render(in: context.cgContext)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    /// Renders `view` in each variant and compares with the stored references.
    @MainActor
    public static func verify<V: View>(
        _ view: V,
        named name: String,
        variants: [Variant] = Variant.themes,
        width: CGFloat = 390,
        height: CGFloat? = nil,
        filePath: String = #filePath
    ) -> [Result] {
        variants.map { variant in
            guard let image = render(view, variant: variant, width: width, height: height) else {
                return .mismatch("\(name).\(variant.name): could not render")
            }
            return compare(image, name: "\(name).\(variant.name)", filePath: filePath)
        }
    }

    static func compare(_ image: UIImage, name: String, filePath: String) -> Result {
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
        let reference = directory.appendingPathComponent("\(name).png")
        let stamp = directory.appendingPathComponent("recorded-on.txt")
        let system = "iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
        let fileManager = FileManager.default

        guard let referenceData = try? Data(contentsOf: reference) else {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                guard let png = image.pngData() else { return .mismatch("\(name): could not encode PNG") }
                try png.write(to: reference)
                if !fileManager.fileExists(atPath: stamp.path) {
                    try Data(system.utf8).write(to: stamp)
                }
                return .recorded
            } catch {
                return .skipped("\(name): no reference and the snapshot folder is not writable")
            }
        }
        if let recorded = try? String(contentsOf: stamp, encoding: .utf8),
           recorded.trimmingCharacters(in: .whitespacesAndNewlines) != system {
            return .skipped("\(name): references were recorded on \(recorded), running on \(system)")
        }
        guard let expected = UIImage(data: referenceData)?.cgImage, let actual = image.cgImage else {
            return .mismatch("\(name): unreadable image")
        }
        guard expected.width == actual.width, expected.height == actual.height else {
            return .mismatch("\(name): size \(actual.width)x\(actual.height), reference \(expected.width)x\(expected.height)")
        }
        let fraction = differingFraction(expected, actual)
        if fraction > tolerance {
            let failed = directory.appendingPathComponent("\(name).failed.png")
            try? image.pngData()?.write(to: failed)
            return .mismatch("\(name): \(String(format: "%.2f", fraction * 100))% of pixels differ")
        }
        return .matched
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    static func differingFraction(_ a: CGImage, _ b: CGImage) -> Double {
        let pa = pixels(a), pb = pixels(b)
        guard pa.count == pb.count, !pa.isEmpty else { return 1 }
        var differing = 0
        var index = 0
        while index < pa.count {
            let delta = abs(Int(pa[index]) - Int(pb[index]))
                + abs(Int(pa[index + 1]) - Int(pb[index + 1]))
                + abs(Int(pa[index + 2]) - Int(pb[index + 2]))
                + abs(Int(pa[index + 3]) - Int(pb[index + 3]))
            if delta > 24 { differing += 1 }
            index += 4
        }
        return Double(differing) / Double(pa.count / 4)
    }

    /// Average color of the rendered image, for sanity checks (for example "dark is darker").
    public static func averageLuminance(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let data = pixels(cg)
        var total = 0.0
        var index = 0
        while index < data.count {
            total += 0.2126 * Double(data[index]) + 0.7152 * Double(data[index + 1]) + 0.0722 * Double(data[index + 2])
            index += 4
        }
        return total / Double(max(1, data.count / 4)) / 255
    }
}
