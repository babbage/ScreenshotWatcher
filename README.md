# ScreenshotWatcher

_This ReadMe contains Duncan Babbage's contribution to the [discussion on these issues at forums.swift.org](https://forums.swift.org/t/reliably-testing-code-that-adopts-swift-concurrency/57304/39) and on the original code example:_

This is going to be important as we increasingly adapt our code patterns to use new asynchronous facilities in Swift. This was an interesting discussion to read. So after mulling over it for a few days, I took a deep dive.

## Background observations
The code example in question is from one frame relatively simple but balances on the intersection of three somewhat unrelated components:

1. The feature being tested is the use of an `AsyncSequence` to respond to notifications over time. Testing `AsyncSequence` is considerably more complex than testing a normal async function, because an `AsyncSequence` does not return in the way a usual async function will when awaited.

2. There is a desire for the test to run in a serial, predictable manner, but the test is examining a response to an `NotificationCentre` post, the scheduling of which is not fully under the control of the application. 
3. The current structure of the code means that even if a test can demonstrate that the `task()` function on the `ViewModel` is called when the correct `NotificationCentre` message is posted, it is not currently possible to demonstrate that the production app is actually initializing this task when the `ContentView` is displayed. 

## `AsyncSequence` not Async-Await
I want to emphasise the first point. In the thread I noticed there are multiple references to testing ‘async/await code’. This is quite a misnomer here. The complexity here arises primary from using an `AsyncSequence` to respond to the notifications over time. With XCTest’s support for async test methods, it is trivally simple to create linear deterministic tests that await the results of an async method and then continue. The reason why this code is difficult to test pivots on the fact that you cannot `await` on an `AsyncSequence` in a test in the usual way as the test will never proceed forward to the subsequent `waitForExpectations`. It is key that the whole discussion in the thread above needs to be understood in that framework in my view—the discussion was mostly relevant to testing code that uses `AsyncSequence` not to testing async-await code in general. :)

## Combine would be better
The OP and others noted that it would be much easier to implement this code with Combine. In my view, that would definitely be a better way to implement this code, both for testability and other features that Combine provides. My take is this is not a good situation to reach for `AsyncSequence`, not just due to testability but due to suitability. Nonetheless, I’ve been mulling over the thread for several days and decided to sit down and lay out a way this could be made reliabily testable while still using AsyncSequence. Coming back today to try out some code I learned something in working through it, so that was good.

## Define separate testable components
To test more effective and reliably, we need to create separate testable components so that when all tests pass, we can be confident that the production code both has the intended effects, and (ideally) even that the SwiftUI views are verifably configured to correctly call those methods as expected at runtime.

In particular, it would ideal to be able to test three things:
1. Verify that when the default screenshot action is called, it increments the `viewModel.count`.
2. Verify that the supplied screenshot action is called, when the screenshot notification is posted.
3. Verify that `ContentView` is configured to call the `onDisplay` action, when it is displayed. 

With SwiftUI the last of these seems a lot more difficult—managing view lifetimes is largely out of our hands now—but maybe we can take a shot.

