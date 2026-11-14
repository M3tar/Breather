import AppKit
@preconcurrency import MetalKit

/// On-demand native snapshot support. Ordinary playback does no readback.
@MainActor protocol MetalViewSnapshotProviding: AnyObject {
    func captureMetalImage() async throws -> MetalViewSnapshot.Frame
}

@MainActor enum MetalViewSnapshot {
    struct Frame {
        let image: CGImage
        let maximumWorkMS: Double
    }
    static func capture(queue: MTLCommandQueue, size: CGSize, pixelFormat: MTLPixelFormat,
                        encode: (MTLRenderCommandEncoder) -> Void) async throws -> MetalViewSnapshot.Frame {
        let encodeStarted = CACurrentMediaTime()
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
              size.width * size.height <= 4_194_304 else { throw Failure.unavailable }
        let width = Int(size.width), height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
            width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .shared
        guard let texture = queue.device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer()
        else { throw Failure.unavailable }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.unavailable }
        encode(encoder); encoder.endEncoding()
        let encodeMS = (CACurrentMediaTime() - encodeStarted) * 1000
        let waiter = Completion()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.continuation = continuation
                waiter.timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    waiter.finish(.failure(Failure.unavailable))
                }
                buffer.addCompletedHandler { command in
                    let succeeded = command.status == .completed
                    Task { @MainActor in waiter.finish(succeeded ? .success(()) : .failure(Failure.unavailable)) }
                }
                buffer.commit()
            }
        } onCancel: {
            Task { @MainActor in waiter.finish(.failure(CancellationError())) }
        }
        try Task.checkCancellation()
        let readStarted = CACurrentMediaTime()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw Failure.unavailable }
        return Frame(image: image, maximumWorkMS: max(encodeMS, (CACurrentMediaTime() - readStarted) * 1000))
    }
    enum Failure: Error { case unavailable }
    @MainActor private final class Completion {
        var continuation: CheckedContinuation<Void, Error>?
        var timeout: Task<Void, Never>?
        func finish(_ result: Result<Void, Error>) {
            timeout?.cancel(); timeout = nil
            let pending = continuation; continuation = nil; pending?.resume(with: result)
        }
    }
}
