import UIKit
import AsyncDisplayKit
import MetalKit

// For glass
public final class HidingWindowCaptureSource: LiquidGlassCaptureSource {
    private weak var window: UIWindow?
    private weak var viewToHide: UIView?
    public var afterScreenUpdates: Bool = true

    public init(window: UIWindow, viewToHide: UIView) {
        self.window = window
        self.viewToHide = viewToHide
    }

    public func capture(rectInWindow: CGRect, scale: CGFloat) -> CGImage? {
        guard let window else { return nil }

        let wasHidden = viewToHide?.isHidden ?? false
        let wasAlpha  = viewToHide?.alpha ?? 1.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        viewToHide?.isHidden = true
        viewToHide?.alpha    = 0.0
        CATransaction.commit()

        defer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            viewToHide?.isHidden = wasHidden
            viewToHide?.alpha    = wasAlpha
            CATransaction.commit()
        }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale  = scale

        let renderer = UIGraphicsImageRenderer(size: rectInWindow.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rectInWindow.origin.x,
                                      y: -rectInWindow.origin.y)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates)
        }

        return image.cgImage
    }
}


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
    
    /// Shared snapshot cache. Должен жить на уровне экрана/контроллера и шариться на все ноды.
    public weak var snapshotEnvironment: LiquidGlassSnapshotEnvironment?

    /// Margin вокруг rectInWindow, чтобы во время движения кроп всегда попадал в общий snapshot.
    public var snapshotMargin: UIEdgeInsets = .init(top: 18, left: 44, bottom: 18, right: 44)
    
    // MARK: Private

    private var mtkView: MTKView?
    private var renderer: LiquidGlassRenderer?

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

            view.enableSetNeedsDisplay = true
            view.isPaused = true

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
    
    public func renderCurrentFrame(now: CFTimeInterval = CACurrentMediaTime()) {
        guard let mtkView, let renderer else { return }
        guard let window = view.window else { return }

        let rectInWindow: CGRect
        if let pres = view.layer.presentation(), let superview = view.superview {
            rectInWindow = superview.convert(pres.frame, to: window)
        } else {
            rectInWindow = view.convert(view.bounds, to: window)
        }

        let scale = window.screen.scale * configuration.downscale

        var cgImage: CGImage?

        if let env = snapshotEnvironment {
            if env.captureSource == nil { env.captureSource = captureSource }
            cgImage = env.croppedImage(
                for: rectInWindow,
                scale: scale,
                margin: snapshotMargin,
                now: now
            )
        } else if let captureSource {
            cgImage = captureSource.capture(rectInWindow: rectInWindow, scale: scale)
        }

        if let cgImage {
            renderer.updateBackground(cgImage: cgImage)
            mtkView.setNeedsDisplay()
        }
    }
}





// MARK: - LiquidGlassSnapshotEnvironment


import UIKit

/// Shared snapshot cache: capture a larger region редко, crop маленький region часто.
public final class LiquidGlassSnapshotEnvironment {
    
    public struct Snapshot {
        public let cgImage: CGImage
        public let rectInWindow: CGRect   // points
        public let scale: CGFloat         // renderer scale used to create cgImage
        public let timestamp: CFTimeInterval
    }

    // MARK: - Public настройки

    /// Откуда берём картинку (обычно UIWindow через WindowCaptureSource / HidingWindowCaptureSource)
    public weak var captureSource: LiquidGlassCaptureSource?

    /// Лимит частоты обновления общего snapshot (кроп можно делать хоть 60fps)
    public var maxSnapshotFPS: Double = 50.0

    /// Запас вокруг области (в points), чтобы во время движения не выбегать за snapshot
    public var defaultMargin: UIEdgeInsets = .init(top: 18, left: 44, bottom: 18, right: 44)

    /// Текущий кеш
    public private(set) var snapshot: Snapshot?

    public init(captureSource: LiquidGlassCaptureSource? = nil) {
        self.captureSource = captureSource
    }

    // MARK: - API

    /// Прогреть snapshot под известную траекторию (например, union(fromFrame, toFrame) для анимации таба).
    @discardableResult
    public func prime(rectsInWindow: [CGRect], scale: CGFloat, margin: UIEdgeInsets? = nil) -> Bool {
        precondition(Thread.isMainThread)
        
        guard let captureSource else { return false }
        guard !rectsInWindow.isEmpty else { return false }

        let m = margin ?? defaultMargin
        let target = rectsInWindow
            .reduce(rectsInWindow[0]) { $0.union($1) }
            .insetBy(dx: 0, dy: 0)
            .inset(by: UIEdgeInsets(top: -m.top, left: -m.left, bottom: -m.bottom, right: -m.right))

        guard let img = captureSource.capture(rectInWindow: target, scale: scale) else {
            return false
        }
        
        snapshot = Snapshot(cgImage: img, rectInWindow: target, scale: scale, timestamp: CACurrentMediaTime())
        return true
    }

