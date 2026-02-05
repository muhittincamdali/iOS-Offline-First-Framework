import Foundation
import Compression

// MARK: - Compression Configuration

/// Configuration for compression operations
public struct CompressionConfiguration: Codable, Sendable {
    public let algorithm: CompressionAlgorithm
    public let level: CompressionLevel
    public let bufferSize: Int
    public let minSizeToCompress: Int
    
    public static let `default` = CompressionConfiguration(
        algorithm: .lz4,
        level: .balanced,
        bufferSize: 65536,
        minSizeToCompress: 1024
    )
    
    public static let maxCompression = CompressionConfiguration(
        algorithm: .lzma,
        level: .maximum,
        bufferSize: 131072,
        minSizeToCompress: 512
    )
    
    public static let fastCompression = CompressionConfiguration(
        algorithm: .lz4,
        level: .fast,
        bufferSize: 32768,
        minSizeToCompress: 2048
    )
    
    public init(
        algorithm: CompressionAlgorithm = .lz4,
        level: CompressionLevel = .balanced,
        bufferSize: Int = 65536,
        minSizeToCompress: Int = 1024
    ) {
        self.algorithm = algorithm
        self.level = level
        self.bufferSize = bufferSize
        self.minSizeToCompress = minSizeToCompress
    }
}

public enum CompressionAlgorithm: String, Codable, Sendable {
    case lz4 = "LZ4"           // Fast compression, moderate ratio
    case zlib = "ZLIB"         // Good balance of speed and ratio
    case lzma = "LZMA"         // Maximum compression, slower
    case lzfse = "LZFSE"       // Apple's optimized algorithm
}

public enum CompressionLevel: Int, Codable, Sendable {
    case fast = 0
    case balanced = 5
    case maximum = 9
}

// MARK: - Compression Engine

