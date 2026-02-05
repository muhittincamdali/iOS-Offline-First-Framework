import Foundation
import CryptoKit

// MARK: - Delta Sync Configuration

/// Configuration for delta synchronization
public struct DeltaSyncConfiguration: Codable, Sendable {
    public let maxDeltaSize: Int
    public let minChangeThreshold: Double
    public let enableBinaryDiff: Bool
    public let chunkSize: Int
    public let maxHistoryCount: Int
    
    public static let `default` = DeltaSyncConfiguration(
        maxDeltaSize: 1_048_576,  // 1MB
        minChangeThreshold: 0.1,  // 10% minimum change
        enableBinaryDiff: true,
        chunkSize: 4096,
        maxHistoryCount: 100
    )
    
    public init(
        maxDeltaSize: Int = 1_048_576,
        minChangeThreshold: Double = 0.1,
        enableBinaryDiff: Bool = true,
        chunkSize: Int = 4096,
        maxHistoryCount: Int = 100
    ) {
        self.maxDeltaSize = maxDeltaSize
        self.minChangeThreshold = minChangeThreshold
        self.enableBinaryDiff = enableBinaryDiff
        self.chunkSize = chunkSize
        self.maxHistoryCount = maxHistoryCount
    }
}

// MARK: - Delta Types

/// Represents a change in a syncable entity
public struct DeltaChange: Codable, Identifiable, Sendable {
    public let id: String
    public let entityId: String
    public let entityType: String
    public let operation: DeltaOperation
    public let timestamp: Date
    public let version: Int64
    public let previousVersion: Int64?
    public let checksum: String
    public let patch: DeltaPatch?
    public let metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        entityId: String,
        entityType: String,
        operation: DeltaOperation,
        timestamp: Date = Date(),
        version: Int64,
        previousVersion: Int64? = nil,
        checksum: String,
        patch: DeltaPatch? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.entityId = entityId
        self.entityType = entityType
        self.operation = operation
        self.timestamp = timestamp
        self.version = version
        self.previousVersion = previousVersion
        self.checksum = checksum
        self.patch = patch
        self.metadata = metadata
    }
}

public enum DeltaOperation: String, Codable, Sendable {
    case create
    case update
    case delete
    case move
    case restore
}

/// Represents a patch that can be applied to transform data
public struct DeltaPatch: Codable, Sendable {
    public let operations: [PatchOperation]
    public let sourceChecksum: String
    public let targetChecksum: String
    public let sizeReduction: Double
    
    public init(
        operations: [PatchOperation],
        sourceChecksum: String,
        targetChecksum: String,
        sizeReduction: Double
    ) {
        self.operations = operations
        self.sourceChecksum = sourceChecksum
        self.targetChecksum = targetChecksum
        self.sizeReduction = sizeReduction
    }
}

public enum PatchOperation: Codable, Sendable {
    case retain(count: Int)
    case insert(data: Data)
    case delete(count: Int)
    case copy(sourceOffset: Int, length: Int)
    
    // JSON field operations for structured data
    case setField(path: String, value: Data)
    case deleteField(path: String)
    case incrementField(path: String, by: Int64)
    case appendArray(path: String, values: [Data])
    case removeArrayItems(path: String, indices: [Int])
}

// MARK: - Delta Sync Engine

