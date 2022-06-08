import XCTest
@testable import ScreenshotWatcher

class ScreenshotWatcherTests: XCTestCase {
    
    // Executed 1000000 tests, with 0 failures (0 unexpected) in 2274.146 (3139.190) seconds
    func test_selfInitializedViewModel_doesNotDisplayRaceCondition() async throws {
        // Initialize the ViewModel
        let viewModel = await ViewModel()
        
        // Baseline expectations
        await MainActor.run { // MainActor.run required because ViewModel is @MainActor given @Published count
            XCTAssertEqual(viewModel.count, 0, "Expected 0 count, found \(viewModel.count)")
        }
        
        // Post the notification created when a screenshot occurs, then wait till it has been issued.
        _ = await expectation(forNotification: UIApplication.userDidTakeScreenshotNotification, object: nil)
        await NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        await waitForExpectations(timeout: 5)
        
        // Test expectations
        await MainActor.run { // MainActor.run required because ViewModel is @MainActor given @Published count
            XCTAssertEqual(viewModel.count, 1, "Expected 1 count, found \(viewModel.count)")
        }
        
        // Cleanup
        await viewModel.cancelMonitoring()
    }
    
    // Executed 100000 tests, with 0 failures (0 unexpected) in 138.589 (203.695) seconds
    func test_notificationCentreNotifications_doesNotDisplayRaceCondition() async throws {
        // Setup test expectation
        let expectation = self.expectation(description: "Notification received.")
        let fulfillExpectation = { expectation.fulfill() }
        
        // Initiate the NotificationCentre.Notifications AsyncSequence
        let asyncSequenceTask = Task {
            let screenshotSequence = await NotificationCenter.default.notifications(
                named: UIApplication.userDidTakeScreenshotNotification
            )
            for await _ in screenshotSequence {
                fulfillExpectation()
            }
        }
        
        // Post the notification created when a screenshot occurs.
        _ = await MainActor.run {
            Task.detached(priority:.userInitiated, operation: {
                await NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
            })
        }
        
        // Test expectations
        await self.waitForExpectations(timeout: 10)
        asyncSequenceTask.cancel()
    }
    
}
