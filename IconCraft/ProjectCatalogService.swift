//
//  ProjectCatalogService.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import AppKit
import Foundation

enum AppIconError: LocalizedError {
    case catalogNotFound
    case contentsJSONUnreadable
    case resizeFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .catalogNotFound:
            return String(localized: "No App Icon catalog was found in the selected folder.")
        case .contentsJSONUnreadable:
            return String(localized: "The App Icon catalog’s Contents.json could not be read.")
        case .resizeFailed:
            return String(localized: "The source image could not be resized to every required icon size.")
        case .exportFailed:
            return String(localized: "The App Icon catalog could not be written. Existing icons were left unchanged.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .catalogNotFound:
            return String(
                localized: "Choose an iOS project folder that contains an .appiconset inside Assets.xcassets."
            )
        case .contentsJSONUnreadable:
            return String(localized: "Ensure the .appiconset contains a valid Contents.json file.")
        case .resizeFailed:
            return String(localized: "Use a valid square PNG or JPEG and try exporting again.")
        case .exportFailed:
            return String(localized: "Check that you have write access to the selected .appiconset folder.")
        }
    }
}

/// Recursively inspects an iOS project tree for `.appiconset` catalogs.
enum ProjectCatalogService {
    /// Finds every `.appiconset` under `projectDirectory`.
    ///
    /// - Throws: `AppIconError.catalogNotFound` when none exist.
    /// - Returns: All candidate catalog URLs when one or more are found.
    static func findAppIconSets(in projectDirectory: URL) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            try scanAppIconSets(in: projectDirectory)
        }.value
    }

    /// Reads `Contents.json` in `appIconSet` and loads the largest icon file that exists on disk.
    static func largestExistingIcon(in appIconSet: URL) async throws -> NSImage? {
        let imageURL = try await Task.detached(priority: .userInitiated) {
            try largestExistingIconURL(in: appIconSet)
        }.value

        guard let imageURL else { return nil }
        return NSImage(contentsOf: imageURL)
    }
}

// MARK: - Background work

extension ProjectCatalogService {
    private static let skippedFolderNames: Set<String> = [
        ".git",
        ".build",
        "build",
        "Build",
        "DerivedData",
        "Pods",
        "Carthage",
        "node_modules",
    ]

    private static let skippedPackageExtensions: Set<String> = [
        "xcodeproj",
        "xcworkspace",
        "app",
        "appex",
        "framework",
        "xcframework",
    ]

    nonisolated private static func scanAppIconSets(in root: URL) throws -> [URL] {
        if root.pathExtension == "appiconset" {
            return [root]
        }

        let enumerator: FileManager.DirectoryEnumerator? = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        )

        guard let enumerator else {
            throw AppIconError.catalogNotFound
        }

        var matches: [URL] = []

        while let item = enumerator.nextObject() {
            guard let fileURL = item as? URL else { continue }
            let name = fileURL.lastPathComponent
            let ext = fileURL.pathExtension

            if skippedFolderNames.contains(name) || skippedPackageExtensions.contains(ext) {
                enumerator.skipDescendants()
                continue
            }

            if ext == "appiconset" {
                matches.append(fileURL)
                enumerator.skipDescendants()
            }
        }

        guard !matches.isEmpty else {
            throw AppIconError.catalogNotFound
        }

        return matches.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    nonisolated private static func largestExistingIconURL(in appIconSet: URL) throws -> URL? {
        let contentsURL = appIconSet.appendingPathComponent("Contents.json")
        guard let data = try? Data(contentsOf: contentsURL) else {
            throw AppIconError.contentsJSONUnreadable
        }

        let contents: AppIconContentsJSON
        do {
            contents = try JSONDecoder().decode(AppIconContentsJSON.self, from: data)
        } catch {
            throw AppIconError.contentsJSONUnreadable
        }

        let existing = contents.images.compactMap { entry -> (url: URL, pixelSize: CGFloat)? in
            guard let filename = entry.filename, !filename.isEmpty else { return nil }
            let fileURL = appIconSet.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                return nil
            }

            let jsonSize = entry.inferredPixelSize
            let pixelSize = jsonSize > 0 ? jsonSize : pixelDimension(of: fileURL)
            return (fileURL, pixelSize)
        }

        return existing.max(by: { $0.pixelSize < $1.pixelSize })?.url
    }

    nonisolated private static func pixelDimension(of url: URL) -> CGFloat {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return 0
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        return CGFloat(max(width, height))
    }
}
