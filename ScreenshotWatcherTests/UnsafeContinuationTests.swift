//
//  UnsafeContinuationTests.swift
//  ScreenshotWatcherTests
//
//  Created by Duncan Babbage on 31/05/22.
//

import XCTest

@MainActor
class UnsafeContinuationTests: XCTestCase {
    func testBasics() async throws {
        let vm = UnsafeViewModel()
        
        // Give the task an opportunity to start executing its work.
        let task = Task { await vm.task() }
        
        XCTAssertFalse(vm.didPost)
        
        vm.post()
        XCTAssertTrue(vm.didPost)
        
        task.cancel()
    }
}

class UnsafeViewModel: ObservableObject {
    @Published var didPost = false
    var continuation: UnsafeContinuation<Void, Never>?
    
    @MainActor
    func task() async {
        await withUnsafeContinuation { self.continuation = $0 }
        self.didPost = true
    }
    
    func post() {
        self.continuation?.resume()
    }
}
