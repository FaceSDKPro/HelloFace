import Foundation
import HiFace
import Security

/// Demo 的 1:1 参考存储。HF1、Face ID 及当前选择都只保存在本机 Keychain。
enum DemoFaceStore {
    // HF1 不携带模型身份；参考特征与选择都按空间隔离，保留旧空间的数据。
    private static let service = "com.hiface.demo.face-feature.\(FaceFeatureFormat.featureSpaceID)"
    private static let selectionService = "\(service).selection"
    private static let selectionAccount = "selected-face-id"
    private static let featureLength = 604

    static func save(feature: String, faceID rawFaceID: String) throws -> String {
        let faceID = try validatedFaceID(rawFaceID)
        guard isValidFeature(feature), let data = feature.data(using: .utf8) else {
            throw StoreError.invalidFeature
        }

        let identity = identityQuery(faceID: faceID)
        var addition = identity
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addition as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try check(SecItemUpdate(
                identity as CFDictionary,
                [
                    kSecValueData as String: data,
                    // 更新特征时同时重申访问策略，避免同名记录保留更宽松的属性。
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ] as CFDictionary
            ))
        } else {
            try check(status)
        }
        try storeSelectedFaceID(faceID)
        return faceID
    }

    static func feature(for rawFaceID: String) throws -> String? {
        let faceID = try validatedFaceID(rawFaceID)
        var query = identityQuery(faceID: faceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data,
              let feature = String(data: data, encoding: .utf8),
              isValidFeature(feature) else {
            throw StoreError.invalidFeature
        }
        return feature
    }

    static func faceIDs() throws -> [String] {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        let attributes: [[String: Any]]
        if let values = result as? [[String: Any]] {
            attributes = values
        } else if let value = result as? [String: Any] {
            attributes = [value]
        } else {
            throw StoreError.invalidResult
        }
        return attributes.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func select(faceID rawFaceID: String) throws {
        let faceID = try validatedFaceID(rawFaceID)
        guard try feature(for: faceID) != nil else { throw StoreError.missingFaceID(faceID) }
        try storeSelectedFaceID(faceID)
    }

    /// 复用本轮读取的身份列表，避免刷新页面时再次扫描 Keychain。
    static func selectedFaceID(among available: [String]) throws -> String? {
        guard !available.isEmpty else {
            try clearSelectedFaceID()
            return nil
        }
        if let selected = try storedSelectedFaceID(), available.contains(selected) {
            return selected
        }
        let selected = available[0]
        try storeSelectedFaceID(selected)
        return selected
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
    }

    private static func identityQuery(faceID: String) -> [String: Any] {
        var query = baseQuery
        query[kSecAttrAccount as String] = faceID
        return query
    }

    private static var selectionQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: selectionService,
            kSecAttrAccount as String: selectionAccount
        ]
    }

    private static func storeSelectedFaceID(_ faceID: String) throws {
        guard let data = faceID.data(using: .utf8) else { throw StoreError.invalidFaceID }
        var addition = selectionQuery
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addition as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try check(SecItemUpdate(
                selectionQuery as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ] as CFDictionary
            ))
        } else {
            try check(status)
        }
    }

    private static func storedSelectedFaceID() throws -> String? {
        var query = selectionQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidResult
        }
        return try validatedFaceID(value)
    }

    private static func clearSelectedFaceID() throws {
        let status = SecItemDelete(selectionQuery as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    static func isValidFeature(_ feature: String) -> Bool {
        let bytes = Array(feature.utf8)
        guard bytes.count == featureLength, bytes.starts(with: [72, 70, 49, 58]) else { return false }
        return bytes.dropFirst(4).allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) ||
                (48...57).contains(byte) || byte == 45 || byte == 95
        }
    }

    private static func validatedFaceID(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, !result.contains("\0"), result.lengthOfBytes(using: .utf8) <= 255 else {
            throw StoreError.invalidFaceID
        }
        return result
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }
}

private enum StoreError: LocalizedError {
    case invalidFaceID
    case invalidFeature
    case invalidResult
    case missingFaceID(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFaceID:
            DemoL10n.text("Face ID 必填，最多 255 UTF-8 字节")
        case .invalidFeature:
            DemoL10n.text("参考人脸特征无效")
        case .invalidResult:
            DemoL10n.text("Keychain 返回了无法识别的数据")
        case .missingFaceID(let faceID):
            DemoL10n.text("找不到参考身份 {0}", [String(describing: faceID)])
        case .keychain(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? DemoL10n.text("Keychain 错误（{0}）", [String(describing: status)])
        }
    }
}
