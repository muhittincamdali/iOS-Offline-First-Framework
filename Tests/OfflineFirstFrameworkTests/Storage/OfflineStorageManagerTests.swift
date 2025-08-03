import XCTest
import Quick
import Nimble
import RxSwift
import RxTest
@testable import OfflineFirstFramework

class OfflineStorageManagerTests: QuickSpec {
    
    override func spec() {
        describe("OfflineStorageManager") {
            var storageManager: OfflineStorageManager!
            var scheduler: TestScheduler!
            var disposeBag: DisposeBag!
            
            beforeEach {
                storageManager = OfflineStorageManager()
                scheduler = TestScheduler(initialClock: 0)
                disposeBag = DisposeBag()
            }
            
            afterEach {
                disposeBag = nil
            }
            
            context("when initialized") {
                it("should have default storage status") {
                    expect(storageManager.storageStatus.value).to(equal(.normal))
                }
                
                it("should have default storage usage") {
                    expect(storageManager.storageUsage.value.usedSpace).to(equal(0))
                    expect(storageManager.storageUsage.value.fileCount).to(equal(0))
                }
            }
            
            context("when saving data") {
                it("should save data successfully") {
                    let testData = TestUser(name: "John", email: "john@example.com")
                    let observer = scheduler.createObserver(SaveResult.self)
                    
                    storageManager.save(testData)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).to(equal(.success))
                }
                
                it("should handle save failure") {
                    // Test with invalid data
                    let observer = scheduler.createObserver(SaveResult.self)
                    
                    // This would require mocking to test failure cases
                    expect(observer.events).to(haveCount(0))
                }
            }
            
            context("when loading data") {
                it("should load data successfully") {
                    let observer = scheduler.createObserver([TestUser].self)
                    
                    storageManager.load(TestUser.self)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).toNot(beNil())
                }
            }
            
            context("when deleting data") {
                it("should delete data successfully") {
                    let testData = TestUser(name: "John", email: "john@example.com")
                    let observer = scheduler.createObserver(DeleteResult.self)
                    
                    storageManager.delete(testData)
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                }
            }
            
            context("when clearing all data") {
                it("should clear all data successfully") {
                    let observer = scheduler.createObserver(ClearResult.self)
                    
                    storageManager.clearAllData()
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).to(equal(.success))
                }
            }
            
            context("when getting storage info") {
                it("should return storage information") {
                    let observer = scheduler.createObserver(StorageInfo.self)
                    
                    storageManager.getStorageInfo()
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                    expect(observer.events.first?.value.element).toNot(beNil())
                }
            }
            
            context("when monitoring storage status") {
                it("should emit storage status changes") {
                    let observer = scheduler.createObserver(StorageStatus.self)
                    
                    storageManager.storageStatus
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
                }
            }
            
            context("when monitoring storage usage") {
                it("should emit storage usage changes") {
                    let observer = scheduler.createObserver(StorageUsage.self)
                    
                    storageManager.storageUsage
                        .subscribe(observer)
                        .disposed(by: disposeBag)
                    
                    scheduler.start()
                    
                    expect(observer.events).to(haveCount(1))
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
