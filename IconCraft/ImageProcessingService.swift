//
//  ImageProcessingService.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Pixel dimensions and a human-readable file size for a local image.
nonisolated struct ImageFileInfo: Sendable {
    let pixelSize: CGSize
    let formattedFileSize: String
}

/// Loads image metadata and produces high-quality square PNG bitmaps off the main thread.
enum ImageProcessingService {
    /// Reads pixel width/height and a formatted file-size string from a local image URL.
    static func imageInfo(from url: URL) async -> ImageFileInfo? {
        await Task.detached(priority: .userInitiated) {
            readImageInfo(from: url)
        }.value
    }

    /// Resizes `image` to a square `targetPixelSize` using a high-quality RGB bitmap, then
    /// rehydrates an `NSImage` from the resulting PNG data.
    static func resize(image: NSImage, targetPixelSize: CGFloat) async -> NSImage? {
        let pixelCount = Int(targetPixelSize.rounded())
        guard pixelCount > 0, let source = cgImage(from: image) else { return nil }

        let pngData = await Task.detached(priority: .userInitiated) {
            makePNGData(resizing: source, to: pixelCount)
        }.value
        guard let pngData else { return nil }

        let result = NSImage(data: pngData)
        result?.size = NSSize(width: pixelCount, height: pixelCount)
        return result
    }

    /// Same pipeline as `resize`, returning the PNG bytes used to build the `NSImage`.
    static func pngData(resizing image: NSImage, to targetPixelSize: CGFloat) async -> Data? {
        let pixelCount = Int(targetPixelSize.rounded())
        guard pixelCount > 0, let source = cgImage(from: image) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            makePNGData(resizing: source, to: pixelCount)
        }.value
    }

    /// Resizes `image` once per unique pixel size and returns PNG data keyed by that size.
    static func pngData(resizing image: NSImage, toPixelSizes pixelSizes: [Int]) async -> [Int: Data] {
        let uniqueSizes = Set(pixelSizes.filter { $0 > 0 })
        guard !uniqueSizes.isEmpty, let source = cgImage(from: image) else { return [:] }

        return await Task.detached(priority: .userInitiated) {
            var result: [Int: Data] = [:]
            result.reserveCapacity(uniqueSizes.count)
            for size in uniqueSizes {
                if let data = makePNGData(resizing: source, to: size) {
                    result[size] = data
                }
            }
            return result
        }.value
    }

    /// Normalizes both images to 512×512, compares raw RGBA pixels, and returns a
    /// black-on-white diff map (black = mismatch, white = identical).
    static func generatePixelDiff(newImage: NSImage, currentImage: NSImage) async -> NSImage? {
        guard let newSource = cgImage(from: newImage),
              let currentSource = cgImage(from: currentImage)
        else {
            return nil
        }

        let diff = await Task.detached(priority: .userInitiated) {
            makePixelDiff(new: newSource, current: currentSource)
        }.value
        guard let diff else { return nil }

        return NSImage(cgImage: diff, size: NSSize(width: Self.diffCanvasSize, height: Self.diffCanvasSize))
    }
}

// MARK: - Background work

extension ImageProcessingService {
    nonisolated fileprivate static let diffCanvasSize = 512
    nonisolated fileprivate static let diffPixelThreshold = 5

    nonisolated private static func readImageInfo(from url: URL) -> ImageFileInfo? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return nil }

        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file

        return ImageFileInfo(
            pixelSize: CGSize(width: width, height: height),
            formattedFileSize: formatter.string(fromByteCount: Int64(byteCount))
        )
    }

    nonisolated private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.cgImage }
    }

    nonisolated private static func makePNGData(resizing cgImage: CGImage, to pixelCount: Int) -> Data? {
        guard let resized = resize(cgImage, to: pixelCount) else { return nil }
        return pngData(from: resized)
    }

    nonisolated private static func resize(_ cgImage: CGImage, to pixelCount: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelCount,
            height: pixelCount,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: pixelCount, height: pixelCount))
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: pixelCount, height: pixelCount)
        )
        return context.makeImage()
    }

    nonisolated private static func makePixelDiff(new: CGImage, current: CGImage) -> CGImage? {
        let canvas = diffCanvasSize
        let bytesPerPixel = 4
        let bytesPerRow = canvas * bytesPerPixel
        let byteCount = bytesPerRow * canvas

        guard let newPixels = rgbaBuffer(from: new, canvasSize: canvas),
              let currentPixels = rgbaBuffer(from: current, canvasSize: canvas),
              newPixels.count == byteCount,
              currentPixels.count == byteCount
        else {
            return nil
        }

        var diffPixels = [UInt8](repeating: 0, count: byteCount)
        let threshold = diffPixelThreshold

        var offset = 0
        while offset < byteCount {
            let deltaR = abs(Int(newPixels[offset]) - Int(currentPixels[offset]))
            let deltaG = abs(Int(newPixels[offset + 1]) - Int(currentPixels[offset + 1]))
            let deltaB = abs(Int(newPixels[offset + 2]) - Int(currentPixels[offset + 2]))
            let deltaA = abs(Int(newPixels[offset + 3]) - Int(currentPixels[offset + 3]))
            let mismatched = deltaR > threshold || deltaG > threshold
                || deltaB > threshold || deltaA > threshold

            let value: UInt8 = mismatched ? 0 : 255
            diffPixels[offset] = value
            diffPixels[offset + 1] = value
            diffPixels[offset + 2] = value
            diffPixels[offset + 3] = 255
            offset += bytesPerPixel
        }

        return cgImage(fromRGBA: &diffPixels, canvasSize: canvas)
    }

    nonisolated private static func rgbaBuffer(from cgImage: CGImage, canvasSize: Int) -> [UInt8]? {
        let bytesPerRow = canvasSize * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * canvasSize)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let baseAddress = raw.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: canvasSize,
                      height: canvasSize,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }

            context.interpolationQuality = .high
            context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
            return true
        }
        return drew ? pixels : nil
    }

    nonisolated private static func cgImage(fromRGBA pixels: inout [UInt8], canvasSize: Int) -> CGImage? {
        let bytesPerRow = canvasSize * 4
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let baseAddress = raw.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: canvasSize,
                      height: canvasSize,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return nil
            }
            return context.makeImage()
        }
    }

    nonisolated private static func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
