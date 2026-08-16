//
//  AppIconSpec.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import CoreGraphics
import Foundation

/// A single iOS app icon slot in an `.appiconset` catalog.
nonisolated struct IconSpecification: Hashable, Identifiable, Sendable {
    var id: String { "\(idiom)-\(size)-\(scale)" }

    /// Asset catalog idiom: `iphone`, `ipad`, or `ios-marketing`.
    let idiom: String
    /// Point size as Xcode expects it, e.g. `"60x60"` or `"83.5x83.5"`.
    let size: String
    /// Scale factor as Xcode expects it, e.g. `"2x"`.
    let scale: String
    /// Rendered width/height in pixels (`point size × scale`).
    let pixelSize: CGFloat
    /// PNG filename written next to `Contents.json`.
    let filename: String

    init(idiom: String, size: String, scale: String, pixelSize: CGFloat) {
        self.idiom = idiom
        self.size = size
        self.scale = scale
        self.pixelSize = pixelSize
        self.filename = "AppIcon-\(idiom)-\(size)@\(scale).png"
    }

    var contentsJSONImage: AppIconContentsJSON.Image {
        AppIconContentsJSON.Image(
            idiom: idiom,
            size: size,
            scale: scale,
            filename: filename
        )
    }
}

/// All modern iOS application icon dimensions for an Xcode `.appiconset`.
enum AppIconConfig {
    static let allSpecs: [IconSpecification] = [
        // MARK: iPhone — Notification (20pt)
        IconSpecification(idiom: "iphone", size: "20x20", scale: "2x", pixelSize: 40),
        IconSpecification(idiom: "iphone", size: "20x20", scale: "3x", pixelSize: 60),
        // MARK: iPhone — Settings (29pt)
        IconSpecification(idiom: "iphone", size: "29x29", scale: "2x", pixelSize: 58),
        IconSpecification(idiom: "iphone", size: "29x29", scale: "3x", pixelSize: 87),
        // MARK: iPhone — Spotlight (40pt)
        IconSpecification(idiom: "iphone", size: "40x40", scale: "2x", pixelSize: 80),
        IconSpecification(idiom: "iphone", size: "40x40", scale: "3x", pixelSize: 120),
        // MARK: iPhone — App (60pt)
        IconSpecification(idiom: "iphone", size: "60x60", scale: "2x", pixelSize: 120),
        IconSpecification(idiom: "iphone", size: "60x60", scale: "3x", pixelSize: 180),

        // MARK: iPad — Notification (20pt)
        IconSpecification(idiom: "ipad", size: "20x20", scale: "1x", pixelSize: 20),
        IconSpecification(idiom: "ipad", size: "20x20", scale: "2x", pixelSize: 40),
        // MARK: iPad — Settings (29pt)
        IconSpecification(idiom: "ipad", size: "29x29", scale: "1x", pixelSize: 29),
        IconSpecification(idiom: "ipad", size: "29x29", scale: "2x", pixelSize: 58),
        // MARK: iPad — Spotlight (40pt)
        IconSpecification(idiom: "ipad", size: "40x40", scale: "1x", pixelSize: 40),
        IconSpecification(idiom: "ipad", size: "40x40", scale: "2x", pixelSize: 80),
        // MARK: iPad — App (76pt)
        IconSpecification(idiom: "ipad", size: "76x76", scale: "1x", pixelSize: 76),
        IconSpecification(idiom: "ipad", size: "76x76", scale: "2x", pixelSize: 152),
        // MARK: iPad Pro — App (83.5pt)
        IconSpecification(idiom: "ipad", size: "83.5x83.5", scale: "2x", pixelSize: 167),

        // MARK: App Store Marketing
        IconSpecification(idiom: "ios-marketing", size: "1024x1024", scale: "1x", pixelSize: 1024),
    ]

    static func contentsJSON(author: String = "xcode", version: Int = 1) -> AppIconContentsJSON {
        AppIconContentsJSON(specs: allSpecs, author: author, version: version)
    }
}

/// Xcode `Contents.json` schema for an `.appiconset` catalog.
nonisolated struct AppIconContentsJSON: Codable, Hashable, Sendable {
    var images: [Image]
    var info: Info

    init(images: [Image], info: Info) {
        self.images = images
        self.info = info
    }

    init(specs: [IconSpecification], author: String = "xcode", version: Int = 1) {
        self.images = specs.map(\.contentsJSONImage)
        self.info = Info(author: author, version: version)
    }

    /// One `images` entry in an `.appiconset` `Contents.json`.
    ///
    /// `filename` and `scale` are optional so empty slots and Xcode's single-size
    /// iOS catalogs (1024×1024, no scale) still decode.
    nonisolated struct Image: Codable, Hashable, Sendable {
        var idiom: String
        var size: String
        var scale: String?
        var filename: String?

        /// Point size × scale, e.g. `"83.5x83.5"` @ `"2x"` → 167.
        var inferredPixelSize: CGFloat {
            Self.pointDimension(from: size) * Self.scaleFactor(from: scale)
        }

        private static func pointDimension(from size: String) -> CGFloat {
            let token = size.lowercased().split(separator: "x").first
            return CGFloat(Double(token.map(String.init) ?? "") ?? 0)
        }

        private static func scaleFactor(from scale: String?) -> CGFloat {
            guard let scale else { return 1 }
            return CGFloat(Double(scale.lowercased().replacingOccurrences(of: "x", with: "")) ?? 1)
        }
    }

    /// The `info` dictionary Xcode writes into every asset catalog JSON.
    nonisolated struct Info: Codable, Hashable, Sendable {
        var author: String
        var version: Int
    }
}
