import AVFoundation
import os

/// One decoded image and one main-thread drain at most. Network bursts never queue stale UI work.
final class VideoFramePresenter: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: (CMSampleBuffer, CGSize, Double)?
    private var scheduled = false
    private var stopped = false
    private var received = 0, replaced = 0
    private var displayed = 0
    private var reportTime = ProcessInfo.processInfo.systemUptime
    private var maxAge = 0.0
    private let layer: AVSampleBufferDisplayLayer
    private let onDisplay: (CGSize) -> Void
    private let logger = Logger(subsystem: "com.lopleec.androidmirror", category: "video")

    init(layer: AVSampleBufferDisplayLayer, onDisplay: @escaping (CGSize) -> Void) { self.layer = layer; self.onDisplay = onDisplay }
    func offer(_ sample: CMSampleBuffer, size: CGSize) {
        let shouldSchedule = lock.withLock {
            guard !stopped else { return false }
            received += 1
            if latest != nil { replaced += 1 }
            latest = (sample, size, ProcessInfo.processInfo.systemUptime)
            guard !scheduled else { return false }
            scheduled = true; return true
        }
        if shouldSchedule { DispatchQueue.main.async { [self] in drain() } }
    }
    func stop() { lock.withLock { stopped = true; latest = nil } }
    @MainActor private func drain() {
        guard !lock.withLock({ stopped }) else { return }
        if layer.status == .failed { layer.flush() }
        guard layer.isReadyForMoreMediaData else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [self] in drain() }
            return
        }
        let frame = lock.withLock { let frame = latest; latest = nil; scheduled = false; return frame }
        guard let (sample, size, arrival) = frame else { return }
        layer.enqueue(sample); onDisplay(size); displayed += 1
        let now = ProcessInfo.processInfo.systemUptime
        maxAge = max(maxAge, (now - arrival) * 1000)
        if now - reportTime >= 5 {
            let counters = lock.withLock { let result = (received, replaced); received = 0; replaced = 0; return result }
            let fps = Double(displayed) / (now - reportTime)
            logger.info("Video displayed_fps=\(fps, privacy: .public) received=\(counters.0, privacy: .public) replaced=\(counters.1, privacy: .public) max_local_queue_ms=\(self.maxAge, privacy: .public)")
            displayed = 0; maxAge = 0; reportTime = now
        }
    }
}
