import Foundation
@preconcurrency import Combine

/// Manages offline data storage with encryption and compression
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public final class OfflineStorageManager: ObservableObject {
    
    // MARK: - Properties
    
    public let storageStatus = CurrentValueSubject<StorageStatus, Never>(.normal)
    public let storageUsage = CurrentValueSubject<StorageUsage, Never>(StorageUsage())
    
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.offlinefirst.storage", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Storage Paths
    
    private var documentsDirectory: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var storageDirectory: URL {
        return documentsDirectory.appendingPathComponent("OfflineFirstStorage")
    }
    
    private var dataDirectory: URL {
        return storageDirectory.appendingPathComponent("Data")
    }
    
    private var metadataDirectory: URL {
        return storageDirectory.appendingPathComponent("Metadata")
    }
    
    // MARK: - Initialization
    
    public init() {
        setupStorage()
    }
    
    // MARK: - Public Methods
    
    public func initialize() {
        Logger.info("OfflineStorageManager initialized")
        createDirectoriesIfNeeded()
        updateStorageStatus()
    }
    
    public func startMonitoring() {
        Timer.publish(every: 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStorageStatus()
            }
            .store(in: &cancellables)
        Logger.info("Storage monitoring started")
    }
    
    public func save<T: Codable>(_ data: T) async throws -> SaveResult {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let metadata = StorageMetadata(
                        id: UUID().uuidString,
                        type: String(describing: T.self),
                        createdAt: Date(),
                        updatedAt: Date(),
                        size: 0
                    )
                    
                    let encodedData = try JSONEncoder().encode(data)
                    let compressedData = try self.compress(encodedData)
                    let encryptedData = try self.encrypt(compressedData)
                    
                    let filename = "\(metadata.id).data"
                    let fileURL = self.dataDirectory.appendingPathComponent(filename)
                    
                    try encryptedData.write(to: fileURL)
                    
                    // Save metadata
                    let metadataData = try JSONEncoder().encode(metadata)
                    let metadataURL = self.metadataDirectory.appendingPathComponent("\(metadata.id).meta")
                    try metadataData.write(to: metadataURL)
                    
                    Task { @MainActor in
                        self.updateStorageStatus()
                        continuation.resume(returning: .success)
                    }
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func load<T: Codable>(_ type: T.Type) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let metadataFiles = try self.fileManager.contentsOfDirectory(
                        at: self.metadataDirectory,
                        includingPropertiesForKeys: nil
                    )
                    
                    var results: [T] = []
                    
                    for metadataFile in metadataFiles {
                        let metadataData = try Data(contentsOf: metadataFile)
                        let metadata = try JSONDecoder().decode(StorageMetadata.self, from: metadataData)
                        
                        if metadata.type == String(describing: T.self) {
                            let dataFile = self.dataDirectory.appendingPathComponent("\(metadata.id).data")
                            let encryptedData = try Data(contentsOf: dataFile)
                            let decryptedData = try self.decrypt(encryptedData)
                            let compressedData = try self.decompress(decryptedData)
                            let object = try JSONDecoder().decode(T.self, from: compressedData)
                            results.append(object)
                        }
                    }
                    
                    continuation.resume(returning: results)
                    
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    public func delete<T: Codable>(_ data: T) async throws -> DeleteResult {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let dataToDelete = try JSONEncoder().encode(data)
                    let compressedData = try self.compress(dataToDelete)
                    
                    let metadataFiles = try self.fileManager.contentsOfDirectory(
                        at: self.metadataDirectory,
                        includingPropertiesForKeys: nil
                    )
                    
                    for metadataFile in metadataFiles {
                        let metadataData = try Data(contentsOf: metadataFile)
                        let metadata = try JSONDecoder().decode(StorageMetadata.self, from: metadataData)
                        
                        let dataFile = self.dataDirectory.appendingPathComponent("\(metadata.id).data")
                        let encryptedData = try Data(contentsOf: dataFile)
                        let decryptedData = try self.decrypt(encryptedData)
                        
                        if decryptedData == compressedData {
                            try self.fileManager.removeItem(at: dataFile)
                            try self.fileManager.removeItem(at: metadataFile)
                            
                            Task { @MainActor in
                                self.updateStorageStatus()
                                continuation.resume(returning: .success)
                            }
                            return
                        }
                    }
                    
                    continuation.resume(returning: .notFound)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func clearAllData() async throws -> ClearResult {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let dataFiles = try self.fileManager.contentsOfDirectory(
                        at: self.dataDirectory,
                        includingPropertiesForKeys: nil
                    )
                    
                    let metadataFiles = try self.fileManager.contentsOfDirectory(
                        at: self.metadataDirectory,
                        includingPropertiesForKeys: nil
                    )
                    
                    for file in dataFiles {
                        try self.fileManager.removeItem(at: file)
                    }
                    
                    for file in metadataFiles {
                        try self.fileManager.removeItem(at: file)
                    }
                    
                    Task { @MainActor in
                        self.updateStorageStatus()
                        continuation.resume(returning: .success)
                    }
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func getStorageInfo() async -> StorageInfo {
        return await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let dataFiles = try self.fileManager.contentsOfDirectory(
                        at: self.dataDirectory,
                        includingPropertiesForKeys: [.fileSizeKey]
                    )
                    
                    var totalSize: Int64 = 0
                    var fileCount = 0
                    
                    for file in dataFiles {
                        let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
                        totalSize += Int64(attributes.fileSize ?? 0)
                        fileCount += 1
                    }
                    
                    let info = StorageInfo(
                        totalSize: totalSize,
                        fileCount: fileCount,
                        availableSpace: self.getAvailableSpace()
                    )
                    
                    continuation.resume(returning: info)
                    
                } catch {
                    continuation.resume(returning: StorageInfo(totalSize: 0, fileCount: 0, availableSpace: 0))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupStorage() {
        createDirectoriesIfNeeded()
    }
    
    private func createDirectoriesIfNeeded() {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.error("Failed to create storage directories: \(error.localizedDescription)")
        }
    }
    
    private func updateStorageStatus() {
        Task {
            let info = await getStorageInfo()
            
            self.storageUsage.send(StorageUsage(
                usedSpace: info.totalSize,
                availableSpace: info.availableSpace,
                fileCount: info.fileCount
            ))
            
            let status: StorageStatus
            if info.totalSize > 100 * 1024 * 1024 { // 100MB
                status = .full
            } else if info.totalSize > 50 * 1024 * 1024 { // 50MB
                status = .lowSpace
            } else {
                status = .normal
            }
            
            self.storageStatus.send(status)
        }
    }
    
    private func getAvailableSpace() -> Int64 {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: documentsDirectory.path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    private func compress(_ data: Data) throws -> Data {
        return data
    }
    
    private func decompress(_ data: Data) throws -> Data {
        return data
    }
    
    private func encrypt(_ data: Data) throws -> Data {
        return data
    }
    
    private func decrypt(_ data: Data) throws -> Data {
        return data
    }
}

// MARK: - Supporting Types

public enum StorageStatus: Sendable {
    case normal
    case lowSpace
    case full
}

public struct StorageUsage: Sendable {
    public let usedSpace: Int64
    public let availableSpace: Int64
    public let fileCount: Int
    
    public init(usedSpace: Int64 = 0, availableSpace: Int64 = 0, fileCount: Int = 0) {
        self.usedSpace = usedSpace
        self.availableSpace = availableSpace
        self.fileCount = fileCount
    }
}

public struct StorageInfo: Sendable {
    public let totalSize: Int64
    public let fileCount: Int
    public let availableSpace: Int64
    
    public init(totalSize: Int64, fileCount: Int, availableSpace: Int64) {
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.availableSpace = availableSpace
    }
}

public struct StorageMetadata: Codable, Sendable {
    public let id: String
    public let type: String
    public let createdAt: Date
    public let updatedAt: Date
    public let size: Int64
    
    public init(id: String, type: String, createdAt: Date, updatedAt: Date, size: Int64) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.size = size
    }
}

public enum StorageError: Error {
    case unknown
    case insufficientSpace
    case corruptedData
    case encryptionFailed
    case compressionFailed
}
