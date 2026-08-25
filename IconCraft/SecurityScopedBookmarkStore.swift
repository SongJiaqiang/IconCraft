//
//  SecurityScopedBookmarkStore.swift
//  IconCraft
//
//  Created by Qiang on 2026/08/15.
//

import Foundation

/// Persists app-scoped security-scoped bookmarks for folders the user picked in `NSOpenPanel`.
enum SecurityScopedBookmarkStore {
    enum Key: String {
        case exportFolder = "securityScopedBookmark.exportFolder"
        case projectFolder = "securityScopedBookmark.projectFolder"
    }

    /// Stores a bookmark so the chosen folder can be reused without a Downloads entitlement.
    static func save(_ url: URL, for key: Key) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key.rawValue)
        } catch {
            // Session access from the open panel still works even if persistence fails.
        }
    }

    /// Resolves a previously chosen folder. Returns `nil` when missing, stale beyond repair, or gone.
    static func resolvedURL(for key: Key) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key.rawValue) else { return nil }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return nil
        }

        if isStale {
            save(url, for: key)
        }

        return url
    }
}