/// High-performance delta synchronization engine
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public actor DeltaSyncEngine {
    
    // MARK: - Properties
    
    private let configuration: DeltaSyncConfiguration
    private var changeLog: [DeltaChange] = []
    private var checksumCache: [String: String] = [:]
    private var versionTracker: [String: Int64] = [:]
    
    // MARK: - Initialization
    
    public init(configuration: DeltaSyncConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Change Detection
    
    /// Detect changes between two versions of data
    public func detectChanges<T: Codable & Identifiable>(
        old: T?,
        new: T?,
        entityType: String
    ) throws -> DeltaChange? {
        guard let newEntity = new else {
            // Deletion
            guard let oldEntity = old else { return nil }
            let entityId = String(describing: oldEntity.id)
            let checksum = try computeChecksum(for: oldEntity)
            
            return DeltaChange(
                entityId: entityId,
                entityType: entityType,
                operation: .delete,
                version: nextVersion(for: entityId),
                previousVersion: versionTracker[entityId],
                checksum: checksum
            )
        }
        
        let entityId = String(describing: newEntity.id)
        let newChecksum = try computeChecksum(for: newEntity)
        
        guard let oldEntity = old else {
            // Creation
            return DeltaChange(
                entityId: entityId,
                entityType: entityType,
                operation: .create,
                version: nextVersion(for: entityId),
                checksum: newChecksum
            )
        }
        
        let oldChecksum = try computeChecksum(for: oldEntity)
        
        // No change
        if oldChecksum == newChecksum {
            return nil
        }
        
        // Generate patch
        let patch = try generatePatch(from: oldEntity, to: newEntity)
        
        return DeltaChange(
            entityId: entityId,
            entityType: entityType,
            operation: .update,
            version: nextVersion(for: entityId),
            previousVersion: versionTracker[entityId],
            checksum: newChecksum,
            patch: patch
        )
    }
    
    /// Detect changes in a collection
    public func detectBatchChanges<T: Codable & Identifiable>(
        old: [T],
        new: [T],
        entityType: String
    ) throws -> [DeltaChange] where T.ID: Hashable {
        var changes: [DeltaChange] = []
        
        let oldDict = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newDict = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
        
        // Detect creations and updates
        for (id, newEntity) in newDict {
            let oldEntity = oldDict[id]
            if let change = try detectChanges(old: oldEntity, new: newEntity, entityType: entityType) {
                changes.append(change)
            }
        }
        
        // Detect deletions
        for (id, oldEntity) in oldDict where newDict[id] == nil {
            if let change = try detectChanges(old: oldEntity, new: nil as T?, entityType: entityType) {
                changes.append(change)
            }
        }
        
        return changes.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Patch Generation
    
    /// Generate a patch to transform old data into new data
    public func generatePatch<T: Codable>(from old: T, to new: T) throws -> DeltaPatch {
        let oldData = try JSONEncoder().encode(old)
        let newData = try JSONEncoder().encode(new)
        
        let oldChecksum = computeDataChecksum(oldData)
        let newChecksum = computeDataChecksum(newData)
        
        // Use JSON diff for structured data
        let operations = try generateJSONPatch(from: oldData, to: newData)
        
        let patchSize = operations.reduce(0) { size, op in
            switch op {
            case .insert(let data): return size + data.count
            case .setField(_, let value): return size + value.count
            case .appendArray(_, let values): return size + values.reduce(0) { $0 + $1.count }
            default: return size + 8 // Overhead estimate
            }
        }
        
        let sizeReduction = 1.0 - (Double(patchSize) / Double(newData.count))
        
        return DeltaPatch(
            operations: operations,
            sourceChecksum: oldChecksum,
            targetChecksum: newChecksum,
            sizeReduction: max(0, sizeReduction)
        )
    }
    
    private func generateJSONPatch(from oldData: Data, to newData: Data) throws -> [PatchOperation] {
        guard let oldJSON = try JSONSerialization.jsonObject(with: oldData) as? [String: Any],
              let newJSON = try JSONSerialization.jsonObject(with: newData) as? [String: Any] else {
            // Fall back to binary diff for non-JSON data
            return try generateBinaryPatch(from: oldData, to: newData)
        }
        
        return try diffJSON(old: oldJSON, new: newJSON, path: "")
    }
    
    private func diffJSON(old: [String: Any], new: [String: Any], path: String) throws -> [PatchOperation] {
        var operations: [PatchOperation] = []
        
        let allKeys = Set(old.keys).union(Set(new.keys))
        
        for key in allKeys {
            let currentPath = path.isEmpty ? key : "\(path).\(key)"
            
            let oldValue = old[key]
            let newValue = new[key]
            
            if oldValue == nil && newValue != nil {
                // Field added
                let valueData = try JSONSerialization.data(withJSONObject: newValue!)
                operations.append(.setField(path: currentPath, value: valueData))
            } else if oldValue != nil && newValue == nil {
                // Field deleted
                operations.append(.deleteField(path: currentPath))
            } else if let oldDict = oldValue as? [String: Any], let newDict = newValue as? [String: Any] {
                // Nested object - recurse
                let nestedOps = try diffJSON(old: oldDict, new: newDict, path: currentPath)
                operations.append(contentsOf: nestedOps)
            } else if let oldArray = oldValue as? [Any], let newArray = newValue as? [Any] {
                // Array comparison
                let arrayOps = try diffArrays(old: oldArray, new: newArray, path: currentPath)
                operations.append(contentsOf: arrayOps)
            } else if !isEqual(oldValue, newValue) {
                // Value changed
                let valueData = try JSONSerialization.data(withJSONObject: newValue!)
                operations.append(.setField(path: currentPath, value: valueData))
            }
        }
        
        return operations
    }
    
    private func diffArrays(old: [Any], new: [Any], path: String) throws -> [PatchOperation] {
        var operations: [PatchOperation] = []
        
        // Find items to remove (present in old, not in new)
        var indicesToRemove: [Int] = []
        for (index, oldItem) in old.enumerated() {
            if !new.contains(where: { isEqual($0, oldItem) }) {
                indicesToRemove.append(index)
            }
        }
        
        if !indicesToRemove.isEmpty {
            operations.append(.removeArrayItems(path: path, indices: indicesToRemove))
        }
        
        // Find items to add (present in new, not in old)
        var itemsToAdd: [Data] = []
        for newItem in new {
            if !old.contains(where: { isEqual($0, newItem) }) {
                let itemData = try JSONSerialization.data(withJSONObject: newItem)
                itemsToAdd.append(itemData)
            }
        }
        
        if !itemsToAdd.isEmpty {
            operations.append(.appendArray(path: path, values: itemsToAdd))
        }
        
        return operations
    }
    
    private func generateBinaryPatch(from oldData: Data, to newData: Data) throws -> [PatchOperation] {
        var operations: [PatchOperation] = []
        
        // Simple LCS-based binary diff
        let chunkSize = configuration.chunkSize
        var oldIndex = 0
        var newIndex = 0
        
        while newIndex < newData.count {
            // Try to find matching chunk in old data
            let newChunkEnd = min(newIndex + chunkSize, newData.count)
            let newChunk = newData[newIndex..<newChunkEnd]
            
            var found = false
            for searchIndex in stride(from: oldIndex, to: oldData.count - newChunk.count + 1, by: 1) {
                let oldChunk = oldData[searchIndex..<searchIndex + newChunk.count]
                if oldChunk == newChunk {
                    // Found matching chunk - copy operation
                    operations.append(.copy(sourceOffset: searchIndex, length: newChunk.count))
                    oldIndex = searchIndex + newChunk.count
                    newIndex = newChunkEnd
                    found = true
                    break
                }
            }
            
            if !found {
                // No match found - insert new data
                operations.append(.insert(data: Data(newChunk)))
                newIndex = newChunkEnd
            }
        }
        
        return operations
    }
    
    // MARK: - Patch Application
    
    /// Apply a patch to transform data
    public func applyPatch<T: Codable>(_ patch: DeltaPatch, to data: T) throws -> T {
        var currentData = try JSONEncoder().encode(data)
        
        // Verify source checksum
        let sourceChecksum = computeDataChecksum(currentData)
        guard sourceChecksum == patch.sourceChecksum else {
            throw DeltaSyncError.checksumMismatch
        }
        
        // Apply operations
        guard var json = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
            throw DeltaSyncError.invalidData
        }
        
        for operation in patch.operations {
            json = try applyOperation(operation, to: json)
        }
        
        currentData = try JSONSerialization.data(withJSONObject: json)
        
        // Verify target checksum
        let targetChecksum = computeDataChecksum(currentData)
        guard targetChecksum == patch.targetChecksum else {
            throw DeltaSyncError.checksumMismatch
        }
        
        return try JSONDecoder().decode(T.self, from: currentData)
    }
    
    private func applyOperation(_ operation: PatchOperation, to json: [String: Any]) throws -> [String: Any] {
        var result = json
        
        switch operation {
        case .setField(let path, let value):
            let parsedValue = try JSONSerialization.jsonObject(with: value)
            result = setValueAtPath(result, path: path, value: parsedValue)
            
        case .deleteField(let path):
            result = deleteValueAtPath(result, path: path)
            
        case .incrementField(let path, let amount):
            if let current = valueAtPath(result, path: path) as? Int64 {
                result = setValueAtPath(result, path: path, value: current + amount)
            }
            
        case .appendArray(let path, let values):
            if var array = valueAtPath(result, path: path) as? [Any] {
                for valueData in values {
                    if let value = try? JSONSerialization.jsonObject(with: valueData) {
                        array.append(value)
                    }
                }
                result = setValueAtPath(result, path: path, value: array)
            }
            
        case .removeArrayItems(let path, let indices):
            if var array = valueAtPath(result, path: path) as? [Any] {
                for index in indices.sorted().reversed() {
                    if index < array.count {
                        array.remove(at: index)
                    }
                }
                result = setValueAtPath(result, path: path, value: array)
            }
            
        case .retain, .insert, .delete, .copy:
            // These are for binary patches - not applicable to JSON
            break
        }
        
        return result
    }
    
    // MARK: - Change Log Management
    
    /// Record a change to the log
    public func recordChange(_ change: DeltaChange) {
        changeLog.append(change)
        versionTracker[change.entityId] = change.version
        
        // Trim old entries
        if changeLog.count > configuration.maxHistoryCount {
            changeLog.removeFirst(changeLog.count - configuration.maxHistoryCount)
        }
    }
    
    /// Get changes since a specific version
    public func changesSince(version: Int64, entityType: String? = nil) -> [DeltaChange] {
        changeLog.filter { change in
            change.version > version &&
            (entityType == nil || change.entityType == entityType)
        }
    }
    
    /// Get pending changes for sync
    public func pendingChanges() -> [DeltaChange] {
        changeLog
    }
    
    /// Clear synced changes
    public func clearSyncedChanges(upToVersion version: Int64) {
        changeLog.removeAll { $0.version <= version }
    }
    
    // MARK: - Utilities
    
    private func computeChecksum<T: Codable>(for entity: T) throws -> String {
        let data = try JSONEncoder().encode(entity)
        return computeDataChecksum(data)
    }
    
    private func computeDataChecksum(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func nextVersion(for entityId: String) -> Int64 {
        let current = versionTracker[entityId] ?? 0
        return current + 1
    }
    
    private func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if lhs == nil && rhs == nil { return true }
        guard let l = lhs, let r = rhs else { return false }
        
        switch (l, r) {
        case (let l as Int, let r as Int): return l == r
        case (let l as Double, let r as Double): return l == r
        case (let l as String, let r as String): return l == r
        case (let l as Bool, let r as Bool): return l == r
        case (let l as [String: Any], let r as [String: Any]):
            return NSDictionary(dictionary: l).isEqual(to: r)
        case (let l as [Any], let r as [Any]):
            return NSArray(array: l).isEqual(to: r)
        default:
            return false
        }
    }
    
    private func valueAtPath(_ dict: [String: Any], path: String) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = dict
        
        for component in components {
            if let dict = current as? [String: Any] {
                guard let value = dict[component] else { return nil }
                current = value
            } else {
                return nil
            }
        }
        
        return current
    }
    
    private func setValueAtPath(_ dict: [String: Any], path: String, value: Any) -> [String: Any] {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return dict }
        
        var result = dict
        
        if components.count == 1 {
            result[components[0]] = value
        } else {
            let key = components[0]
            let remainingPath = components.dropFirst().joined(separator: ".")
            
            if var nested = result[key] as? [String: Any] {
                nested = setValueAtPath(nested, path: remainingPath, value: value)
                result[key] = nested
            }
        }
        
        return result
    }
    
    private func deleteValueAtPath(_ dict: [String: Any], path: String) -> [String: Any] {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return dict }
        
        var result = dict
        
        if components.count == 1 {
            result.removeValue(forKey: components[0])
        } else {
            let key = components[0]
            let remainingPath = components.dropFirst().joined(separator: ".")
            
            if var nested = result[key] as? [String: Any] {
                nested = deleteValueAtPath(nested, path: remainingPath)
                result[key] = nested
            }
        }
        
        return result
    }
}

// MARK: - Errors

public enum DeltaSyncError: Error, LocalizedError {
    case checksumMismatch
    case patchGenerationFailed
    case patchApplicationFailed
    case invalidData
    case versionConflict
    
    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Data checksum does not match expected value"
        case .patchGenerationFailed:
            return "Failed to generate delta patch"
        case .patchApplicationFailed:
            return "Failed to apply delta patch"
        case .invalidData:
            return "Invalid data format"
        case .versionConflict:
            return "Version conflict detected"
        }
    }
}
