import Foundation
import CryptoKit
import Security

// MARK: - Encryption Configuration

/// Configuration for encryption operations
public struct EncryptionConfiguration: Codable, Sendable {
    public let algorithm: EncryptionAlgorithm
    public let keyDerivation: KeyDerivationFunction
    public let saltLength: Int
    public let iterationCount: Int
    
    public static let `default` = EncryptionConfiguration(
        algorithm: .aes256GCM,
        keyDerivation: .pbkdf2,
        saltLength: 32,
        iterationCount: 100_000
    )
    
    public init(
        algorithm: EncryptionAlgorithm = .aes256GCM,
        keyDerivation: KeyDerivationFunction = .pbkdf2,
        saltLength: Int = 32,
        iterationCount: Int = 100_000
    ) {
        self.algorithm = algorithm
        self.keyDerivation = keyDerivation
        self.saltLength = saltLength
        self.iterationCount = iterationCount
    }
}

public enum EncryptionAlgorithm: String, Codable, Sendable {
    case aes256GCM = "AES-256-GCM"
    case chaChaPoly = "ChaCha20-Poly1305"
}

public enum KeyDerivationFunction: String, Codable, Sendable {
    case pbkdf2 = "PBKDF2"
    case hkdf = "HKDF"
}

// MARK: - Encryption Engine

/// Production-ready encryption engine using CryptoKit
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class EncryptionEngine: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let configuration: EncryptionConfiguration
    private let keychain: KeychainManager
    private let queue = DispatchQueue(label: "com.offlinefirst.encryption", qos: .userInitiated)
    
    private static let masterKeyTag = "com.offlinefirst.masterkey"
    private static let derivedKeyPrefix = "com.offlinefirst.derived."
    
    // MARK: - Initialization
    
    public init(configuration: EncryptionConfiguration = .default) {
        self.configuration = configuration
        self.keychain = KeychainManager()
    }
    
    // MARK: - Key Management
    
    /// Generate and store master encryption key
    public func generateMasterKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try keychain.store(key: key, withTag: Self.masterKeyTag)
        return key
    }
    
    /// Retrieve master key or generate if not exists
    public func getMasterKey() throws -> SymmetricKey {
        if let key = try? keychain.retrieve(withTag: Self.masterKeyTag) {
            return key
        }
        return try generateMasterKey()
    }
    
    /// Derive key from password using PBKDF2
    public func deriveKey(from password: String, salt: Data? = nil) throws -> (key: SymmetricKey, salt: Data) {
        let actualSalt = salt ?? generateRandomBytes(count: configuration.saltLength)
        
        guard let passwordData = password.data(using: .utf8) else {
            throw EncryptionError.invalidPassword
        }
        
        let derivedKey: SymmetricKey
        
        switch configuration.keyDerivation {
        case .pbkdf2:
            derivedKey = try derivePBKDF2Key(password: passwordData, salt: actualSalt)
        case .hkdf:
            derivedKey = try deriveHKDFKey(password: passwordData, salt: actualSalt)
        }
        
        return (derivedKey, actualSalt)
    }
    
    private func derivePBKDF2Key(password: Data, salt: Data) throws -> SymmetricKey {
        var derivedKeyData = Data(count: 32)
        
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(configuration.iterationCount),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        
        guard result == kCCSuccess else {
            throw EncryptionError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKeyData)
    }
    
    private func deriveHKDFKey(password: Data, salt: Data) throws -> SymmetricKey {
        let inputKey = SymmetricKey(data: password)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: "OfflineFirst-Encryption".data(using: .utf8)!,
            outputByteCount: 32
        )
        return derivedKey
    }
    
    // MARK: - Encryption
    
    /// Encrypt data using AES-256-GCM
    public func encrypt(_ data: Data, with key: SymmetricKey? = nil) throws -> EncryptedData {
        let encryptionKey = try key ?? getMasterKey()
        
        switch configuration.algorithm {
        case .aes256GCM:
            return try encryptAESGCM(data, with: encryptionKey)
        case .chaChaPoly:
            return try encryptChaChaPoly(data, with: encryptionKey)
        }
    }
    
    /// Encrypt data with password
    public func encrypt(_ data: Data, password: String) throws -> EncryptedDataWithSalt {
        let (key, salt) = try deriveKey(from: password)
        let encrypted = try encrypt(data, with: key)
        return EncryptedDataWithSalt(encryptedData: encrypted, salt: salt)
    }
    
    private func encryptAESGCM(_ data: Data, with key: SymmetricKey) throws -> EncryptedData {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        return EncryptedData(
            ciphertext: combined,
            algorithm: .aes256GCM,
            timestamp: Date()
        )
    }
    
    private func encryptChaChaPoly(_ data: Data, with key: SymmetricKey) throws -> EncryptedData {
        let nonce = ChaChaPoly.Nonce()
        let sealedBox = try ChaChaPoly.seal(data, using: key, nonce: nonce)
        
        return EncryptedData(
            ciphertext: sealedBox.combined,
            algorithm: .chaChaPoly,
            timestamp: Date()
        )
    }
    
    // MARK: - Decryption
    
    /// Decrypt data
    public func decrypt(_ encryptedData: EncryptedData, with key: SymmetricKey? = nil) throws -> Data {
        let decryptionKey = try key ?? getMasterKey()
        
        switch encryptedData.algorithm {
        case .aes256GCM:
            return try decryptAESGCM(encryptedData, with: decryptionKey)
        case .chaChaPoly:
            return try decryptChaChaPoly(encryptedData, with: decryptionKey)
        }
    }
    
    /// Decrypt data with password
    public func decrypt(_ encryptedData: EncryptedDataWithSalt, password: String) throws -> Data {
        let (key, _) = try deriveKey(from: password, salt: encryptedData.salt)
        return try decrypt(encryptedData.encryptedData, with: key)
    }
    
    private func decryptAESGCM(_ encryptedData: EncryptedData, with key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData.ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    private func decryptChaChaPoly(_ encryptedData: EncryptedData, with key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData.ciphertext)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
    
    // MARK: - Hashing
    
    /// Compute SHA256 hash
    public func hash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
    
    /// Compute HMAC
    public func hmac(_ data: Data, key: SymmetricKey? = nil) throws -> Data {
        let hmacKey = try key ?? getMasterKey()
        let authCode = HMAC<SHA256>.authenticationCode(for: data, using: hmacKey)
        return Data(authCode)
    }
    
    /// Verify HMAC
    public func verifyHMAC(_ data: Data, authentication: Data, key: SymmetricKey? = nil) throws -> Bool {
        let hmacKey = try key ?? getMasterKey()
        return HMAC<SHA256>.isValidAuthenticationCode(authentication, authenticating: data, using: hmacKey)
    }
    
    // MARK: - Utilities
    
    /// Generate cryptographically secure random bytes
    public func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
    
    /// Secure data wipe
    public func secureWipe(_ data: inout Data) {
        data.withUnsafeMutableBytes { buffer in
            memset_s(buffer.baseAddress, buffer.count, 0, buffer.count)
        }
    }
    
    /// Delete all stored keys
    public func deleteAllKeys() throws {
        try keychain.deleteAll()
    }
}

