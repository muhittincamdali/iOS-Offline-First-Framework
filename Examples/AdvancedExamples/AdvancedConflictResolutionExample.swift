import Foundation

/// Demonstrates a timestamp+vector-clock hybrid conflict resolution stub.
public struct ConflictResolver {
  public enum Resolution { case localWins, remoteWins, merged }
  public static func resolve(local: String, remote: String) -> Resolution {
    // Replace with real CRDT/OT strategy in production
    return local.count >= remote.count ? .localWins : .remoteWins
  }
}
