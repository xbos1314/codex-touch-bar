import Darwin
import Foundation

final class FileSystemEventMonitor {
    private let url: URL
    private let eventMask: DispatchSource.FileSystemEvent
    private let queue: DispatchQueue
    private let onEvent: () -> Void
    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init(
        url: URL,
        eventMask: DispatchSource.FileSystemEvent,
        queue: DispatchQueue,
        onEvent: @escaping () -> Void
    ) {
        self.url = url
        self.eventMask = eventMask
        self.queue = queue
        self.onEvent = onEvent
    }

    @discardableResult
    func start() -> Bool {
        stop()

        let nextDescriptor = open(url.path, O_EVTONLY)
        guard nextDescriptor >= 0 else { return false }

        let nextSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: nextDescriptor,
            eventMask: eventMask,
            queue: queue
        )
        nextSource.setEventHandler(handler: onEvent)
        nextSource.setCancelHandler {
            close(nextDescriptor)
        }
        nextSource.resume()

        descriptor = nextDescriptor
        source = nextSource
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        stop()
    }
}
