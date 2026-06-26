// ClaudeMonitor/Data/FSEventWatcher.swift
import Foundation

final class FSEventWatcher {
    private var stream: FSEventStreamRef?

    // handler: 변경된 .jsonl 파일의 URL
    init(path: URL, handler: @escaping (URL) -> Void) {
        let paths = [path.path as CFString] as CFArray
        let selfPtr = Unmanaged.passRetained(Box(handler))

        var ctx = FSEventStreamContext(
            version: 0,
            info: selfPtr.toOpaque(),
            retain: nil,
            release: { Unmanaged<Box<(URL) -> Void>>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            let box = Unmanaged<Box<(URL) -> Void>>.fromOpaque(info!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            for i in 0..<numEvents {
                guard let p = paths[i] as? String else { continue }
                let url = URL(fileURLWithPath: p)
                if url.pathExtension == "jsonl" {
                    box.value(url)
                }
            }
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // 0.5초 debounce
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )
        if let s = stream {
            FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(s)
        }
    }

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}

// Swift 클로저를 UnsafeMutableRawPointer 로 전달하기 위한 래퍼
private final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