/// Production-ready compression engine using Apple's Compression framework
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class CompressionEngine: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let configuration: CompressionConfiguration
    private let queue = DispatchQueue(label: "com.offlinefirst.compression", qos: .userInitiated, attributes: .concurrent)
    
    // MARK: - Initialization
    
    public init(configuration: CompressionConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Compression
    
    /// Compress data using configured algorithm
    public func compress(_ data: Data) throws -> CompressedData {
        // Skip compression for small data
        if data.count < configuration.minSizeToCompress {
            return CompressedData(
                data: data,
                algorithm: nil,
                originalSize: data.count,
                compressedSize: data.count,
                compressionRatio: 1.0,
                isCompressed: false
            )
        }
        
        let algorithm = nativeAlgorithm(for: configuration.algorithm)
        let compressedData = try performCompression(data, algorithm: algorithm)
        
        // Only use compression if it actually reduces size
        if compressedData.count >= data.count {
            return CompressedData(
                data: data,
                algorithm: nil,
                originalSize: data.count,
                compressedSize: data.count,
                compressionRatio: 1.0,
                isCompressed: false
            )
        }
        
        let ratio = Double(compressedData.count) / Double(data.count)
        
        return CompressedData(
            data: compressedData,
            algorithm: configuration.algorithm,
            originalSize: data.count,
            compressedSize: compressedData.count,
            compressionRatio: ratio,
            isCompressed: true
        )
    }
    
    /// Compress data asynchronously
    public func compressAsync(_ data: Data) async throws -> CompressedData {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.compress(data)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Compress multiple data items in parallel
    public func compressBatch(_ items: [Data]) async throws -> [CompressedData] {
        try await withThrowingTaskGroup(of: (Int, CompressedData).self) { group in
            for (index, data) in items.enumerated() {
                group.addTask {
                    let compressed = try self.compress(data)
                    return (index, compressed)
                }
            }
            
            var results = [(Int, CompressedData)]()
            for try await result in group {
                results.append(result)
            }
            
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    private func performCompression(_ data: Data, algorithm: compression_algorithm) throws -> Data {
        let pageSize = configuration.bufferSize
        var compressedData = Data()
        
        let sourceData = data
        var sourceIndex = 0
        
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: pageSize)
        defer { destinationBuffer.deallocate() }
        
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        
        var status = compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, algorithm)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw CompressionError.initializationFailed
        }
        defer { compression_stream_destroy(stream) }
        
        stream.pointee.dst_ptr = destinationBuffer
        stream.pointee.dst_size = pageSize
        
        while true {
            // Fill source buffer
            let sourceChunkSize = min(pageSize, sourceData.count - sourceIndex)
            
            if sourceChunkSize > 0 {
                sourceData.withUnsafeBytes { sourcePtr in
                    let ptr = sourcePtr.baseAddress!.advanced(by: sourceIndex)
                    stream.pointee.src_ptr = ptr.assumingMemoryBound(to: UInt8.self)
                    stream.pointee.src_size = sourceChunkSize
                }
            }
            
            let flags: Int32 = sourceIndex + sourceChunkSize >= sourceData.count ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            
            status = compression_stream_process(stream, flags)
            
            switch status {
            case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                let outputSize = pageSize - stream.pointee.dst_size
                if outputSize > 0 {
                    compressedData.append(destinationBuffer, count: outputSize)
                }
                
                if status == COMPRESSION_STATUS_END {
                    return compressedData
                }
                
                // Reset destination buffer
                stream.pointee.dst_ptr = destinationBuffer
                stream.pointee.dst_size = pageSize
                
                // Advance source index
                sourceIndex += sourceChunkSize - stream.pointee.src_size
                
            case COMPRESSION_STATUS_ERROR:
                throw CompressionError.compressionFailed
                
            default:
                throw CompressionError.unknownError
            }
        }
    }
    
    // MARK: - Decompression
    
    /// Decompress data
    public func decompress(_ compressedData: CompressedData) throws -> Data {
        guard compressedData.isCompressed, let algorithm = compressedData.algorithm else {
            return compressedData.data
        }
        
        let nativeAlgo = nativeAlgorithm(for: algorithm)
        return try performDecompression(compressedData.data, algorithm: nativeAlgo, originalSize: compressedData.originalSize)
    }
    
    /// Decompress data asynchronously
    public func decompressAsync(_ compressedData: CompressedData) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let result = try self.decompress(compressedData)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Decompress raw data with specified algorithm
    public func decompress(_ data: Data, algorithm: CompressionAlgorithm, originalSize: Int) throws -> Data {
        let nativeAlgo = nativeAlgorithm(for: algorithm)
        return try performDecompression(data, algorithm: nativeAlgo, originalSize: originalSize)
    }
    
    private func performDecompression(_ data: Data, algorithm: compression_algorithm, originalSize: Int) throws -> Data {
        let pageSize = configuration.bufferSize
        var decompressedData = Data()
        decompressedData.reserveCapacity(originalSize)
        
        var sourceIndex = 0
        
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: pageSize)
        defer { destinationBuffer.deallocate() }
        
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        
        var status = compression_stream_init(stream, COMPRESSION_STREAM_DECODE, algorithm)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw CompressionError.initializationFailed
        }
        defer { compression_stream_destroy(stream) }
        
        stream.pointee.dst_ptr = destinationBuffer
        stream.pointee.dst_size = pageSize
        
        while true {
            // Fill source buffer
            let sourceChunkSize = min(pageSize, data.count - sourceIndex)
            
            if sourceChunkSize > 0 {
                data.withUnsafeBytes { sourcePtr in
                    let ptr = sourcePtr.baseAddress!.advanced(by: sourceIndex)
                    stream.pointee.src_ptr = ptr.assumingMemoryBound(to: UInt8.self)
                    stream.pointee.src_size = sourceChunkSize
                }
            }
            
            let flags: Int32 = sourceIndex + sourceChunkSize >= data.count ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            
            status = compression_stream_process(stream, flags)
            
            switch status {
            case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                let outputSize = pageSize - stream.pointee.dst_size
                if outputSize > 0 {
                    decompressedData.append(destinationBuffer, count: outputSize)
                }
                
                if status == COMPRESSION_STATUS_END {
                    return decompressedData
                }
                
                // Reset destination buffer
                stream.pointee.dst_ptr = destinationBuffer
                stream.pointee.dst_size = pageSize
                
                // Advance source index
                sourceIndex += sourceChunkSize - stream.pointee.src_size
                
            case COMPRESSION_STATUS_ERROR:
                throw CompressionError.decompressionFailed
                
            default:
                throw CompressionError.unknownError
            }
        }
    }
    
    // MARK: - Utilities
    
    private func nativeAlgorithm(for algorithm: CompressionAlgorithm) -> compression_algorithm {
        switch algorithm {
        case .lz4:
            return COMPRESSION_LZ4
        case .zlib:
            return COMPRESSION_ZLIB
        case .lzma:
            return COMPRESSION_LZMA
        case .lzfse:
            return COMPRESSION_LZFSE
        }
    }
    
    /// Estimate compressed size
    public func estimateCompressedSize(_ data: Data) -> Int {
        switch configuration.algorithm {
        case .lz4:
            return Int(Double(data.count) * 0.5) // ~50% compression typical
        case .zlib:
            return Int(Double(data.count) * 0.4) // ~40% compression typical
        case .lzma:
            return Int(Double(data.count) * 0.3) // ~30% compression typical
        case .lzfse:
            return Int(Double(data.count) * 0.45) // ~45% compression typical
        }
    }
    
    /// Get compression statistics
    public func statistics(for compressedData: CompressedData) -> CompressionStatistics {
        return CompressionStatistics(
            originalSize: compressedData.originalSize,
            compressedSize: compressedData.compressedSize,
            compressionRatio: compressedData.compressionRatio,
            spaceSaved: compressedData.originalSize - compressedData.compressedSize,
            algorithm: compressedData.algorithm
        )
    }
}

