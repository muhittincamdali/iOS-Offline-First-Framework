import Foundation
import RxSwift
import CocoaLumberjack

/// Manages offline data storage with encryption and compression
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class OfflineStorageManager {
    
    // MARK: - Properties
    
    public let storageStatus = BehaviorSubject<StorageStatus>(value: .normal)
    public let storageUsage = BehaviorSubject<StorageUsage>(value: StorageUsage())
    
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.offlinefirst.storage", qos: .userInitiated)
    private let disposeBag = DisposeBag()
    
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
        DDLogInfo("OfflineStorageManager initialized")
        createDirectoriesIfNeeded()
        updateStorageStatus()
    }
    
    public func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateStorageStatus()
        }
        DDLogInfo("Storage monitoring started")
    }
    
    public func save<T: Codable>(_ data: T) -> Observable<SaveResult> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(.failure(StorageError.unknown))
                observer.onCompleted()
                return Disposables.create()
            }
            
            self.queue.async {
                do {
                    let metadata = StorageMetadata(
                        id: UUID().uuidString,
                        type: String(describing: T.self),
                        createdAt: Date(),
                        updatedAt: Date(),
                        size: 0
                    )
                    
                    let data = try JSONEncoder().encode(data)
                    let compressedData = try self.compress(data)
                    let encryptedData = try self.encrypt(compressedData)
                    
                    let filename = "\(metadata.id).data"
                    let fileURL = self.dataDirectory.appendingPathComponent(filename)
                    
                    try encryptedData.write(to: fileURL)
                    
                    // Save metadata
                    let metadataData = try JSONEncoder().encode(metadata)
                    let metadataURL = self.metadataDirectory.appendingPathComponent("\(metadata.id).meta")
                    try metadataData.write(to: metadataURL)
                    
                    DispatchQueue.main.async {
                        observer.onNext(.success)
                        observer.onCompleted()
                    }
                    
                    self.updateStorageStatus()
                    
                } catch {
                    DispatchQueue.main.async {
                        observer.onNext(.failure(error))
                        observer.onCompleted()
                    }
                }
            }
            
            return Disposables.create()
        }
    }
    
    public func load<T: Codable>(_ type: T.Type) -> Observable<[T]> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext([])
                observer.onCompleted()
                return Disposables.create()
            }
            
            self.queue.async {
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
                    
                    DispatchQueue.main.async {
                        observer.onNext(results)
                        observer.onCompleted()
                    }
                    
                } catch {
                    DispatchQueue.main.async {
                        observer.onNext([])
                        observer.onCompleted()
                    }
                }
            }
            
            return Disposables.create()
        }
    }
    
    public func delete<T: Codable>(_ data: T) -> Observable<DeleteResult> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(.failure(StorageError.unknown))
                observer.onCompleted()
                return Disposables.create()
            }
            
            self.queue.async {
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
                            
                            DispatchQueue.main.async {
                                observer.onNext(.success)
                                observer.onCompleted()
                            }
                            
                            self.updateStorageStatus()
                            return
                        }
                    }
                    
                    DispatchQueue.main.async {
                        observer.onNext(.notFound)
                        observer.onCompleted()
                    }
                    
                } catch {
                    DispatchQueue.main.async {
                        observer.onNext(.failure(error))
                        observer.onCompleted()
                    }
                }
            }
            
            return Disposables.create()
        }
    }
    
    public func clearAllData() -> Observable<ClearResult> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(.failure(StorageError.unknown))
                observer.onCompleted()
                return Disposables.create()
            }
            
            self.queue.async {
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
                    
                    DispatchQueue.main.async {
                        observer.onNext(.success)
                        observer.onCompleted()
                    }
                    
                    self.updateStorageStatus()
                    
                } catch {
                    DispatchQueue.main.async {
                        observer.onNext(.failure(error))
                        observer.onCompleted()
                    }
                }
            }
            
            return Disposables.create()
        }
    }
    
    public func getStorageInfo() -> Observable<StorageInfo> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onCompleted()
                return Disposables.create()
            }
            
            self.queue.async {
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
                    
                    DispatchQueue.main.async {
                        observer.onNext(info)
                        observer.onCompleted()
                    }
                    
                } catch {
                    DispatchQueue.main.async {
                        observer.onCompleted()
                    }
                }
            }
            
            return Disposables.create()
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
            DDLogError("Failed to create storage directories: \(error)")
        }
    }
    
    private func updateStorageStatus() {
        getStorageInfo()
            .subscribe(onNext: { [weak self] info in
                self?.storageUsage.onNext(StorageUsage(
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
                
                self?.storageStatus.onNext(status)
            })
            .disposed(by: disposeBag)
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
        // Simple compression - in real implementation use proper compression
        return data
    }
    
    private func decompress(_ data: Data) throws -> Data {
        // Simple decompression - in real implementation use proper decompression
        return data
    }
    
    private func encrypt(_ data: Data) throws -> Data {
        // Simple encryption - in real implementation use proper encryption
        return data
    }
    
    private func decrypt(_ data: Data) throws -> Data {
        // Simple decryption - in real implementation use proper decryption
        return data
    }
}

// MARK: - Supporting Types

public enum StorageStatus {
    case normal
    case lowSpace
    case full
}

public struct StorageUsage {
    public let usedSpace: Int64
    public let availableSpace: Int64
    public let fileCount: Int
    
    public init(usedSpace: Int64 = 0, availableSpace: Int64 = 0, fileCount: Int = 0) {
        self.usedSpace = usedSpace
        self.availableSpace = availableSpace
        self.fileCount = fileCount
    }
}

public struct StorageInfo {
    public let totalSize: Int64
    public let fileCount: Int
    public let availableSpace: Int64
    
    public init(totalSize: Int64, fileCount: Int, availableSpace: Int64) {
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.availableSpace = availableSpace
    }
}

public struct StorageMetadata: Codable {
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
