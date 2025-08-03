import Foundation
import OfflineFirstFramework

// Example usage of iOS Offline First Framework
print("iOS Offline First Framework Example")

// Initialize the framework
let config = OfflineFirstConfiguration()
OfflineFirstManager.shared.initialize(with: config)

// Example user data
struct User: Codable {
    let id: String
    let name: String
    let email: String
    let createdAt: Date
}

// Create sample user
let user = User(
    id: UUID().uuidString,
    name: "John Doe",
    email: "john@example.com",
    createdAt: Date()
)

// Save user data offline
print("Saving user data...")
OfflineFirstManager.shared.save(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ User saved successfully")
        case .failure(let error):
            print("❌ Failed to save user: \(error)")
        case .conflict(let error):
            print("⚠️ Conflict detected: \(error)")
        }
    })
    .disposed(by: DisposeBag())

// Load saved users
print("Loading saved users...")
OfflineFirstManager.shared.load(User.self)
    .subscribe(onNext: { users in
        print("📱 Found \(users.count) users")
        for user in users {
            print("- \(user.name) (\(user.email))")
        }
    })
    .disposed(by: DisposeBag())

// Monitor network status
print("Monitoring network status...")
OfflineFirstManager.shared.isOnline
    .subscribe(onNext: { isOnline in
        print("🌐 Network: \(isOnline ? "Online" : "Offline")")
    })
    .disposed(by: DisposeBag())

// Perform sync
print("Performing sync...")
OfflineFirstManager.shared.sync()
    .subscribe(onNext: { result in
        switch result {
        case .success(let syncedData):
            print("✅ Sync completed: \(syncedData.syncedItems) items synced")
        case .failure(let error):
            print("❌ Sync failed: \(error)")
        }
    })
    .disposed(by: DisposeBag())

// Get analytics
print("Getting analytics...")
OfflineFirstManager.shared.getAnalytics()
    .subscribe(onNext: { analytics in
        print("📊 Analytics:")
        print("- Offline sessions: \(analytics.offlineSessions)")
        print("- Sync success rate: \(analytics.syncSuccessRate)%")
        print("- Average sync time: \(analytics.averageSyncTime)s")
    })
    .disposed(by: DisposeBag())

print("Example completed!")
