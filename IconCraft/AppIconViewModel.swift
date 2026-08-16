//
//  AppIconViewModel.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import AppKit
import Combine
import UniformTypeIdentifiers

struct IconPreviewItem: Identifiable {
    var id: String { spec.id }
    let spec: IconSpecification
    let image: NSImage
}

@MainActor
final class AppIconViewModel: ObservableObject {
    @Published var selectedImageURL: URL?
    @Published var sourceImage: NSImage?
    @Published var pixelDimensions: CGSize?
    @Published var fileSizeString: String?
    @Published var generatedPreviews: [IconPreviewItem] = []

    @Published var projectURL: URL?
    @Published var availableIconSets: [URL] = []
    @Published var selectedIconSetURL: URL?

    @Published var currentAppIcon: NSImage?
    @Published var diffImage: NSImage?

    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var showSuccessAlert = false
    @Published var showDownloadSuccessAlert = false

    private var downloadedCatalogURL: URL?

    private let exporter = AppIconsetExporter()
    private var scopedImageURL: URL?
    private var scopedProjectURL: URL?
    private var operationID = 0
    private var inFlightOperations = 0

    deinit {
        scopedImageURL?.stopAccessingSecurityScopedResource()
        scopedProjectURL?.stopAccessingSecurityScopedResource()
    }

    var canCalculateDiff: Bool {
        sourceImage != nil && currentAppIcon != nil
    }

    var canReplaceIcons: Bool {
        sourceImage != nil && selectedIconSetURL != nil && !isProcessing
    }

    var canDownloadIcons: Bool {
        sourceImage != nil && !isProcessing
    }
}

// MARK: - Image selection

extension AppIconViewModel {
    func selectSourceImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic, .tiff, .gif]
        panel.title = String(localized: "Choose Source Icon")
        panel.message = String(localized: "Select a square image to generate iOS app icons.")

        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            await loadSourceImage(from: url)
        }
    }

    func loadSourceImage(from url: URL) async {
        let token = beginOperation()
        defer { endOperation() }

        replaceScopedURL(&scopedImageURL, with: url)
        selectedImageURL = url
        errorMessage = nil

        guard let image = NSImage(contentsOf: url) else {
            clearSourceImageMetadata()
            present(AppIconError.resizeFailed)
            return
        }

        sourceImage = image

        if let info = await ImageProcessingService.imageInfo(from: url) {
            pixelDimensions = info.pixelSize
            fileSizeString = info.formattedFileSize
        } else {
            pixelDimensions = image.size
            fileSizeString = nil
        }

        guard isCurrentOperation(token) else { return }
        await refreshGeneratedPreviews()
        await refreshDiff()
    }
}

// MARK: - Project selection

extension AppIconViewModel {
    func selectProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = [.folder]
        panel.title = String(localized: "Choose iOS Project")
        panel.message = String(localized: "Select an iOS project folder, Assets.xcassets, or an .appiconset.")

        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            await loadProject(from: url)
        }
    }

    func loadProject(from url: URL) async {
        let token = beginOperation()
        defer { endOperation() }

        replaceScopedURL(&scopedProjectURL, with: url)
        projectURL = url
        errorMessage = nil
        availableIconSets = []
        selectedIconSetURL = nil
        currentAppIcon = nil
        diffImage = nil

        do {
            let catalogs = try await ProjectCatalogService.findAppIconSets(in: url)
            guard isCurrentOperation(token) else { return }

            availableIconSets = catalogs
            selectedIconSetURL = preferredIconSet(in: catalogs)
            await loadCurrentIcon()
            await refreshDiff()
        } catch {
            guard isCurrentOperation(token) else { return }
            present(error)
        }
    }

    func selectIconSet(_ url: URL?) {
        guard selectedIconSetURL != url else { return }
        selectedIconSetURL = url
        currentAppIcon = nil
        diffImage = nil

        Task {
            let token = beginOperation()
            defer { endOperation() }
            await loadCurrentIcon()
            guard isCurrentOperation(token) else { return }
            await refreshDiff()
        }
    }
}

// MARK: - Diff & export

