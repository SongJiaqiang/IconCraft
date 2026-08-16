//
//  AppIconsetExporter.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import AppKit
import Foundation

/// Writes a complete iOS `.appiconset` (PNGs + `Contents.json`), replacing any existing catalog atomically.
final class AppIconsetExporter {
    nonisolated private struct CatalogFile: Sendable {
        let filename: String
        let data: Data
    }

    /// Resizes `sourceImage` for every spec in `AppIconConfig.allSpecs` and replaces `targetDirectory`.
    ///
    /// New files are staged beside the catalog and swapped in only after every write succeeds.
    /// If replacement fails, the original catalog is restored from a sibling backup.
    func exportAndReplace(sourceImage: NSImage, targetDirectory: URL) async throws {
        let files = try await renderCatalogFiles(from: sourceImage)
        try await Task.detached(priority: .userInitiated) {
            try Self.replaceCatalog(at: targetDirectory, with: files)
        }.value
    }
}

// MARK: - Render

extension AppIconsetExporter {
    private func renderCatalogFiles(from sourceImage: NSImage) async throws -> [CatalogFile] {
        let specs = AppIconConfig.allSpecs
        let pixelSizes = specs.map { Int($0.pixelSize.rounded()) }
        let pngBySize = await ImageProcessingService.pngData(
            resizing: sourceImage,
            toPixelSizes: pixelSizes
        )

        var files: [CatalogFile] = []
        files.reserveCapacity(specs.count + 1)

        for spec in specs {
            let pixelSize = Int(spec.pixelSize.rounded())
            guard let data = pngBySize[pixelSize] else {
                throw AppIconError.resizeFailed
            }
            files.append(CatalogFile(filename: spec.filename, data: data))
        }

        files.append(CatalogFile(filename: "Contents.json", data: try contentsJSONData()))
        return files
    }

    private func contentsJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(AppIconConfig.contentsJSON())
    }
}

// MARK: - Atomic replace

extension AppIconsetExporter {
    nonisolated private static func replaceCatalog(at target: URL, with files: [CatalogFile]) throws {
        let fileManager = FileManager.default
        let parent = target.deletingLastPathComponent()
        let token = UUID().uuidString
        let stagingURL = parent.appendingPathComponent(".appiconset-export-\(token)", isDirectory: true)
        let backupURL = parent.appendingPathComponent(".appiconset-backup-\(token)", isDirectory: true)

        do {
            try writeStagingCatalog(files, to: stagingURL)
            try swapStaging(stagingURL, onto: target, backupURL: backupURL)
        } catch {
            restoreIfNeeded(target: target, backupURL: backupURL)
            try? fileManager.removeItem(at: stagingURL)
            throw AppIconError.exportFailed
        }

        try? fileManager.removeItem(at: backupURL)
    }

    nonisolated private static func writeStagingCatalog(_ files: [CatalogFile], to stagingURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        for file in files {
            let url = stagingURL.appendingPathComponent(file.filename)
            try file.data.write(to: url, options: .atomic)
        }
    }

    nonisolated private static func swapStaging(_ stagingURL: URL, onto target: URL, backupURL: URL) throws {
        let fileManager = FileManager.default
        let targetPath = target.path(percentEncoded: false)
        let hadOriginal = fileManager.fileExists(atPath: targetPath)

        if hadOriginal {
            try fileManager.moveItem(at: target, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: stagingURL, to: target)
        } catch {
            if hadOriginal {
                try? fileManager.removeItem(at: target)
                try fileManager.moveItem(at: backupURL, to: target)
            }
            throw error
        }
    }

    nonisolated private static func restoreIfNeeded(target: URL, backupURL: URL) {
        let fileManager = FileManager.default
        let backupPath = backupURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: backupPath) else { return }

        try? fileManager.removeItem(at: target)
        try? fileManager.moveItem(at: backupURL, to: target)
    }
}
