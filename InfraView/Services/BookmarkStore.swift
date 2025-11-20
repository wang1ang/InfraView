//
//  BookmarkStore.swift
//  InfraView
//
//  Created by 王洋 on 27/9/2025.
//

import Foundation

enum BookmarkStore {
    private static let defaultsKey = "ScopedBookmarks"

    static func save(url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            var dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
            let key = url.standardizedFileURL.path
            dict[key] = data
            UserDefaults.standard.set(dict, forKey: defaultsKey)
        } catch {
            print("Save bookmark failed:", error)
        }
    }

    /// 尝试命中精确目录；否则做"最长祖先目录"的匹配
    static func resolve(matching parent: URL) -> URL? {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] else {
            return nil
        }
        let parentPath = parent.standardizedFileURL.path

        // 1) 精确命中
        if let exact = dict[parentPath] {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: exact,
                                options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil,
                                bookmarkDataIsStale: &stale),
               !stale {
                return u
            }
        }

        // 2) 祖先匹配（优先更长的祖先路径）
        let sorted = dict.keys.sorted { $0.count > $1.count }
        for k in sorted {
            if parentPath == k || parentPath.hasPrefix(k + "/") {
                if let data = dict[k] {
                    var stale = false
                    if let u = try? URL(resolvingBookmarkData: data,
                                        options: [.withSecurityScope, .withoutUI],
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &stale),
                       !stale {
                        return u
                    }
                }
            }
        }
        return nil
    }
}