## Provide Actions via dependency injection
To achieve the above the first step is to dissociate the various parts of the process so that they are individually testable. To do this, we can use dependency injection to provide Actions to the ContentView, rather than the code for those actions residing within the ContentView (or ViewModel) itself. We can provide default implementations of these Actions alongside the definition of the actions that will used in production. This will enable us to however replace individual actions with test expectations as needed to test each component of the system.  This is a [pattern from John Sundell](https://swiftbysundell.com/articles/dependency-injection-and-unit-testing-using-async-await/) I've adapted that I am using in my own app.

To do this, we will define a single Actions struct within the ContentView, that has a single property (“action”), `onDisplay`:

    struct Actions {
        // Actions the View takes in response to state changes or input.
        var onDisplay: () async -> Void
    }

An instance of Actions then becomes a required property on `ContentView`, with a modified initialiser that will automatically use the default `Actions(for: viewModel)` in production when an alternative implementation is not injected:

    init(viewModel: ViewModel = ViewModel(), actions: ContentView.Actions? = nil) {
        self.viewModel = viewModel
        self.actions = actions ?? Actions(for: viewModel)
    }

Instead of calling `task()` on the `ViewModel`, the `ContentView` now calls its `onDisplay` action when it loads:

    var body: some View {
        Text("\(viewModel.count) screenshots have been taken")
            .task { await actions.onDisplay() }
    }

The full architecture with the default actions in an extension are thus:

```
import SwiftUI

class ViewModel: ObservableObject {
    @Published @MainActor var count = 0
}

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel
    let actions: Actions

    var body: some View {
        Text("\(viewModel.count) screenshots have been taken")
            .task { await actions.onDisplay() }
    }
    
    init(viewModel: ViewModel = ViewModel(), actions: ContentView.Actions? = nil) {
        self.viewModel = viewModel
        self.actions = actions ?? Actions(for: viewModel)
    }

    struct Actions {
        // Actions the View takes in response to state changes or input. Pattern adapted from:
        // https://swiftbysundell.com/articles/dependency-injection-and-unit-testing-using-async-await/
        var onDisplay: () async -> Void
    }
}

extension ContentView.Actions {
    typealias AsyncFunction = () async -> Void
    
    // Default actions for production.
    // In this case, we define our default actions as static functions on the type because the
    // defaultOnDisplay action wishes to be able to call the defaultRespondToScreenshot action,
    // while that defaultRespondToScreenshot reuqires a reference to the ViewModel. In cases
    // where the functions are independent, simple closures could be passed to an init.
    static func defaultOnDisplay(screenshotAction: @escaping AsyncFunction) -> AsyncFunction {
        return {
            let screenshots = await NotificationCenter.default.notifications(
                named: UIApplication.userDidTakeScreenshotNotification
            )
            for await _ in screenshots {
                await screenshotAction()
            }
        }
    }

    static func defaultRespondToScreenshot(for viewModel: ViewModel) -> AsyncFunction {
        return {
            await MainActor.run {
                viewModel.count += 1
            }
        }
    }

    init (for viewModel: ViewModel) {
        let respondToScreenshot = ContentView.Actions.defaultRespondToScreenshot(for: viewModel)
        let onDisplay = ContentView.Actions.defaultOnDisplay(screenshotAction: respondToScreenshot)
        self.onDisplay = onDisplay
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = ViewModel()
        let defaultActions = ContentView.Actions(for: viewModel)
        ContentView(viewModel: viewModel, actions: defaultActions)
    }
}
```

(The typealias is of course not required but makes reading the function parameters a lot more comprehensible.)

Previously, the default code for when a screenshot was taken was to call `task()` on the `ViewModel`. Note this new implementation moves that code to instead be passed to the `onDisplay` action as a closure parameter. This will enable us to be able to replace this specific screenshot action task—separate from the functioning of the `AsyncSequence` code—in some tests. (We also do not put this action as an injectable property on the `ViewModel` because we would then need the `ViewModel` to instantiate this action while also needing this action to instantiate the `ViewModel`.)

## Testing the components
We are now able to write performant and reliable tests that validate the code as outlined earlier.

### 1. Verify that when the default screenshot action is called, it increments the viewModel count.
Now that the default screenshot action is a standalone function, we can test its effects directly, without neither the complication of the NotificationCentre post nor the AsyncSequence:

```
func testA_defaultRespondToScreenshotAction_incrementsViewModelCount() async throws {
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
```

This test is performant. On an i9 MacBook Pro (no Apple Silcon), it averaged about 0.003 seconds (3/1,000 of a second) to run:

> Executed 100000 tests, with 0 failures (0 unexpected) in 293.792 (512.494) seconds

Because the `ViewModel.count` is a published property for UI changes, we have asserted it should only be modified on the main thread hence the calls to `MainActor.run`. Otherwise, uncomplicated, and entirely linear.


### 2. Verify that the supplied screenshot action is called, when the screenshot notification is posted.
When we create an instance of `Actions`, using the default production implementation, we want to verify that it responds to the expected `NotificationCentre` post when one is issued, and that it will indeed call the screenshot action we supply to it for each of those posts. With this design we can now test both of these things independently of both the `ViewModel` and the `ContentView`, neither of which is needed for this test:

```
func testB_defaultOnDisplayAction_callsSuppliedScreenshotAction_whenScreenshotNotificationPosted() async throws {
    // Actions and expectation
    let expectation = self.expectation(description: "screenshotAction called.")
    let fulfillExpectation = { expectation.fulfill() }
    let actions = ContentView.Actions(
        onDisplay: ContentView.Actions.defaultOnDisplay(screenshotAction: fulfillExpectation)
    )

    // Initiate the process created by the onDisplay action
    Task { await actions.onDisplay() }
    
    // Post the notification created when a screenshot occurs.
    _ = await MainActor.run {
        Task {
            NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        }
    }
    
    // Test expectations
    await self.waitForExpectations(timeout: 10)
}
```

This test is fast (runs in about 0.005 seconds) and reliable—when run once at a time. However, when run repeatedly, this test rapidly triggers issues between NotificationCentre and expectation.fulfillment. After trying various things, my recommendation would simply be currently to not run this test repeatedly.  In my view, these are issues with the functioning of the NotificationCentre in a multithreaded environment and with XCTestExpectation, the tool we have been given to verify async code (including for completion handlers, pre async-await). It seems pointless to bang our heads here on repeated test runs. This reliably confirms for us that our action works and is wired up correctly to the expected notification. Take the win.

### 3. Verify that ContentView is configured to call the onDisplay action, when it is displayed. 

This is really the only necessary Integration Test here, in my view. However, I thought this would probably not be possible with a SwiftUI app and View, at least not without resorting to third party dependency extensions and complex code. But it sure would be good to lock in verification that our `onDisplay` action really was being fired off when that `ContentView` loaded—otherwise all our other tests are in vain, and we might have to resort to UITests or similar to continue to be sure that the view does indeed function as expected.

However, turns out, there is a way. And with just a short helper method, we can even have a clean, linear test too:

```
func testC_onDisplayActionIsCalled_whenContentViewIsDisplayed() async {
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
```

With the ability to inject a test expectation instead of the default onDisplay action, we can focus on how to instantiate a ContentView so that we can verify that it does call the onDisplay method. And after some trial an error, not that difficult! Put the `ContentView` in a `UIHostingController`, add it as a subview to a new `UIWindow`’s `rootViewController`, and lay it out.

The test method itself here looks much more like testing typical async-await code. We call the code being tested—`await display(contentView)`—and then we simply await to see if our test expectations are fulfilled. 

The test is again fast. Because people were revving engines in this thread, I again ran this method 100,000 times, finding an average execution time of 0.007 seconds. But I’m sure it’ll be noticably faster on an M1:

> Executed 100000 tests, with 0 failures (0 unexpected) in 705.619 (839.864) seconds

## Summary
* Super important to distinguish between testing AsyncSequence code, as described here, and standard async-await code. The latter will be much more common in our code bases.

* Using dependency injection to supply Actions to our Views and/or ViewModels is an outstanding way of separating concerns and making code eminently more testable, particularly in an async world.

* Well written tests can run fast. I really need to review some of my old tests as these ones smoke them.

* Maybe I need to set up a dev blog. 🤔😝
