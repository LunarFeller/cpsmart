import AppKit
import ImageIO

final class ThumbnailProvider {
    private typealias Completion = (NSImage?) -> Void

    private struct PendingRequest {
        let token: UUID
        var completions: [Completion]
    }

    private let maxPixelSize: CGFloat
    private let cache = NSCache<NSUUID, NSImage>()
    private let operationQueue: OperationQueue
    private let stateLock = NSLock()
    private var pendingRequests: [UUID: PendingRequest] = [:]

    init(maxPixelSize: CGFloat = 480) {
        self.maxPixelSize = maxPixelSize
        operationQueue = OperationQueue()
        operationQueue.name = "cpsmart.thumbnail-decoding"
        operationQueue.qualityOfService = .userInitiated
    }

    func thumbnail(for entry: ClipboardEntry, completion: @escaping (NSImage?) -> Void) {
        guard case .image(let data, _) = entry.payload else {
            completeOnMain(completion, image: nil)
            return
        }

        let cacheKey = entry.id as NSUUID
        if let cachedImage = cache.object(forKey: cacheKey) {
            completeOnMain(completion, image: cachedImage)
            return
        }

        stateLock.lock()
        if var pendingRequest = pendingRequests[entry.id] {
            pendingRequest.completions.append(completion)
            pendingRequests[entry.id] = pendingRequest
            stateLock.unlock()
            return
        }

        let token = UUID()
        pendingRequests[entry.id] = PendingRequest(token: token, completions: [completion])
        stateLock.unlock()

        operationQueue.addOperation { [weak self] in
            guard let self else { return }
            let image = Self.decodeThumbnail(from: data, maxPixelSize: self.maxPixelSize)
            if let image {
                self.cache.setObject(image, forKey: cacheKey)
            }
            self.finishRequest(for: entry.id, token: token, image: image)
        }
    }

    func cancelAll() {
        operationQueue.cancelAllOperations()
        stateLock.lock()
        pendingRequests.removeAll()
        stateLock.unlock()
    }

    private static func decodeThumbnail(from data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        // Always asks ImageIO for a downsampled image so the full source is never decoded first.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return NSImage(
            cgImage: thumbnail,
            size: NSSize(width: thumbnail.width, height: thumbnail.height)
        )
    }

    private func finishRequest(for id: UUID, token: UUID, image: NSImage?) {
        stateLock.lock()
        guard let pendingRequest = pendingRequests[id], pendingRequest.token == token else {
            stateLock.unlock()
            return
        }
        pendingRequests[id] = nil
        stateLock.unlock()

        DispatchQueue.main.async {
            pendingRequest.completions.forEach { $0(image) }
        }
    }

    private func completeOnMain(_ completion: @escaping Completion, image: NSImage?) {
        DispatchQueue.main.async {
            completion(image)
        }
    }
}
