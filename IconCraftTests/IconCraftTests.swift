//
//  IconCraftTests.swift
//  IconCraftTests
//
//  Created by Qiang on 2026/08/15.
//

import AppKit
import Testing
@testable import IconCraft

struct IconCraftTests {

    @Test func exportWritesCatalogIntoChosenDirectory() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("IconCraftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let catalogURL = try await AppIconsetExporter().export(
            sourceImage: makeSourceImage(),
            into: parent
        )

        let contents = catalogURL.appendingPathComponent("Contents.json")
        #expect(FileManager.default.fileExists(atPath: contents.path(percentEncoded: false)))
        #expect(catalogURL.lastPathComponent == "AppIcon.appiconset")
        #expect(
            catalogURL.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
                == parent.standardizedFileURL.path(percentEncoded: false)
        )
    }

    @Test func scannerFindsAppIconsetAndSkipsPhotoLibraries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IconCraftScan-\(UUID().uuidString)", isDirectory: true)
        let catalog = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        let photosLibrary = root.appendingPathComponent("Pictures/Photos Library.photoslibrary", isDirectory: true)
        let nestedCatalog = photosLibrary.appendingPathComponent("AppIcon.appiconset", isDirectory: true)

        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedCatalog, withIntermediateDirectories: true)

        let matches = try await ProjectCatalogService.findAppIconSets(in: root)
        let found = Set(matches.map { $0.standardizedFileURL.path(percentEncoded: false) })
        let expected = catalog.standardizedFileURL.path(percentEncoded: false)
        #expect(found == [expected])
    }

    @Test func userFacingErrorsDoNotUseIOS() {
        for error in [
            AppIconError.catalogNotFound,
            AppIconError.contentsJSONUnreadable,
            AppIconError.resizeFailed,
            AppIconError.exportFailed,
            AppIconError.downloadFailed,
        ] {
            let description = error.errorDescription ?? ""
            let recovery = error.recoverySuggestion ?? ""
            #expect(!description.localizedCaseInsensitiveContains("ios"))
            #expect(!recovery.localizedCaseInsensitiveContains("ios"))
        }
    }

    @Test func purposeStringsExplainConcreteUse() throws {
        let plist = try loadPlist("IconCraft/Info.plist")
        let requiredKeys = [
            "NSAppleMusicUsageDescription",
            "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription",
            "NSDownloadsFolderUsageDescription",
            "NSNetworkVolumesUsageDescription",
            "NSPhotoLibraryUsageDescription",
            "NSRemovableVolumesUsageDescription",
        ]

        for key in requiredKeys {
            let text = try #require(plist[key] as? String)
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(text.count > 80)
            #expect(
                text.localizedCaseInsensitiveContains("appiconset")
                    || text.localizedCaseInsensitiveContains("app icon")
                    || text.localizedCaseInsensitiveContains("icon")
            )
        }

        #expect(plist["NSContactsUsageDescription"] == nil)
        #expect(plist["NSMicrophoneUsageDescription"] == nil)
    }

    @Test func entitlementsAreLimitedToUserSelectedFilesAndBookmarks() throws {
        let plist = try loadPlist("IconCraft/IconCraft.entitlements")
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(plist["com.apple.security.files.user-selected.read-write"] as? Bool == true)
        #expect(plist["com.apple.security.files.bookmarks.app-scope"] as? Bool == true)
        #expect(plist["com.apple.security.files.downloads.read-write"] == nil)
        #expect(plist["com.apple.security.network.server"] == nil)
        #expect(plist["com.apple.security.network.client"] == nil)
        #expect(plist["com.apple.security.device.usb"] == nil)
    }

    @Test func projectDoesNotEnableDownloadsFolderEntitlement() throws {
        let root = repositoryRoot()
        let pbxproj = try String(
            contentsOf: root.appendingPathComponent("IconCraft.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        #expect(!pbxproj.contains("ENABLE_FILE_ACCESS_DOWNLOADS_FOLDER"))
        #expect(pbxproj.contains("ENABLE_USER_SELECTED_FILES = readwrite"))
        #expect(pbxproj.contains("CURRENT_PROJECT_VERSION = 14"))
        #expect(pbxproj.contains("CODE_SIGN_ENTITLEMENTS = IconCraft/IconCraft.entitlements"))
    }
}

private extension IconCraftTests {
    func makeSourceImage() -> NSImage {
        let pixelCount = 1024
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelCount,
            pixelsHigh: pixelCount,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: pixelCount, height: pixelCount))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pixelCount, height: pixelCount))
        image.addRepresentation(rep)
        return image
    }

    func loadPlist(_ relativePath: String) throws -> [String: Any] {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any])
    }

    func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