extension AppIconViewModel {
    func calculatePixelDiff() {
        Task {
            let token = beginOperation()
            defer { endOperation() }
            await refreshDiff()
            guard isCurrentOperation(token) else { return }
            if !canCalculateDiff {
                errorMessage = String(localized: "Add a source image and an existing app icon to compare.")
            }
        }
    }

    func downloadAppIcons() {
        guard let sourceImage else {
            errorMessage = String(localized: "Choose a source image to download an App Icon catalog.")
            return
        }

        Task {
            let token = beginOperation()
            defer { endOperation() }

            errorMessage = nil
            showDownloadSuccessAlert = false

            do {
                let catalogURL = try await exporter.exportToDownloads(sourceImage: sourceImage)
                guard isCurrentOperation(token) else { return }
                downloadedCatalogURL = catalogURL
                showDownloadSuccessAlert = true
            } catch {
                guard isCurrentOperation(token) else { return }
                present(error)
            }
        }
    }

    func revealDownloadedCatalog() {
        guard let downloadedCatalogURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([downloadedCatalogURL])
    }

    func replaceAppIcons() {
        guard let sourceImage, let selectedIconSetURL else {
            errorMessage = String(localized: "Choose a source image and an App Icon catalog to replace.")
            return
        }

        Task {
            let token = beginOperation()
            defer { endOperation() }

            errorMessage = nil
            showSuccessAlert = false

            do {
                try await exporter.exportAndReplace(
                    sourceImage: sourceImage,
                    targetDirectory: selectedIconSetURL
                )
                guard isCurrentOperation(token) else { return }

                await loadCurrentIcon()
                await refreshDiff()
                showSuccessAlert = true
            } catch {
                guard isCurrentOperation(token) else { return }
                present(error)
            }
        }
    }
}

// MARK: - Private

extension AppIconViewModel {
    private func loadCurrentIcon() async {
        guard let selectedIconSetURL else {
            currentAppIcon = nil
            return
        }

        do {
            currentAppIcon = try await ProjectCatalogService.largestExistingIcon(in: selectedIconSetURL)
        } catch {
            currentAppIcon = nil
            present(error)
        }
    }

    private func refreshGeneratedPreviews() async {
        guard let sourceImage else {
            generatedPreviews = []
            return
        }

        let specs = AppIconConfig.allSpecs
        let pngBySize = await ImageProcessingService.pngData(
            resizing: sourceImage,
            toPixelSizes: specs.map { Int($0.pixelSize.rounded()) }
        )

        generatedPreviews = specs.compactMap { spec in
            let pixelCount = Int(spec.pixelSize.rounded())
            guard let data = pngBySize[pixelCount], let image = NSImage(data: data) else {
                return nil
            }
            image.size = NSSize(width: pixelCount, height: pixelCount)
            return IconPreviewItem(spec: spec, image: image)
        }
    }

    private func refreshDiff() async {
        guard let sourceImage, let currentAppIcon else {
            diffImage = nil
            return
        }

        diffImage = await ImageProcessingService.generatePixelDiff(
            newImage: sourceImage,
            currentImage: currentAppIcon
        )
    }

    private func preferredIconSet(in catalogs: [URL]) -> URL? {
        catalogs.first { $0.deletingPathExtension().lastPathComponent == "AppIcon" }
            ?? catalogs.first
    }

    private func clearSourceImageMetadata() {
        sourceImage = nil
        pixelDimensions = nil
        fileSizeString = nil
        generatedPreviews = []
        diffImage = nil
    }

    private func present(_ error: Error) {
        if let localized = error as? LocalizedError {
            var message = localized.errorDescription ?? error.localizedDescription
            if let recovery = localized.recoverySuggestion {
                message += "\n\n\(recovery)"
            }
            errorMessage = message
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceScopedURL(_ storage: inout URL?, with url: URL) {
        storage?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        storage = url
    }

    private func beginOperation() -> Int {
        operationID += 1
        inFlightOperations += 1
        isProcessing = true
        return operationID
    }

    private func endOperation() {
        inFlightOperations = max(0, inFlightOperations - 1)
        isProcessing = inFlightOperations > 0
    }

    private func isCurrentOperation(_ token: Int) -> Bool {
        token == operationID
    }
}
