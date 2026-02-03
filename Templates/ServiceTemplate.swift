// MARK: - Offline-First Service Template
// Use this template for creating Offline-First Services

import Foundation
import CoreData

// MARK: - Local Store Protocol
protocol LocalStoreProtocol: Sendable {
    func fetchAll<T: SyncableModel>() async -> [T]
    func fetch<T: SyncableModel>(id: String) async -> T?
    func save<T: SyncableModel>(_ item: T) async
    func delete(_ id: String) async
    func updateSyncStatus(_ id: String, status: SyncStatus, remoteId: String?) async
    func applyRemoteChange<T: SyncableModel>(_ change: RemoteChange<T>) async
}

// MARK: - Local Store Implementation
final class __NAME__LocalStore: LocalStoreProtocol, @unchecked Sendable {
    // MARK: - Singleton
    static let shared = __NAME__LocalStore()
    
    // MARK: - Core Data Stack
    private let container: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext
    
    // MARK: - Initialization
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "__NAME__")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data: \(error)")
            }
        }
        
        backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Fetch All
    func fetchAll<T: SyncableModel>() async -> [T] {
        await backgroundContext.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: T.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
            
            do {
                let results = try self.backgroundContext.fetch(request)
                return results.compactMap { T(managedObject: $0) }
            } catch {
                print("Fetch error: \(error)")
                return []
            }
        }
    }
    
    // MARK: - Fetch Single
    func fetch<T: SyncableModel>(id: String) async -> T? {
        await backgroundContext.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: T.entityName)
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1
            
            do {
                let results = try self.backgroundContext.fetch(request)
                return results.first.flatMap { T(managedObject: $0) }
            } catch {
                return nil
            }
        }
    }
    
    // MARK: - Save
    func save<T: SyncableModel>(_ item: T) async {
        await backgroundContext.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: T.entityName)
            request.predicate = NSPredicate(format: "id == %@", item.id)
            
            do {
                let existing = try self.backgroundContext.fetch(request).first
                let object = existing ?? NSEntityDescription.insertNewObject(
                    forEntityName: T.entityName,
                    into: self.backgroundContext
                )
                
                item.populate(managedObject: object)
                try self.backgroundContext.save()
            } catch {
                print("Save error: \(error)")
            }
        }
    }
    
    // MARK: - Delete
    func delete(_ id: String) async {
        await backgroundContext.perform {
            // Create tombstone for sync
            let tombstone = NSEntityDescription.insertNewObject(
                forEntityName: "Tombstone",
                into: self.backgroundContext
            )
            tombstone.setValue(id, forKey: "deletedId")
            tombstone.setValue(Date(), forKey: "deletedAt")
            
            // Delete actual object
            let request = NSFetchRequest<NSManagedObject>(entityName: "__TYPE__Entity")
            request.predicate = NSPredicate(format: "id == %@", id)
            
            do {
                if let object = try self.backgroundContext.fetch(request).first {
                    self.backgroundContext.delete(object)
                }
                try self.backgroundContext.save()
            } catch {
                print("Delete error: \(error)")
            }
        }
    }
    
    // MARK: - Update Sync Status
    func updateSyncStatus(_ id: String, status: SyncStatus, remoteId: String? = nil) async {
        await backgroundContext.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "__TYPE__Entity")
            request.predicate = NSPredicate(format: "id == %@", id)
            
            do {
                if let object = try self.backgroundContext.fetch(request).first {
                    object.setValue(status.rawValue, forKey: "syncStatus")
                    if let remoteId = remoteId {
                        object.setValue(remoteId, forKey: "remoteId")
                    }
                    try self.backgroundContext.save()
                }
            } catch {
                print("Update sync status error: \(error)")
            }
        }
    }
    
    // MARK: - Apply Remote Change
    func applyRemoteChange<T: SyncableModel>(_ change: RemoteChange<T>) async {
        await backgroundContext.perform {
            switch change {
            case .created(let item), .updated(let item):
                let request = NSFetchRequest<NSManagedObject>(entityName: T.entityName)
                request.predicate = NSPredicate(format: "remoteId == %@", item.remoteId ?? "")
                
                do {
                    let existing = try self.backgroundContext.fetch(request).first
                    
                    // Check for conflicts (local modification newer than remote)
                    if let existingModified = existing?.value(forKey: "modifiedAt") as? Date,
                       existingModified > item.modifiedAt {
                        // Keep local version, mark as conflict
                        existing?.setValue(SyncStatus.conflict.rawValue, forKey: "syncStatus")
                        try self.backgroundContext.save()
                        return
                    }
                    
                    let object = existing ?? NSEntityDescription.insertNewObject(
                        forEntityName: T.entityName,
                        into: self.backgroundContext
                    )
                    
                    item.populate(managedObject: object)
                    object.setValue(SyncStatus.synced.rawValue, forKey: "syncStatus")
                    try self.backgroundContext.save()
                } catch {
                    print("Apply remote change error: \(error)")
                }
                
            case .deleted(let remoteId):
                let request = NSFetchRequest<NSManagedObject>(entityName: T.entityName)
                request.predicate = NSPredicate(format: "remoteId == %@", remoteId)
                
                do {
                    if let object = try self.backgroundContext.fetch(request).first {
                        self.backgroundContext.delete(object)
                        try self.backgroundContext.save()
                    }
                } catch {
                    print("Apply delete error: \(error)")
                }
            }
        }
    }
}

// MARK: - Sync Status
enum SyncStatus: String {
    case pending
    case syncing
    case synced
    case conflict
    case failed
}

// MARK: - Syncable Model Protocol
protocol SyncableModel: Codable, Sendable {
    var id: String { get set }
    var remoteId: String? { get set }
    var syncStatus: SyncStatus { get set }
    var createdAt: Date { get set }
    var modifiedAt: Date { get set }
    
    static var entityName: String { get }
    init?(managedObject: NSManagedObject)
    func populate(managedObject: NSManagedObject)
}

// MARK: - Remote Change
enum RemoteChange<T: SyncableModel> {
    case created(T)
    case updated(T)
    case deleted(String) // remoteId
}

// MARK: - Change Type
enum ChangeType<T: SyncableModel> {
    case create(T)
    case update(T)
    case delete(String)
}
