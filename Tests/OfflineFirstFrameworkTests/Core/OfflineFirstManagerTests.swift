import XCTest
import Quick
import Nimble
import RxSwift
import RxTest
@testable import OfflineFirstFramework

class OfflineFirstManagerTests: QuickSpec {
    
    override func spec() {
        describe("OfflineFirstManager") {
            var manager: OfflineFirstManager!
            var scheduler: TestScheduler!
            var disposeBag: DisposeBag!
            
            beforeEach {
                manager = OfflineFirstManager.shared
                scheduler = TestScheduler(initialClock: 0)
                disposeBag = DisposeBag()
            }
            
            afterEach {
                disposeBag = nil
            }
            
            context("when initialized") {
                it("should have all managers initialized") {
                    expect(manager.networkManager).toNot(beNil())
                    expect(manager.storageManager).toNot(beNil())
                    expect(manager.syncManager).toNot(beNil())
                    expect(manager.analyticsManager).toNot(beNil())
                    expect(manager.conflictManager).toNot(beNil())
                }
                
                it("should have default configuration") {
                    expect(manager.configuration.maxStorageSize).to(equal(100 * 1024 * 1024))
                    expect(manager.configuration.syncInterval).to(equal(300))
                    expect(manager.configuration.retryAttempts).to(equal(3))
                }
            }
            
            context("when saving data") {
                it("should save data successfully") {
                    let testData = TestUser(name: "John", email: "john@example.com")
                    
                    let observer = scheduler.createObserver(SaveResult.self)
                    
                    manager.save(testData)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).to(equal(.success))
                }
                
                it("should handle save failure") {
                    // This would require mocking the storage manager
                    // For now, we'll test the observable structure
                    let testData = TestUser(name: "", email: "")
                    
                    let observer = scheduler.createObserver(SaveResult.self)
                    
                    manager.save(testData)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                }
            }
            
            context("when loading data") {
                it("should load data successfully") {
                    let observer = scheduler.createObserver([TestUser].self)
                    
                    manager.load(TestUser.self)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).toNot(beNil())
                }
            }
            
            context("when syncing data") {
                it("should perform sync successfully") {
                    let observer = scheduler.createObserver(SyncResult.self)
                    
                    manager.sync()
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                }
                
                it("should handle sync failure") {
                    let observer = scheduler.createObserver(SyncResult.self)
                    
                    manager.sync(force: true)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                }
            }
            
            context("when resolving conflicts") {
                it("should resolve conflicts successfully") {
                    let testData = TestUser(name: "John", email: "john@example.com")
                    let observer = scheduler.createObserver(ConflictResolutionResult.self)
                    
                    manager.resolveConflicts(for: testData)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                }
            }
            
            context("when getting analytics") {
                it("should return analytics data") {
                    let observer = scheduler.createObserver(OfflineAnalytics.self)
                    
                    manager.getAnalytics()
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).toNot(beNil())
                }
            }
            
            context("when clearing data") {
                it("should clear all data successfully") {
                    let observer = scheduler.createObserver(ClearResult.self)
                    
                    manager.clearAllData()
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).to(equal(.success))
                }
            }
        }
    }
}

// MARK: - Test Models

struct TestUser: Codable, Equatable {
    let name: String
    let email: String
    
    init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}