    /// Основной метод: вернуть кропнутый CGImage под текущий rect (в координатах UIWindow).
    /// Если кеш не покрывает rect — пытаемся обновить общий snapshot (с rate-limit).
    public func croppedImage(
        for rectInWindow: CGRect,
        scale: CGFloat,
        margin: UIEdgeInsets? = nil,
        now: CFTimeInterval = CACurrentMediaTime()
    ) -> CGImage? {
        precondition(Thread.isMainThread)
        
        guard rectInWindow.width > 1, rectInWindow.height > 1 else { return nil }
        guard let captureSource else { return nil }

        let m = margin ?? defaultMargin
        let neededExpanded = rectInWindow.inset(
            by: UIEdgeInsets(top: -m.top, left: -m.left, bottom: -m.bottom, right: -m.right)
        )

        // 1) Если текущий snapshot подходит — просто кропаем.
        if let s = snapshot,
           abs(s.scale - scale) < 0.0001,
           s.rectInWindow.contains(rectInWindow),
           let cropped = crop(snapshot: s, to: rectInWindow) {
            return cropped
        }

        // 2) Если snapshot не подходит — решаем, можно ли перефоткать общий snapshot (rate limit).
        let shouldBypassRateLimit = (snapshot == nil) // первый снимок — всегда делаем
        if shouldBypassRateLimit || canRefreshSnapshot(now: now) {
            // Если уже был snapshot — лучше брать union(старый, новый expanded), чтобы меньше "дёргаться" по краям.
            
            let captureRect: CGRect
            if let s = snapshot, abs(s.scale - scale) < 0.0001 {
                captureRect = s.rectInWindow.union(neededExpanded)
            } else {
                captureRect = neededExpanded
            }

            if let img = captureSource.capture(rectInWindow: captureRect, scale: scale) {
                snapshot = Snapshot(cgImage: img, rectInWindow: captureRect, scale: scale, timestamp: now)
            }
        }

        // 3) После попытки обновления — снова пробуем отдать кроп.
        if let s = snapshot,
           abs(s.scale - scale) < 0.0001,
           s.rectInWindow.contains(rectInWindow),
           let cropped = crop(snapshot: s, to: rectInWindow) {
            return cropped
        }

        // 4) Если не покрыли (слишком маленький margin или rate-limit не дал обновиться) — ничего не отдаём.
        return nil
    }

    // MARK: - Internal

    private func canRefreshSnapshot(now: CFTimeInterval) -> Bool {
        guard maxSnapshotFPS > 0 else { return true }
        guard let s = snapshot else { return true }
        let minDelta = 1.0 / maxSnapshotFPS
        return (now - s.timestamp) >= minDelta
    }

    private func crop(snapshot s: Snapshot, to rectInWindow: CGRect) -> CGImage? {
        // rectInWindow (points) -> local rect inside snapshot (points)
        let local = CGRect(
            x: rectInWindow.origin.x - s.rectInWindow.origin.x,
            y: rectInWindow.origin.y - s.rectInWindow.origin.y,
            width: rectInWindow.size.width,
            height: rectInWindow.size.height
        )

        // points -> pixels
        var px = CGRect(
            x: local.origin.x * s.scale,
            y: local.origin.y * s.scale,
            width: local.size.width * s.scale,
            height: local.size.height * s.scale
        ).integral

        // clamp в границы изображения (на всякий)
        let maxW = CGFloat(s.cgImage.width)
        let maxH = CGFloat(s.cgImage.height)
        if px.origin.x < 0 { px.origin.x = 0 }
        if px.origin.y < 0 { px.origin.y = 0 }
        if px.maxX > maxW { px.size.width = max(0, maxW - px.origin.x) }
        if px.maxY > maxH { px.size.height = max(0, maxH - px.origin.y) }

        guard px.width >= 1, px.height >= 1 else { return nil }
        return s.cgImage.cropping(to: px)
    }
}

private extension CGRect {
    func inset(by insets: UIEdgeInsets) -> CGRect {
        CGRect(
            x: origin.x + insets.left,
            y: origin.y + insets.top,
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom
        )
    }
}
