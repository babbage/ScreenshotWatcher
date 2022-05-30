import XCTest
import SwiftUI
@testable import ScreenshotWatcher

class ScreenshotWatcherTests: XCTestCase {

func testA_defaultRespondToScreenshotAction_incrementsViewModelCount() async throws {
    // Executed 100000 tests, with 0 failures (0 unexpected) in 293.792 (512.494) seconds
    
    // Setup
    let viewModel = ViewModel()
    let defaultScreenshotAction = ContentView.Actions.defaultRespondToScreenshot(for: viewModel)

    // Verify baseline value
    await MainActor.run { XCTAssertEqual(viewModel.count, 0) }
    
    // Code under test
    await defaultScreenshotAction()
    
    // Test expectations
    await MainActor.run { XCTAssertEqual(viewModel.count, 1) }
}

func testB_defaultOnDisplayAction_callsSuppliedScreenshotAction_whenScreenshotNotificationPosted() async throws {
    // Reliably passes when run once. When run repeatedly, rapidly triggers issues between
    // NotificationCentre and expectation.fulfillment so not recommended to run repeatedly.
    
    // Actions and expectation
    let expectation = self.expectation(description: "screenshotAction called.")
    let fulfillExpectation = { expectation.fulfill() }
    let actions = ContentView.Actions(
        onDisplay: ContentView.Actions.defaultOnDisplay(screenshotAction: fulfillExpectation)
    )

    // Initiate the process created by the onDisplay action
    let asyncSequence = Task { await actions.onDisplay() }
    
    // Post the notification created when a screenshot occurs.
    _ = await MainActor.run {
        Task {
            NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        }
    }
    
    // Test expectations
    await self.waitForExpectations(timeout: 1)
    asyncSequence.cancel()
}

func testC_onDisplayActionIsCalled_whenContentViewIsDisplayed() async {
    // Executed 100000 tests, with 0 failures (0 unexpected) in 705.619 (839.864) seconds
    
    // Actions and expectation
    let expectation = self.expectation(description: "onDisplay Action called.")
    let actions = ContentView.Actions(
        onDisplay: { expectation.fulfill() }
    )

    // Create content view
    let viewModel = ViewModel()
    let contentView = await ContentView(viewModel: viewModel, actions: actions)

    // Process being tested
    await display(contentView)

    // Test expectations
    await waitForExpectations(timeout: 1)
}

private func display(_ contentView: ContentView) async {
    await MainActor.run {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        let hostingController = UIHostingController(rootView: contentView)
        window.rootViewController?.view.addSubview(hostingController.view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }
}

}