// MARK: - Supporting Types

public struct CompressedData: Codable, Sendable {
    public let data: Data
    public let algorithm: CompressionAlgorithm?
    public let originalSize: Int
    public let compressedSize: Int
    public let compressionRatio: Double
    public let isCompressed: Bool
    
    public init(
        data: Data,
        algorithm: CompressionAlgorithm?,
        originalSize: Int,
        compressedSize: Int,
        compressionRatio: Double,
        isCompressed: Bool
    ) {
        self.data = data
        self.algorithm = algorithm
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.compressionRatio = compressionRatio
        self.isCompressed = isCompressed
    }
}

public struct CompressionStatistics: Sendable {
    public let originalSize: Int
    public let compressedSize: Int
    public let compressionRatio: Double
    public let spaceSaved: Int
    public let algorithm: CompressionAlgorithm?
    
    public var spaceSavedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(spaceSaved) / Double(originalSize) * 100
    }
    
    public var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(originalSize), countStyle: .binary)
    }
    
    public var formattedCompressedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(compressedSize), countStyle: .binary)
    }
}

public enum CompressionError: Error, LocalizedError {
    case initializationFailed
    case compressionFailed
    case decompressionFailed
    case invalidData
    case unknownError
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize compression stream"
        case .compressionFailed:
            return "Compression operation failed"
        case .decompressionFailed:
            return "Decompression operation failed"
        case .invalidData:
            return "Invalid data format"
        case .unknownError:
            return "Unknown compression error"
        }
    }
}

// MARK: - Streaming Compression

/// Stream-based compression for large files
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class CompressionStream: @unchecked Sendable {
    
    private let engine: CompressionEngine
    private var buffer = Data()
    private let chunkSize: Int
    
    public init(configuration: CompressionConfiguration = .default, chunkSize: Int = 65536) {
        self.engine = CompressionEngine(configuration: configuration)
        self.chunkSize = chunkSize
    }
    
    /// Compress file at URL
    public func compressFile(at source: URL, to destination: URL) async throws -> CompressionStatistics {
        let sourceData = try Data(contentsOf: source)
        let compressed = try await engine.compressAsync(sourceData)
        try compressed.data.write(to: destination)
        return engine.statistics(for: compressed)
    }
    
    /// Decompress file at URL
    public func decompressFile(at source: URL, to destination: URL, originalSize: Int, algorithm: CompressionAlgorithm) async throws {
        let sourceData = try Data(contentsOf: source)
        let decompressed = try engine.decompress(sourceData, algorithm: algorithm, originalSize: originalSize)
        try decompressed.write(to: destination)
    }
}
