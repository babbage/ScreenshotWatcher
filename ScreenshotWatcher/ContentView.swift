import SwiftUI

@MainActor // @MainActor required because count is @Published
class ViewModel: ObservableObject {
    @Published var count = 0
    let screenshotNotifications = NotificationCenter.default.notifications(named: UIApplication.userDidTakeScreenshotNotification)
    var screenshotMonitor: Task<(), Never>?
    
    init() {
        Task { await monitorForScreenshots() }
    }

    func monitorForScreenshots() async {
        screenshotMonitor = Task {
            for await _ in screenshotNotifications {
                self.count += 1
            }
        }
    }
    
    func cancelMonitoring() {
        screenshotMonitor?.cancel()
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Text("\(viewModel.count) screenshots have been taken")
    }
    
    init() {
        self.viewModel = ViewModel()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
