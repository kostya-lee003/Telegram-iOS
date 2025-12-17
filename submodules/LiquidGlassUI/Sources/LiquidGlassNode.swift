import UIKit
import AsyncDisplayKit
import MetalKit

public protocol LiquidGlassCaptureSource: AnyObject {
    /// rectInWindow: область в координатах UIWindow, которую надо захватить
    func capture(rectInWindow: CGRect, scale: CGFloat) -> CGImage?
}

/// Базовый вариант: захват из UIWindow (универсально для любого контента под нодой)
public final class WindowCaptureSource: LiquidGlassCaptureSource {
    private weak var window: UIWindow?

    public init(window: UIWindow) {
        self.window = window
    }

    public func capture(rectInWindow: CGRect, scale: CGFloat) -> CGImage? {
        guard let window else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(size: rectInWindow.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rectInWindow.origin.x, y: -rectInWindow.origin.y)
            // drawHierarchy часто даёт более “похожий” на реальность результат, чем layer.render
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.cgImage
    }
}

public enum LiquidGlassShape {
    case circle
    case roundedRect(cornerRadius: CGFloat) // в поинтах
}

public struct LiquidGlassConfiguration {
    public var maxFPS: Double = 60.0
    public var downscale: CGFloat = 0.6

    public var refraction: Float = 0.12
    public var chroma: Float = 0.10

    public var shadowOffset: Float = 10.0   // px (в текстуре)
    public var shadowBlur: Float = 18.0     // px
    public var shadowStrength: Float = 0.06 // 0..1

    public var rimThickness: Float = 1.5    // px
    public var rimStrength: Float = 0.9     // 0..1
    public var lightDir: SIMD2<Float> = .init(-0.5, -0.8) // верх-лево

    public var alpha: Float = 1.0

    public init() {}
}

public final class LiquidGlassNode: ASDisplayNode {

    public enum UpdateMode {
        case idleOneShot   // один кадр и стоп
        case continuous    // пока явно не остановим
    }
    
    // MARK: Public API

    public var configuration: LiquidGlassConfiguration = .init() {
        didSet { renderer?.configuration = configuration }
    }

    public var shape: LiquidGlassShape = .circle {
        didSet { renderer?.shape = shape }
    }

    /// Источник снапшота (обычно UIWindow)
    public weak var captureSource: LiquidGlassCaptureSource?
    
    public var updateMode: UpdateMode = .idleOneShot

    private var pendingOneShot = false


    // MARK: Private

    private var mtkView: MTKView?
    private var renderer: LiquidGlassRenderer?

    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    public override init() {
        super.init()
        self.isLayerBacked = false

        setViewBlock { [weak self] in
            let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
            view.isOpaque = false
            view.backgroundColor = .clear
            view.clearColor = MTLClearColorMake(0, 0, 0, 0)
            view.framebufferOnly = false

            view.enableSetNeedsDisplay = true   // ✅ было false :contentReference[oaicite:3]{index=3}
            view.isPaused = true               // ✅ оставляем true

            self?.mtkView = view
            return view
        }
    }

    public override func didLoad() {
        super.didLoad()
        guard let mtkView = self.mtkView else { return }
        let renderer = LiquidGlassRenderer(mtkView: mtkView)
        renderer.configuration = configuration
        renderer.shape = shape
        self.renderer = renderer
    }

    deinit {
        stop()
    }
    
    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        lastTick = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    
    public func start() {
        guard displayLink == nil else { return }
        lastTick = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let mtkView, let renderer else { stop(); return }
        guard let captureSource else { stop(); return }
        guard let window = view.window else { stop(); return }

        // если idle и нет запроса — сразу стоп
        let shouldRun = (updateMode == .continuous) || pendingOneShot
        guard shouldRun else {
            stop()
            return
        }

        let now = CACurrentMediaTime()
        let minDelta = 1.0 / max(configuration.maxFPS, 1.0)
        if lastTick != 0, (now - lastTick) < minDelta { return }
        lastTick = now

        pendingOneShot = false

        let rectInWindow = view.convert(view.bounds, to: window)
        let scale = (window.screen.scale * configuration.downscale)

        if let cgImage = captureSource.capture(rectInWindow: rectInWindow, scale: scale) {
            renderer.updateBackground(cgImage: cgImage)
            mtkView.setNeedsDisplay()
        }

        if updateMode == .idleOneShot {
            stop()
        }
    }
    
    public func requestOneShotUpdate() {
        pendingOneShot = true
        ensureDisplayLink()
    }

    public func beginContinuousUpdates() {
        updateMode = .continuous
        ensureDisplayLink()
    }

    public func endContinuousUpdates(finalOneShot: Bool = true) {
        updateMode = .idleOneShot
        if finalOneShot {
            requestOneShotUpdate()
        } else {
            stop()
        }
    }

}

