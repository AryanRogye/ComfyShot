//
//  TaskQueue.swift
//  ComfyShot
//
//  Created by Aryan Rogye on 9/8/26.
//

/// A thread-safe, serial task queue that executes asynchronous closures in FIFO order.
actor TaskQueue {
    private let continuation: AsyncStream<@Sendable () async -> Void>.Continuation

    init() {
        /// Create an AsyncStream that yields blocks of async code
        let (stream, continuation) = AsyncStream<@Sendable () async -> Void>.makeStream()
        self.continuation = continuation

        /// Start the background loop to process items sequentially
        Task {
            for await workItem in stream {
                await workItem()
            }
        }
    }

    /// Enqueues a new asynchronous task to be executed sequentially.
    /// - Parameter block: The asynchronous code closure to run.
    nonisolated func enqueue(_ block: @escaping @Sendable () async -> Void) {
        continuation.yield(block)
    }
}
