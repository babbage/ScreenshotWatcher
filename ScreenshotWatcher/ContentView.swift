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