// MARK: - Keychain Manager

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class KeychainManager {
    
    public init() {}
    
    public func store(key: SymmetricKey, withTag tag: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecAttrService as String: "com.offlinefirst.encryption",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        // Delete existing key if present
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status)
        }
    }
    
    public func retrieve(withTag tag: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecAttrService as String: "com.offlinefirst.encryption",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let keyData = result as? Data else {
            throw EncryptionError.keyNotFound
        }
        
        return SymmetricKey(data: keyData)
    }
    
    public func delete(withTag tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecAttrService as String: "com.offlinefirst.encryption"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status)
        }
    }
    
    public func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.offlinefirst.encryption"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status)
        }
    }
}

// MARK: - Supporting Types

public struct EncryptedData: Codable, Sendable {
    public let ciphertext: Data
    public let algorithm: EncryptionAlgorithm
    public let timestamp: Date
    
    public init(ciphertext: Data, algorithm: EncryptionAlgorithm, timestamp: Date) {
        self.ciphertext = ciphertext
        self.algorithm = algorithm
        self.timestamp = timestamp
    }
}

public struct EncryptedDataWithSalt: Codable, Sendable {
    public let encryptedData: EncryptedData
    public let salt: Data
    
    public init(encryptedData: EncryptedData, salt: Data) {
        self.encryptedData = encryptedData
        self.salt = salt
    }
}

public enum EncryptionError: Error, LocalizedError {
    case invalidPassword
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case keyNotFound
    case keychainError(OSStatus)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return "Invalid password provided"
        case .keyDerivationFailed:
            return "Failed to derive encryption key"
        case .encryptionFailed:
            return "Encryption operation failed"
        case .decryptionFailed:
            return "Decryption operation failed"
        case .keyNotFound:
            return "Encryption key not found in keychain"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

// MARK: - CommonCrypto Bridge

import CommonCrypto

private func CCKeyDerivationPBKDF(
    _ algorithm: CCPBKDFAlgorithm,
    _ password: UnsafePointer<Int8>?,
    _ passwordLen: Int,
    _ salt: UnsafePointer<UInt8>?,
    _ saltLen: Int,
    _ prf: CCPseudoRandomAlgorithm,
    _ rounds: UInt32,
    _ derivedKey: UnsafeMutablePointer<UInt8>?,
    _ derivedKeyLen: Int
) -> Int32 {
    CCKeyDerivationPBKDF(
        algorithm,
        password,
        passwordLen,
        salt,
        saltLen,
        prf,
        rounds,
        derivedKey,
        derivedKeyLen
    )
}
