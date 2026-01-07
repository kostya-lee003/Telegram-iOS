import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Display
import UIKitRuntimeUtils
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import TelegramPresentationData

private extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

private let separatorHeight: CGFloat = 1.0 / UIScreen.main.scale
private func tabBarItemImage(_ image: UIImage?, title: String, backgroundColor: UIColor, tintColor: UIColor, horizontal: Bool, imageMode: Bool, centered: Bool = false) -> (UIImage, CGFloat) {
    let font = horizontal ? Font.regular(13.0) : Font.medium(10.0)
    let titleSize = (title as NSString).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [NSAttributedString.Key.font: font], context: nil).size
    
    let imageSize: CGSize
    if let image = image {
        if horizontal {
            let factor: CGFloat = 0.8
            imageSize = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor))
        } else {
            imageSize = image.size
        }
    } else {
        imageSize = CGSize()
    }
    
    let horizontalSpacing: CGFloat = 4.0
    
    let size: CGSize
    let contentWidth: CGFloat
    if horizontal {
        let width = max(1.0, centered ? imageSize.width : ceil(titleSize.width) + horizontalSpacing + imageSize.width)
        size = CGSize(width: width, height: 34.0)
        contentWidth = size.width
    } else {
        let width =  max(1.0, centered ? imageSize.width : max(ceil(titleSize.width), imageSize.width), 1.0)
        size = CGSize(width: width, height: 45.0)
        contentWidth = imageSize.width
    }
    
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    if let context = UIGraphicsGetCurrentContext() {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: CGPoint(), size: size))
        
        if let image = image, imageMode {
            let imageRect: CGRect
            if horizontal {
                imageRect = CGRect(origin: CGPoint(x: 0.0, y: floor((size.height - imageSize.height) / 2.0)), size: imageSize)
            } else {
                imageRect = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - imageSize.width) / 2.0), y: centered ? floor((size.height - imageSize.height) / 2.0) : 0.0), size: imageSize)
            }
            context.saveGState()
            context.translateBy(x: imageRect.midX, y: imageRect.midY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
            if image.renderingMode == .alwaysOriginal {
                context.draw(image.cgImage!, in: imageRect)
            } else {
                context.clip(to: imageRect, mask: image.cgImage!)
                context.setFillColor(tintColor.cgColor)
                context.fill(imageRect)
            }
            context.restoreGState()
        }
    }
    
    if !imageMode {
        if horizontal {
            (title as NSString).draw(at: CGPoint(x: imageSize.width + horizontalSpacing, y: floor((size.height - titleSize.height) / 2.0)), withAttributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: tintColor])
        } else {
            (title as NSString).draw(at: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: size.height - titleSize.height - 1.0), withAttributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: tintColor])
        }
    }
    
    let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return (resultImage!, contentWidth)
}

private let badgeFont = Font.regular(13.0)

private final class TabBarItemNode: ASDisplayNode {
    let extractedContainerNode: ContextExtractedContentContainingNode
    let containerNode: ContextControllerSourceNode
    let imageNode: ASImageNode
    let animationContainerNode: ASDisplayNode
    let animationNode: AnimatedStickerNode
    let textImageNode: ASImageNode
    let contextImageNode: ASImageNode
    let contextTextImageNode: ASImageNode
    var contentWidth: CGFloat?
    var isSelected: Bool = false
    
    let ringImageNode: ASImageNode
    var ringColor: UIColor? {
        didSet {
            if let ringColor = self.ringColor {
                self.ringImageNode.image = generateCircleImage(diameter: 29.0, lineWidth: 1.0, color: ringColor, backgroundColor: nil)
            } else {
                self.ringImageNode.image = nil
            }
        }
    }
    
    var swiped: ((TabBarItemSwipeDirection) -> Void)?
    
    var pointerInteraction: PointerInteraction?
    
    override init() {
        self.extractedContainerNode = ContextExtractedContentContainingNode()
        self.containerNode = ContextControllerSourceNode()
        
        self.ringImageNode = ASImageNode()
        self.ringImageNode.isUserInteractionEnabled = false
        self.ringImageNode.displayWithoutProcessing = true
        self.ringImageNode.displaysAsynchronously = false
        
        self.imageNode = ASImageNode()
        self.imageNode.isUserInteractionEnabled = false
        self.imageNode.displayWithoutProcessing = true
        self.imageNode.displaysAsynchronously = false
        self.imageNode.isAccessibilityElement = false
        
        self.animationContainerNode = ASDisplayNode()
        
        self.animationNode = DefaultAnimatedStickerNodeImpl()
        self.animationNode.autoplay = true
        self.animationNode.automaticallyLoadLastFrame = true
        
        self.textImageNode = ASImageNode()
        self.textImageNode.isUserInteractionEnabled = false
        self.textImageNode.displayWithoutProcessing = true
        self.textImageNode.displaysAsynchronously = false
        self.textImageNode.isAccessibilityElement = false
        
        self.contextImageNode = ASImageNode()
        self.contextImageNode.isUserInteractionEnabled = false
        self.contextImageNode.displayWithoutProcessing = true
        self.contextImageNode.displaysAsynchronously = false
        self.contextImageNode.isAccessibilityElement = false
        self.contextImageNode.alpha = 0.0
        self.contextTextImageNode = ASImageNode()
        self.contextTextImageNode.isUserInteractionEnabled = false
        self.contextTextImageNode.displayWithoutProcessing = true
        self.contextTextImageNode.displaysAsynchronously = false
        self.contextTextImageNode.isAccessibilityElement = false
        self.contextTextImageNode.alpha = 0.0
        
        super.init()
        
        self.isAccessibilityElement = true
        
        self.extractedContainerNode.contentNode.addSubnode(self.ringImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.textImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.imageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.animationContainerNode)
        self.animationContainerNode.addSubnode(self.animationNode)
        self.extractedContainerNode.contentNode.addSubnode(self.contextTextImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.contextImageNode)
        self.containerNode.addSubnode(self.extractedContainerNode)
        self.containerNode.targetNodeForActivationProgress = self.extractedContainerNode.contentNode
        self.addSubnode(self.containerNode)
        
        self.extractedContainerNode.willUpdateIsExtractedToContextPreview = { [weak self] isExtracted, transition in
            guard let strongSelf = self else {
                return
            }
            transition.updateAlpha(node: strongSelf.ringImageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.imageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.animationNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.textImageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.contextImageNode, alpha: isExtracted ? 1.0 : 0.0)
            transition.updateAlpha(node: strongSelf.contextTextImageNode, alpha: isExtracted ? 1.0 : 0.0)
        }
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.pointerInteraction = PointerInteraction(node: self, style: .rectangle(CGSize(width: 90.0, height: 50.0)))
    }
    
    @objc private func swipeGesture(_ gesture: UISwipeGestureRecognizer) {
        if case .ended = gesture.state {
            self.containerNode.cancelGesture()
            
            switch gesture.direction {
            case .left:
                self.swiped?(.left)
            default:
                self.swiped?(.right)
            }
        }
    }
}

private final class TabBarNodeContainer {
    let item: UITabBarItem
    let updateBadgeListenerIndex: Int
    let updateTitleListenerIndex: Int
    let updateImageListenerIndex: Int
    let updateSelectedImageListenerIndex: Int
    
    let imageNode: TabBarItemNode
    let badgeContainerNode: ASDisplayNode
    let badgeBackgroundNode: ASImageNode
    let badgeTextNode: ImmediateTextNode
    
    var badgeValue: String?
    var appliedBadgeValue: String?
    
    var titleValue: String?
    var appliedTitleValue: String?
    
    var imageValue: UIImage?
    var appliedImageValue: UIImage?
    
    var selectedImageValue: UIImage?
    var appliedSelectedImageValue: UIImage?
    
    init(item: TabBarNodeItem, imageNode: TabBarItemNode, updateBadge: @escaping (String) -> Void, updateTitle: @escaping (String, Bool) -> Void, updateImage: @escaping (UIImage?) -> Void, updateSelectedImage: @escaping (UIImage?) -> Void, contextAction: @escaping (ContextExtractedContentContainingNode, ContextGesture) -> Void, swipeAction: @escaping (TabBarItemSwipeDirection) -> Void) {
        self.item = item.item
        
        self.imageNode = imageNode
        self.imageNode.isAccessibilityElement = true
        self.imageNode.accessibilityTraits = .button
        
        self.badgeContainerNode = ASDisplayNode()
        self.badgeContainerNode.isUserInteractionEnabled = false
        self.badgeContainerNode.isAccessibilityElement = false
        
        self.badgeBackgroundNode = ASImageNode()
        self.badgeBackgroundNode.isUserInteractionEnabled = false
        self.badgeBackgroundNode.displayWithoutProcessing = true
        self.badgeBackgroundNode.displaysAsynchronously = false
        self.badgeBackgroundNode.isAccessibilityElement = false
        
        self.badgeTextNode = ImmediateTextNode()
        self.badgeTextNode.maximumNumberOfLines = 1
        self.badgeTextNode.isUserInteractionEnabled = false
        self.badgeTextNode.displaysAsynchronously = false
        self.badgeTextNode.isAccessibilityElement = false
        
        self.badgeContainerNode.addSubnode(self.badgeBackgroundNode)
        self.badgeContainerNode.addSubnode(self.badgeTextNode)
        
        self.badgeValue = item.item.badgeValue ?? ""
        self.updateBadgeListenerIndex = UITabBarItem_addSetBadgeListener(item.item, { value in
            updateBadge(value ?? "")
        })
        
        self.titleValue = item.item.title
        self.updateTitleListenerIndex = item.item.addSetTitleListener { value, animated in
            updateTitle(value ?? "", animated)
        }
        
        self.imageValue = item.item.image
        self.updateImageListenerIndex = item.item.addSetImageListener { value in
            updateImage(value)
        }
        
        self.selectedImageValue = item.item.selectedImage
        self.updateSelectedImageListenerIndex = item.item.addSetSelectedImageListener { value in
            updateSelectedImage(value)
        }
        
        imageNode.containerNode.activated = { [weak self] gesture, _ in
            guard let strongSelf = self else {
                return
            }
            contextAction(strongSelf.imageNode.extractedContainerNode, gesture)
        }
        imageNode.swiped = { [weak imageNode] direction in
            guard let imageNode = imageNode, imageNode.isSelected else {
                return
            }
            swipeAction(direction)
        }
        imageNode.containerNode.isGestureEnabled = item.contextActionType != .none
        let contextActionType = item.contextActionType
        imageNode.containerNode.shouldBegin = { [weak imageNode] _ in
            switch contextActionType {
            case .none:
                return false
            case .always:
                return true
            case .whenActive:
                return imageNode?.isSelected ?? false
            }
        }
    }
    
    deinit {
        self.item.removeSetBadgeListener(self.updateBadgeListenerIndex)
        self.item.removeSetTitleListener(self.updateTitleListenerIndex)
        self.item.removeSetImageListener(self.updateImageListenerIndex)
        self.item.removeSetSelectedImageListener(self.updateSelectedImageListenerIndex)
    }
}

final class TabBarNodeItem {
    let item: UITabBarItem
    let contextActionType: TabBarItemContextActionType
    
    init(item: UITabBarItem, contextActionType: TabBarItemContextActionType) {
        self.item = item
        self.contextActionType = contextActionType
    }
}

class TabBarNode: ASDisplayNode, ASGestureRecognizerDelegate {
    
    var tabBarItems: [TabBarNodeItem] = [] {
        didSet {
            self.reloadTabBarItems()
        }
    }
    
    var reduceMotion: Bool = false
    
    var selectedIndex: Int? {
        didSet {
            guard selectedIndex != oldValue else { return }

            if let old = oldValue {
                updateNodeImage(old, layout: true)
            }
            if let new = selectedIndex {
                updateNodeImage(new, layout: true)
            }

            if suppressNextSelectedIndexMove {
                suppressNextSelectedIndexMove = false
                if let capsuleFrame = lastCapsuleFrame,
                   let new = selectedIndex,
                   let target = makeGlassFrame(for: new, capsuleFrame: capsuleFrame) {
                    glassAnimBaseFrame = target
                }
                return
            }

            guard
                let capsuleFrame = lastCapsuleFrame,
                let new = selectedIndex,
                let target = makeGlassFrame(for: new, capsuleFrame: capsuleFrame)
            else {
                return
            }

            let fromX: CGFloat? = {
                if let old = oldValue,
                   let oldFrame = makeGlassFrame(for: old, capsuleFrame: capsuleFrame) {
                    return oldFrame.origin.x
                }
                if !glassNode.isHidden {
                    return glassNode.frame.origin.x
                }
                return nil
            }()

            startGlassMove(to: target, fromX: fromX)
        }
    }
    
    private let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    private let contextAction: (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void
    private let swipeAction: (Int, TabBarItemSwipeDirection) -> Void
    
    private var theme: TabBarControllerTheme
    private var validLayout: (CGSize, CGFloat, CGFloat, UIEdgeInsets, CGFloat)?
    private var horizontal: Bool = false
    private var centered: Bool = false
    
    private var badgeImage: UIImage

    let backgroundNode: NavigationBackgroundNode
    let separatorNode: ASDisplayNode
    private var tabBarNodeContainers: [TabBarNodeContainer] = []

    private let glassNode: LiquidGlassNode = {
        let node = LiquidGlassNode()
        node.isUserInteractionEnabled = false
        node.configuration.downscale = 0.55
        node.configuration.refraction = 0.16
        node.configuration.shadowOffset = 8
        node.configuration.shadowBlur = 20
        node.configuration.shadowStrength = 0.08
        node.configuration.alpha = 0.0
        node.configuration.rimThickness = 1.6
        node.configuration.rimStrength  = 1.05
        node.configuration.chroma = 0.16
        node.shape = .roundedRect(cornerRadius: 0)
        return node
    }()

    private var glassEnvironment: LiquidGlassSnapshotEnvironment?
    private var glassCaptureSource: LiquidGlassCaptureSource?
    private var lastCapsuleFrame: CGRect?
    
    private enum GlassMotionPhase {
        case tapMove
        case dragReleaseSettle
    }
    
    // MARK: - Glass animation (X only)

    private var forcePrimeWorkItem: DispatchWorkItem?

    private var isGlassAnimating = false
    private var glassMoveLink: CADisplayLink?

    private var glassAnimStartTime: CFTimeInterval = 0
    private var glassAnimDuration: Double = 0.65
    private let tapMoveDuration: Double = 0.50

    private var glassAnimFromX: CGFloat = 0
    private var glassAnimToX: CGFloat = 0

    private var glassAnimBaseFrame: CGRect = .zero

    // MARK: - Glass drag

    private var glassDragRecognizer: UIPanGestureRecognizer?
    
    private var glassDragStartPoint: CGPoint = .zero
    private var isGlassDragArmed = false

    private var isGlassDragging = false
    private var glassDragLink: CADisplayLink?

    private var glassDragBaseFrame: CGRect = .zero
    private var glassDragTargetCenterX: CGFloat = 0
    private var glassDragCurrentCenterX: CGFloat = 0

    private var glassDragLastX: CGFloat = 0
    private var glassDragLastTime: CFTimeInterval = 0
    private var glassDragVelocityX: CGFloat = 0
    
    private var glassTapVelocityX: CGFloat = 0.0
    private var glassDragBoostStartTime: CFTimeInterval = 0
    private var glassAnimStartUniform: CGFloat = 1.0
    private var minUniformToReachTabSize: CGFloat { 1.0 / GlassSize.baseScale }

    private var suppressTapUntil: CFTimeInterval = 0
    
    private var skipNextSelectedIndexAnimation = false

    private var glassMotionPhase: GlassMotionPhase = .tapMove

    private var suppressNextSelectedIndexMove = false
    
    private var pendingSwitchWorkItem: DispatchWorkItem?
    private var pendingSwitchIndex: Int?
    private var pendingSwitchIsLongTap: Bool = false

    // Pan-session flag: начался ли этот pan прямо на стекле (а не “в любом месте таббара”)
    private var glassDragStartedOnGlass: Bool = false

    // опционально, если делаешь catch-up:
    private var glassDragCatchUpUntil: CFTimeInterval = 0
    
    private var isPressHolding: Bool = false  // для long-press: держим стекло увеличенным, не даём уйти в дефолт


    
    // MARK: - Glass Bounce & Liquid effect
    
    private var glassAnimStretchAmplitude: CGFloat = 0.0     // 0..0.4 (доп. рост по Y)
    private var glassAnimBrightnessAmplitude: CGFloat = 0.0  // 0..0.2 (пик яркости)
    
    private var glassAnimStartDelta: CGFloat = 0.0

    
    private var tapRecognizer: TapLongTapOrDoubleTapGestureRecognizer?
    private var touchDownPendingIndex: Int?
    private var didStartGlassMoveOnTouchDown = false
    
    init(theme: TabBarControllerTheme, itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void, contextAction: @escaping (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void, swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void) {
        self.itemSelected = itemSelected
        self.contextAction = contextAction
        self.swipeAction = swipeAction
        self.theme = theme

        self.backgroundNode = NavigationBackgroundNode(color: theme.tabBarBackgroundColor)
        
        self.separatorNode = ASDisplayNode()
        self.separatorNode.backgroundColor = theme.tabBarSeparatorColor
        self.separatorNode.isOpaque = true
        self.separatorNode.isLayerBacked = true
        
        self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.tabBarBadgeBackgroundColor, strokeColor: theme.tabBarBadgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
        
        super.init()
        
        self.isAccessibilityContainer = false
        self.accessibilityTraits = [.tabBar]
        
        self.isOpaque = false
        self.backgroundColor = nil
        
        self.isExclusiveTouch = true

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.separatorNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        let recognizer = TapLongTapOrDoubleTapGestureRecognizer(target: self, action: #selector(self.tapLongTapOrDoubleTapGesture(_:)))
        recognizer.delegate = self.wrappedGestureRecognizerDelegate
        recognizer.tapActionAtPoint = { _ in
            return .keepWithSingleTap
        }
        self.tapRecognizer = recognizer
        self.view.addGestureRecognizer(recognizer)
    }
    
    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        ensureGlassCaptureSource()
        setupGlassDragGestureIfNeeded()
        glassNode.renderCurrentFrame()
    }
    
    override func didExitHierarchy() {
        super.didExitHierarchy()
        self.glassCaptureSource = nil
        self.glassNode.captureSource = nil
    }
    
    private func ensureGlassCaptureSource() {
        precondition(Thread.isMainThread)
        
        if self.glassNode.captureSource != nil { return }

        let glassView = self.glassNode.view
        guard let window = self.view.window else { return }

        let source = HidingWindowCaptureSource(window: window, viewToHide: glassView)
        self.glassCaptureSource = source
        self.glassNode.captureSource = source

        if self.glassEnvironment == nil {
            let env = LiquidGlassSnapshotEnvironment()
            env.captureSource = source
            env.maxSnapshotFPS = 60
            self.glassEnvironment = env
        } else {
            self.glassEnvironment?.captureSource = source
        }

        self.glassNode.snapshotEnvironment = self.glassEnvironment
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return true
    }
    
    @objc private func tapLongTapOrDoubleTapGesture(_ recognizer: TapLongTapOrDoubleTapGestureRecognizer) {
        let now = CACurrentMediaTime()

        switch recognizer.state {
        case .began:
            self.isPressHolding = true
            self.pendingSwitchIsLongTap = false

            let location = recognizer.location(in: self.view)
            guard let capsuleFrame = self.lastCapsuleFrame,
                  let targetIndex = self.nearestTabIndex(at: location) else { return }
            
            guard let targetFrame = self.makeGlassFrame(
                for: targetIndex,
                capsuleFrame: capsuleFrame
            ) else { return }

            var fromX: CGFloat? = nil
            if self.glassNode.isHidden {
                if let selected = self.selectedIndex,
                   let selFrame = self.makeGlassFrame(for: selected, capsuleFrame: capsuleFrame) {
                    fromX = selFrame.origin.x
                } else {
                    fromX = nil
                }
            } else {
                fromX = self.glassNode.frame.origin.x
            }

            self.startGlassMove(to: targetFrame, fromX: fromX)

            if targetIndex != self.selectedIndex {
                scheduleTabSwitch(index: targetIndex)
            }

        case .ended:
            if self.isGlassDragging || now < self.suppressTapUntil {
                self.touchDownPendingIndex = nil
                self.didStartGlassMoveOnTouchDown = false
                return
            }

            if let (gesture, location) = recognizer.lastRecognizedGestureAndLocation {
                if case .tap = gesture {

                    if let endIndex = self.nearestTabIndex(at: location),
                       let pending = self.touchDownPendingIndex,
                       self.didStartGlassMoveOnTouchDown,
                       pending != endIndex
                    {
                        self.stopGlassMove(completed: false)
                        self.didStartGlassMoveOnTouchDown = false
                        self.touchDownPendingIndex = nil
                    }

                    if let endIndex = self.nearestTabIndex(at: location),
                       let pending = self.touchDownPendingIndex,
                       self.didStartGlassMoveOnTouchDown,
                       pending == endIndex
                    {
                        self.suppressNextSelectedIndexMove = true
                    }

                    self.tapped(at: location, longTap: false)
                } else {
                }
            }

            self.touchDownPendingIndex = nil
            self.didStartGlassMoveOnTouchDown = false
            self.isPressHolding = false

        case .cancelled, .failed:
            self.touchDownPendingIndex = nil
            self.didStartGlassMoveOnTouchDown = false
            self.isPressHolding = false
            cancelPendingTabSwitch()

        default:
            break
        }
    }

    
    func updateTheme(_ theme: TabBarControllerTheme) {
        if self.theme !== theme {
            self.theme = theme
            
            self.separatorNode.backgroundColor = theme.tabBarSeparatorColor
            self.backgroundNode.updateColor(color: theme.tabBarBackgroundColor, transition: .immediate)
            
            self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.tabBarBadgeBackgroundColor, strokeColor: theme.tabBarBadgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
            for container in self.tabBarNodeContainers {
                if let attributedText = container.badgeTextNode.attributedText, !attributedText.string.isEmpty {
                    container.badgeTextNode.attributedText = NSAttributedString(string: attributedText.string, font: badgeFont, textColor: self.theme.tabBarBadgeTextColor)
                }
            }
            
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
                
                self.tabBarNodeContainers[i].badgeBackgroundNode.image = self.badgeImage
            }
            
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    func sourceNodesForController(at index: Int) -> [ASDisplayNode]? {
        let container = self.tabBarNodeContainers[index]
        return [container.imageNode.imageNode, container.imageNode.textImageNode, container.badgeContainerNode]
    }
    
    func frameForControllerTab(at index: Int) -> CGRect? {
        let container = self.tabBarNodeContainers[index]
        return container.imageNode.frame
    }
    
    func viewForControllerTab(at index: Int) -> UIView? {
        let container = self.tabBarNodeContainers[index]
        return container.imageNode.view
    }
    
    private func reloadTabBarItems() {
        for node in self.tabBarNodeContainers {
            node.imageNode.removeFromSupernode()
        }
        
        self.centered = self.theme.tabBarTextColor == .clear
        
        var tabBarNodeContainers: [TabBarNodeContainer] = []
        for i in 0 ..< self.tabBarItems.count {
            let item = self.tabBarItems[i]
            let node = TabBarItemNode()
            let container = TabBarNodeContainer(item: item, imageNode: node, updateBadge: { [weak self] value in
                self?.updateNodeBadge(i, value: value)
            }, updateTitle: { [weak self] _, _ in
                self?.updateNodeImage(i, layout: true)
            }, updateImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, updateSelectedImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, contextAction: { [weak self] node, gesture in
                guard let self else { return }
                self.tapRecognizer?.cancel()
                self.contextAction(i, node, gesture)
            }, swipeAction: { [weak self] direction in
                self?.swipeAction(i, direction)
            })
            if item.item.ringSelection {
                node.ringColor = self.theme.tabBarSelectedIconColor
            } else {
                node.ringColor = nil
            }
            
            if let selectedIndex = self.selectedIndex, selectedIndex == i {
                let (textImage, contentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarSelectedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth): (UIImage, CGFloat)
                
                if let _ = item.item.animationName {
                    (image, imageContentWidth) = (UIImage(), 0.0)
                    
                    node.animationNode.isHidden = false
                    let animationSize: Int = Int(51.0 * UIScreen.main.scale)
                    node.animationNode.visibility = true
                    if !node.isSelected {
                        node.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.item.animationName ?? ""), width: animationSize, height: animationSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    }
                    node.animationNode.setOverlayColor(self.theme.tabBarSelectedIconColor, replace: true, animated: false)
                    node.animationNode.updateLayout(size: CGSize(width: 51.0, height: 51.0))
                } else {
                    (image, imageContentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarSelectedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                    
                    node.animationNode.isHidden = true
                    node.animationNode.visibility = false
                }
              
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                node.textImageNode.image = textImage
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button, .selected]
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = true
            } else {
                let (textImage, contentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                
                node.animationNode.isHidden = true
                node.animationNode.visibility = false
                
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = false
            }
            container.badgeBackgroundNode.image = self.badgeImage
            node.extractedContainerNode.contentNode.addSubnode(container.badgeContainerNode)
            tabBarNodeContainers.append(container)
            self.addSubnode(node)
        }
        
        self.tabBarNodeContainers = tabBarNodeContainers
        
        self.reloadHighlightedTab()
        
        self.setNeedsLayout()
    }
    
    private func reloadHighlightedTab() {
        if let last = self.tabBarNodeContainers.last?.imageNode {
            if self.glassNode.supernode != nil {
                self.glassNode.removeFromSupernode()
            }
            self.insertSubnode(self.glassNode, aboveSubnode: last)
        } else {
            if self.glassNode.supernode == nil {
                self.addSubnode(self.glassNode)
            }
        }
    }
    
    private func updateNodeImage(_ index: Int, layout: Bool) {
        if index < self.tabBarNodeContainers.count && index < self.tabBarItems.count {
            let node = self.tabBarNodeContainers[index].imageNode
            let item = self.tabBarItems[index]
            
            self.centered = self.theme.tabBarTextColor == .clear
            
            if item.item.ringSelection {
                node.ringColor = self.theme.tabBarSelectedIconColor
            } else {
                node.ringColor = nil
            }
            
            let previousImageSize = node.imageNode.image?.size ?? CGSize()
            let previousTextImageSize = node.textImageNode.image?.size ?? CGSize()
            if let selectedIndex = self.selectedIndex, selectedIndex == index {
                let (textImage, contentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarSelectedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth): (UIImage, CGFloat)
                if let _ = item.item.animationName {
                    (image, imageContentWidth) = (UIImage(), 0.0)
                    
                    node.animationNode.isHidden = false
                    let animationSize: Int = Int(51.0 * UIScreen.main.scale)
                    node.animationNode.visibility = true
                    if !node.isSelected {
                        node.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.item.animationName ?? ""), width: animationSize, height: animationSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    }
                    node.animationNode.setOverlayColor(self.theme.tabBarSelectedIconColor, replace: true, animated: false)
                    node.animationNode.updateLayout(size: CGSize(width: 51.0, height: 51.0))
                } else {
                    if item.item.ringSelection {
                        (image, imageContentWidth) = (item.item.selectedImage ?? UIImage(), item.item.selectedImage?.size.width ?? 0.0)
                    } else {
                        (image, imageContentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarSelectedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                    }
                    
                    node.animationNode.isHidden = true
                    node.animationNode.visibility = false
                }
                
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button, .selected]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = true
                
                if !self.reduceMotion && item.item.ringSelection {
                    ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTransformScale(node: node.ringImageNode, scale: 1.0, delay: 0.1)
                    node.imageNode.layer.animateScale(from: 1.0, to: 0.87, duration: 0.1, removeOnCompletion: false, completion: { [weak node] _ in
                        node?.imageNode.layer.animateScale(from: 0.87, to: 1.0, duration: 0.14, removeOnCompletion: false, completion: { [weak node] _ in
                            node?.imageNode.layer.removeAllAnimations()
                        })
                    })
                }
            } else {
                let (textImage, contentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                
                let (image, imageContentWidth): (UIImage, CGFloat)
                if item.item.ringSelection {
                    (image, imageContentWidth) = (item.item.image ?? UIImage(), item.item.image?.size.width ?? 0.0)
                } else {
                    (image, imageContentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                }
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.tabBarExtractedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                
                node.animationNode.stop()
                node.animationNode.isHidden = true
                node.animationNode.visibility = false
                
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = false
                
                ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTransformScale(node: node.ringImageNode, scale: 0.5)
            }
            
            let updatedImageSize = node.imageNode.image?.size ?? CGSize()
            let updatedTextImageSize = node.textImageNode.image?.size ?? CGSize()
            
            if previousImageSize != updatedImageSize || previousTextImageSize != updatedTextImageSize {
                if let validLayout = self.validLayout, layout {
                    self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
                }
            }
        }
    }
    
    private func updateNodeBadge(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].badgeValue = value
        if self.tabBarNodeContainers[index].badgeValue != self.tabBarNodeContainers[index].appliedBadgeValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    private func updateNodeTitle(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].titleValue = value
        if self.tabBarNodeContainers[index].titleValue != self.tabBarNodeContainers[index].appliedTitleValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }

    func updateLayout(
        size: CGSize,
        leftInset: CGFloat,
        rightInset: CGFloat,
        additionalSideInsets: UIEdgeInsets,
        bottomInset: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        
        self.validLayout = (size, leftInset, rightInset, additionalSideInsets, bottomInset)

        let containerSize = self.bounds.size
        let sideInsets = leftInset + rightInset + additionalSideInsets.left + additionalSideInsets.right
        let capsuleOuterInset: CGFloat = 26.0
        let capsuleWidth = max(
            1.0,
            containerSize.width - sideInsets - capsuleOuterInset * 2.0
        )
        let capsuleHeight = 60.0

        let capsuleBottomPadding: CGFloat = 20.0
        let capsuleOriginY = containerSize.height - bottomInset - capsuleHeight - capsuleBottomPadding

        let capsuleOriginX = leftInset + additionalSideInsets.left + capsuleOuterInset

        let capsuleFrame = CGRect(
            x: capsuleOriginX,
            y: max(0.0, capsuleOriginY),
            width: capsuleWidth,
            height: capsuleHeight
        )
        self.lastCapsuleFrame = capsuleFrame

        transition.updateFrame(node: self.backgroundNode, frame: capsuleFrame)
        self.backgroundNode.cornerRadius = capsuleHeight / 2.0
        self.backgroundNode.clipsToBounds = true
        self.backgroundNode.update(size: capsuleFrame.size, transition: transition)

        self.separatorNode.isHidden = true

        let horizontal = !leftInset.isZero
        if self.horizontal != horizontal {
            self.horizontal = horizontal
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
            }
        }
        
        if self.tabBarNodeContainers.count != 0 {
            var tabBarNodeContainers = self.tabBarNodeContainers
            var width = capsuleWidth

            var callsTabBarNodeContainer: TabBarNodeContainer?
            if tabBarNodeContainers.count == 4 {
                callsTabBarNodeContainer = tabBarNodeContainers[1]
            }

            if additionalSideInsets.right > 0.0 {
                width -= additionalSideInsets.right

                if let callsTabBarNodeContainer = callsTabBarNodeContainer {
                    tabBarNodeContainers.remove(at: 1)
                    transition.updateAlpha(node: callsTabBarNodeContainer.imageNode, alpha: 0.0)
                    callsTabBarNodeContainer.imageNode.isUserInteractionEnabled = false
                }
            } else {
                if let callsTabBarNodeContainer = callsTabBarNodeContainer {
                    transition.updateAlpha(node: callsTabBarNodeContainer.imageNode, alpha: 1.0)
                    callsTabBarNodeContainer.imageNode.isUserInteractionEnabled = true
                }
            }

            let distanceBetweenNodes = width / CGFloat(tabBarNodeContainers.count)
            let internalWidth = distanceBetweenNodes * CGFloat(tabBarNodeContainers.count - 1)
            let leftNodeOriginX = (width - internalWidth) / 2.0

            for i in 0 ..< tabBarNodeContainers.count {
                let container = tabBarNodeContainers[i]
                let node = container.imageNode
                let nodeSize = node.textImageNode.image?.size ?? CGSize()

                let originXInsideCapsule = floor(leftNodeOriginX + CGFloat(i) * distanceBetweenNodes - nodeSize.width / 2.0)
                let originYInsideCapsule = floor(capsuleFrame.minY + (capsuleHeight - nodeSize.height) / 2.0)

                let nodeFrame = CGRect(
                    origin: CGPoint(
                        x: capsuleFrame.minX + originXInsideCapsule,
                        y: originYInsideCapsule
                    ),
                    size: nodeSize
                )

                let horizontalHitTestInset = distanceBetweenNodes / 2.0 - nodeSize.width / 2.0

                transition.updateFrame(node: node, frame: nodeFrame)

                node.extractedContainerNode.frame = CGRect(origin: .zero, size: nodeFrame.size)
                node.extractedContainerNode.contentNode.frame = node.extractedContainerNode.bounds
                node.extractedContainerNode.contentRect = node.extractedContainerNode.bounds
                node.containerNode.frame = CGRect(origin: .zero, size: nodeFrame.size)

                node.hitTestSlop = UIEdgeInsets(
                    top: -3.0,
                    left: -horizontalHitTestInset,
                    bottom: -3.0,
                    right: -horizontalHitTestInset
                )
                node.containerNode.hitTestSlop = node.hitTestSlop

                node.accessibilityFrame = nodeFrame
                    .insetBy(dx: -horizontalHitTestInset, dy: 0.0)
                    .offsetBy(dx: 0.0, dy: size.height - nodeSize.height - bottomInset)

                if node.ringColor == nil {
                    node.imageNode.frame = CGRect(origin: .zero, size: nodeFrame.size)
                }
                node.textImageNode.frame = CGRect(origin: .zero, size: nodeFrame.size)
                node.contextImageNode.frame = CGRect(origin: .zero, size: nodeFrame.size)
                node.contextTextImageNode.frame = CGRect(origin: .zero, size: nodeFrame.size)

                let scaleFactor: CGFloat = horizontal ? 0.8 : 1.0
                node.animationContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)
                let animationOffset: CGPoint = self.tabBarItems[i].item.animationOffset

                let ringImageFrame: CGRect
                let imageFrame: CGRect
                if horizontal {
                    node.animationNode.frame = CGRect(
                        origin: CGPoint(x: -10.0 - UIScreenPixel, y: -4.0 - UIScreenPixel),
                        size: CGSize(width: 51.0, height: 51.0)
                    )
                    ringImageFrame = CGRect(
                        origin: CGPoint(x: UIScreenPixel, y: 5.0 + UIScreenPixel),
                        size: CGSize(width: 23.0, height: 23.0)
                    )
                    imageFrame = ringImageFrame.insetBy(dx: -1.0 + UIScreenPixel, dy: -1.0 + UIScreenPixel)
                } else {
                    node.animationNode.frame = CGRect(
                        origin: CGPoint(
                            x: floorToScreenPixels((nodeSize.width - 51.0) / 2.0),
                            y: -10.0 - UIScreenPixel
                        ).offsetBy(dx: animationOffset.x, dy: animationOffset.y),
                        size: CGSize(width: 51.0, height: 51.0)
                    )
                    ringImageFrame = CGRect(
                        origin: CGPoint(
                            x: floorToScreenPixels((nodeSize.width - 29.0) / 2.0),
                            y: 1.0
                        ),
                        size: CGSize(width: 29.0, height: 29.0)
                    )
                    imageFrame = ringImageFrame.insetBy(dx: -1.0, dy: -1.0)
                }

                node.ringImageNode.bounds = CGRect(origin: .zero, size: ringImageFrame.size)
                node.ringImageNode.position = ringImageFrame.center
                if node.ringColor != nil {
                    node.imageNode.bounds = CGRect(origin: .zero, size: imageFrame.size)
                    node.imageNode.position = imageFrame.center
                }

                if container.badgeValue != container.appliedBadgeValue {
                    container.appliedBadgeValue = container.badgeValue
                    if let badgeValue = container.badgeValue, !badgeValue.isEmpty {
                        container.badgeTextNode.attributedText = NSAttributedString(
                            string: badgeValue,
                            font: badgeFont,
                            textColor: self.theme.tabBarBadgeTextColor
                        )
                        container.badgeContainerNode.isHidden = false
                    } else {
                        container.badgeContainerNode.isHidden = true
                    }
                }

                if !container.badgeContainerNode.isHidden {
                    var hasSingleLetterValue = false
                    if let string = container.badgeTextNode.attributedText?.string {
                        hasSingleLetterValue = string.count == 1
                    }
                    let badgeSize = container.badgeTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                    let backgroundSize = CGSize(
                        width: hasSingleLetterValue ? 18.0 : max(18.0, badgeSize.width + 10.0 + 1.0),
                        height: 18.0
                    )

                    let backgroundFrame: CGRect
                    if horizontal {
                        backgroundFrame = CGRect(
                            origin: CGPoint(x: 13.0, y: 0.0),
                            size: backgroundSize
                        )
                    } else {
                        let contentWidth: CGFloat = 25.0
                        backgroundFrame = CGRect(
                            origin: CGPoint(
                                x: floor(node.frame.width / 2.0) + contentWidth - backgroundSize.width - 5.0,
                                y: self.centered ? 6.0 : -1.0
                            ),
                            size: backgroundSize
                        )
                    }

                    transition.updateFrame(node: container.badgeContainerNode, frame: backgroundFrame)
                    container.badgeBackgroundNode.frame = CGRect(origin: .zero, size: backgroundFrame.size)
                    container.badgeContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)

                    container.badgeTextNode.frame = CGRect(
                        origin: CGPoint(
                            x: floorToScreenPixels((backgroundFrame.size.width - badgeSize.width) / 2.0),
                            y: 1.0
                        ),
                        size: badgeSize
                    )
                }
            }
        }
        if let capsuleFrame = self.lastCapsuleFrame, let selectedIndex = self.selectedIndex,
           let target = self.makeGlassFrame(for: selectedIndex, capsuleFrame: capsuleFrame) {

            if self.isGlassAnimating {
                self.glassAnimBaseFrame = target

                var current = self.glassNode.frame
                current.origin.y = target.origin.y
                current.size = target.size
                self.applyCapsuleFrame(current)
                
                self.glassAnimToX = target.origin.x
            } else {
                self.applyCapsuleFrame(target)
                self.glassNode.configuration.alpha = 0.0
            }
        }

        self.ensureGlassCaptureSource()
    }
    
    private func tapped(at location: CGPoint, longTap: Bool) {
        if let bottomInset = self.validLayout?.4 {
            if location.y > self.bounds.size.height - bottomInset {
                return
            }

            guard let index = self.nearestTabIndex(at: location) else { return }

            if !longTap, index == self.selectedIndex {
                self.bounceGlassOnTap()
                return
            }

            let previousSelectedIndex = self.selectedIndex
            self.itemSelected(index, longTap, self.sourceNodesForItemSelected(at: index))

            if previousSelectedIndex != index {
                let container = self.tabBarNodeContainers[index]
                if let selectedIndex = self.selectedIndex, let _ = self.tabBarItems[selectedIndex].item.animationName {
                    container.imageNode.animationNode.play(firstFrame: false, fromIndex: nil)
                }
            }
        }
    }
    
    // Finds nearest enabled tab index for a given location.
    // Used by tap and drag-release to share identical logic.
    private func nearestTabIndex(at location: CGPoint) -> Int? {
        var closest: (Int, CGFloat)?

        for i in 0 ..< self.tabBarNodeContainers.count {
            let node = self.tabBarNodeContainers[i].imageNode
            if !node.isUserInteractionEnabled { continue }

            let d = abs(location.x - node.position.x)
            if let current = closest {
                if d < current.1 { closest = (i, d) }
            } else {
                closest = (i, d)
            }
        }
        return closest?.0
    }

    // Builds source nodes list for itemSelected callback.
    // Keeps the same nodes order as existing tapped().
    private func sourceNodesForItemSelected(at index: Int) -> [ASDisplayNode] {
        let c = self.tabBarNodeContainers[index]
        return [c.imageNode.imageNode, c.imageNode.textImageNode, c.badgeContainerNode]
    }
}

// MARK: Glass Animation Helpers
extension TabBarNode {
    
    private func snapToPixels(_ v: CGFloat) -> CGFloat {
        let s = self.view.window?.screen.scale ?? UIScreen.main.scale
        return round(v * s) / s
    }

    private func snapRectToPixels(_ r: CGRect) -> CGRect {
        CGRect(
            x: snapToPixels(r.origin.x),
            y: snapToPixels(r.origin.y),
            width: snapToPixels(r.size.width),
            height: snapToPixels(r.size.height)
        )
    }

    private func clampDelta(_ d: CGFloat) -> CGFloat {
        min(GlassSize.deltaRange, max(-GlassSize.deltaRange, d))
    }

    private func scalesFromDelta(_ delta: CGFloat) -> (sx: CGFloat, sy: CGFloat) {
        let d = clampDelta(delta)
        return (GlassSize.baseScale - d, GlassSize.baseScale + d)
    }

    private func deltaFromScales(scaleX: CGFloat, scaleY: CGFloat) -> CGFloat {
        clampDelta((scaleY - scaleX) * 0.5)
    }
    
    private func easeOutBack(_ x: CGFloat, s: CGFloat = 2.2) -> CGFloat {
        let c1 = s
        let c3 = c1 + 1.0
        let t = x - 1.0
        return 1.0 + c3 * t * t * t + c1 * t * t
    }

    private func releaseDelta(at t: CGFloat, startDelta: CGFloat) -> CGFloat {
        let t1 = GlassSize.settlePhase1End
        let d0 = startDelta
        let d1 = GlassSize.settlePhase1Delta
        let d2: CGFloat = 0.0

        if t <= t1 {
            let p = max(0.0, min(1.0, t / t1))
            let k = easeOutBack(p, s: 2.4)
            return clampDelta(d0 + (d1 - d0) * k)
        } else {
            let p = max(0.0, min(1.0, (t - t1) / (1.0 - t1)))
            let k = easeOutBack(p, s: 2.0)
            return clampDelta(d1 + (d2 - d1) * k)
        }
    }
    
    private func tapDelta(at t: CGFloat) -> CGFloat {
        let screenW = self.view.bounds.width > 1 ? self.view.bounds.width : UIScreen.main.bounds.width
        let vRef = GlassSize.referenceVelocity(screenWidth: screenW) * 1.4
        let speedFactor = max(0.0, min(1.0, abs(self.glassTapVelocityX) / max(1.0, vRef)))

        let midBump = sin(.pi * t)

        let deltaTarget = GlassSize.deltaRange * speedFactor * midBump

        let now = CACurrentMediaTime()
        let wobbleAmp = GlassSize.dragWobbleAmpAtMaxSpeed * speedFactor * midBump
        let wobble = sin(CGFloat(now) * 2.0 * .pi * GlassSize.dragWobbleFreqHz) * wobbleAmp

        return clampDelta(deltaTarget + wobble)
    }
    
    private func releaseUniform(at t: CGFloat, startUniform: CGFloat) -> CGFloat {
        let t1 = GlassSize.settlePhase1End // 0.60
        let uMin = minUniformToReachTabSize

        if t <= t1 {
            let p = max(0, min(1, t / t1))
            return startUniform + (uMin - startUniform) * easeOutCubic(p)
        } else {
            let p = max(0, min(1, (t - t1) / (1 - t1)))
            // “густое желе” можно back
            return uMin + (1.0 - uMin) * easeOutBack(p, s: 2.0)
        }
    }

    /// delta при отпускании: с текущего -> 0 (чтобы к моменту shrink был ровный 1.0/1.0)
    private func releaseDeltaToZero(at t: CGFloat, startDelta: CGFloat) -> CGFloat {
        let t1 = GlassSize.settlePhase1End
        if t <= t1 {
            let p = max(0, min(1, t / t1))
            return clampDelta(startDelta * (1.0 - easeOutCubic(p)))
        } else {
            return 0.0
        }
    }
    
    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        return 1.0 - pow(1.0 - t, 3.0)
    }

    private func makeGlassFrame(for index: Int, capsuleFrame: CGRect) -> CGRect? {
        guard index >= 0, index < self.tabBarNodeContainers.count else { return nil }
        let selectedNode = self.tabBarNodeContainers[index].imageNode
        guard selectedNode.isUserInteractionEnabled else { return nil }

        let visibleIndices: [Int] = self.tabBarNodeContainers.enumerated().compactMap { (i, c) in
            c.imageNode.isUserInteractionEnabled ? i : nil
        }
        guard let slot = visibleIndices.firstIndex(of: index) else { return nil }

        let count = max(1, visibleIndices.count)
        let tabWidth = floorToScreenPixels(capsuleFrame.width / CGFloat(count))
        let x = floorToScreenPixels(capsuleFrame.minX + CGFloat(slot) * tabWidth)

        return CGRect(
            x: x,
            y: capsuleFrame.minY,
            width: tabWidth,
            height: capsuleFrame.height
        )
    }

    private func applyCapsuleFrame(_ frame: CGRect) {
        let frame = snapRectToPixels(frame)
        self.glassNode.isHidden = false
        self.glassNode.frame = frame
        self.glassNode.shape = .roundedRect(cornerRadius: frame.height / 2.0 + 20)
    }
    
    private func stopGlassMove(completed: Bool) {
        self.glassMoveLink?.invalidate()
        self.glassMoveLink = nil
        self.isGlassAnimating = false

        self.glassAnimStretchAmplitude = 0.0
        self.glassAnimBrightnessAmplitude = 0.0
        self.glassNode.configuration.brightnessBoost = 0.0

        if completed {
            var finalBase = self.glassAnimBaseFrame
            finalBase.origin.x = self.glassAnimToX

            switch self.glassMotionPhase {
            case .tapMove:
                self.applyPhaseState(t: 1.0)
                let (sx, sy) = scalesFromDelta(0.0)
                self.applyCapsuleFrame(scaledAboutCenter(finalBase, scaleX: sx, scaleY: sy))

            case .dragReleaseSettle:
                self.applyReleasePhaseState(t: 1.0)
                self.applyCapsuleFrame(finalBase)
            }
        }
    }

    private func startGlassMove(to targetFrame: CGRect, fromX: CGFloat?) {
        if self.glassMoveLink != nil {
            self.stopGlassMove(completed: false)
        }

        let margin = GlassSize.primeMargin
        let currentX: CGFloat = fromX ?? (glassNode.isHidden ? targetFrame.origin.x : glassNode.frame.origin.x)
        
        if let window = self.view.window {
            let maxScale: CGFloat = GlassSize.primeMaxScale

            var fromFrame = targetFrame
            fromFrame.origin.x = currentX
            let toFrame = targetFrame

            let primeFrom = scaledAboutCenter(fromFrame, scale: maxScale)
            let primeTo   = scaledAboutCenter(toFrame,   scale: maxScale)

            let fromInWindow = self.view.convert(primeFrom, to: window)
            let toInWindow   = self.view.convert(primeTo,   to: window)

            let scale = window.screen.scale * glassNode.configuration.downscale
            glassEnvironment?.prime(rectsInWindow: [fromInWindow, toInWindow], scale: scale, margin: margin)
        }

        isGlassAnimating = true
        glassAnimStartTime = CACurrentMediaTime()
        self.glassAnimDuration = tapMoveDuration
        self.glassMotionPhase = .tapMove

        glassAnimBaseFrame = targetFrame
        glassAnimFromX = currentX
        glassAnimToX   = targetFrame.origin.x

        let dx = abs(targetFrame.origin.x - currentX)
        self.glassTapVelocityX = dx / CGFloat(max(0.001, self.glassAnimDuration))

        let maxStretch: CGFloat = 0.50
        let maxBrightness: CGFloat = 0.30

        self.glassAnimStretchAmplitude = maxStretch
        self.glassAnimBrightnessAmplitude = maxBrightness

        glassNode.configuration.brightnessBoost = 0.0

        self.glassNode.configuration.alpha = 0.0

        var startBase = targetFrame
        startBase.origin.x = currentX
        let (sx, sy) = scalesFromDelta(0.0)
        applyCapsuleFrame(scaledAboutCenter(startBase, scaleX: sx, scaleY: sy))
        applyPhaseState(t: 0.0)

        let link = CADisplayLink(target: self, selector: #selector(stepGlassMove))

        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: 60,
                preferred: 60
            )
        } else {
            link.preferredFramesPerSecond = 60
        }

        link.add(to: .main, forMode: .common)
        glassMoveLink = link
        
        // Force update snapshot (Only critical for tab bar)
        forceUpdateGlassSnapshot(targetFrame: targetFrame, currentX: currentX, margin: margin)
    }
    
    // Starts settle animation after drag release.
    // Keeps glass visible first, then fades back to highlight while snapping to a tab.
    func startGlassReleaseSettle(
        to targetFrame: CGRect,
        fromX: CGFloat,
        startDelta: CGFloat,
        startUniform: CGFloat,
        startBrightness: CGFloat,
        velocityX: CGFloat
    ) {
        if self.glassMoveLink != nil {
            self.stopGlassMove(completed: false)
        }

        self.glassMotionPhase = .dragReleaseSettle

        let toX = targetFrame.origin.x

        self.isGlassAnimating = true
        self.glassAnimStartTime = CACurrentMediaTime()

        self.glassAnimDuration = 0.20

        self.glassAnimStartDelta = startDelta

        self.glassAnimStartUniform = startUniform

        self.glassAnimBaseFrame = targetFrame
        self.glassAnimFromX = fromX
        self.glassAnimToX = toX

        self.glassAnimBrightnessAmplitude = max(0.0, min(0.20, startBrightness))

        self.glassNode.configuration.alpha = 1.0
        self.glassNode.configuration.brightnessBoost = Float(self.glassAnimBrightnessAmplitude)

        var fromBase = targetFrame
        fromBase.origin.x = fromX
        
        let (sx0, sy0) = scalesFromDelta(startDelta)
        let fromFrame = scaledAboutCenter(fromBase, scaleX: sx0 * startUniform, scaleY: sy0 * startUniform)
        self.applyCapsuleFrame(fromFrame)

        // Prime both ends to avoid crop misses during fast settle.
        if let window = self.view.window {
            let margin = GlassSize.primeMargin
            let maxScale: CGFloat = GlassSize.primeMaxScale

            let primeFrom = scaledAboutCenter(fromFrame, scale: maxScale)
            let primeTo   = scaledAboutCenter(targetFrame, scale: maxScale)

            let fromInWindow = self.view.convert(primeFrom, to: window)
            let toInWindow   = self.view.convert(primeTo,   to: window)

            let scale = window.screen.scale * self.glassNode.configuration.downscale
            self.glassEnvironment?.prime(rectsInWindow: [fromInWindow, toInWindow], scale: scale, margin: margin)
        }

        let link = CADisplayLink(target: self, selector: #selector(stepGlassMove))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        self.glassMoveLink = link
    }

    // Force update snapshot (Only critical for tab bar)
    private func forceUpdateGlassSnapshot(targetFrame: CGRect, currentX: CGFloat, margin: UIEdgeInsets) {
        self.forcePrimeWorkItem?.cancel()

        let startToken = self.glassAnimStartTime
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isGlassAnimating else { return }
            guard abs(self.glassAnimStartTime - startToken) < 0.0001 else { return }
            guard let window = self.view.window else { return }

            let maxScale: CGFloat = GlassSize.primeMaxScale

            var fromFrame = targetFrame
            fromFrame.origin.x = currentX
            let toFrame = targetFrame

            let primeFrom = scaledAboutCenter(fromFrame, scale: maxScale)
            let primeTo   = scaledAboutCenter(toFrame,   scale: maxScale)

            let fromInWindow = self.view.convert(primeFrom, to: window)
            let toInWindow   = self.view.convert(primeTo,   to: window)

            let scale = window.screen.scale * self.glassNode.configuration.downscale
            self.glassEnvironment?.prime(rectsInWindow: [fromInWindow, toInWindow], scale: scale, margin: margin)

            self.glassNode.renderCurrentFrame(now: CACurrentMediaTime())
        }

        self.forcePrimeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    @objc private func stepGlassMove() {
        let now = CACurrentMediaTime()
        let raw = (now - self.glassAnimStartTime) / self.glassAnimDuration
        let t = CGFloat(min(max(raw, 0.0), 1.0))

        let eased = easeOutCubic(t)
        let x = self.glassAnimFromX + (self.glassAnimToX - self.glassAnimFromX) * eased

        var base = self.glassAnimBaseFrame
        base.origin.x = x

        let delta: CGFloat
        let brightness: CGFloat
        var absScaleX: CGFloat = 1.0
        var absScaleY: CGFloat = 1.0

        switch self.glassMotionPhase {
        case .tapMove:
            delta = tapDelta(at: t)
            brightness = CGFloat(0.08)
            self.applyPhaseState(t: t)

            let (sx, sy) = scalesFromDelta(delta)
            absScaleX = sx
            absScaleY = sy

        case .dragReleaseSettle:
            delta = releaseDeltaToZero(at: t, startDelta: self.glassAnimStartDelta)

            let u = releaseUniform(at: t, startUniform: self.glassAnimStartUniform)

            let k = min(1.0, abs(delta) / GlassSize.deltaRange)
            brightness = CGFloat(0.08 + 0.22 * k)

            self.applyReleasePhaseState(t: t)

            let (sx0, sy0) = scalesFromDelta(delta)
            absScaleX = sx0 * u
            absScaleY = sy0 * u
        }

        let frame = scaledAboutCenter(base, scaleX: absScaleX, scaleY: absScaleY)
        self.applyCapsuleFrame(frame)
        self.glassNode.configuration.brightnessBoost = Float(brightness)

        if self.glassNode.configuration.alpha > 0.001 {
            self.glassNode.renderCurrentFrame(now: now)
        }

        if t >= 1.0 {
            self.stopGlassMove(completed: true)
        }
    }
    
    private func bounceGlassOnTap() {
        guard !isGlassAnimating else { return }

        let baseFrame = glassAnimBaseFrame == .zero ? glassNode.frame : glassAnimBaseFrame

        glassAnimStartTime = CACurrentMediaTime()

        glassAnimBaseFrame = baseFrame
        glassAnimFromX = baseFrame.origin.x
        glassAnimToX   = baseFrame.origin.x

        glassAnimStretchAmplitude = 0.12
        glassAnimBrightnessAmplitude = 0.12

        let link = CADisplayLink(target: self, selector: #selector(stepGlassMove))

        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: 60,
                preferred: 60
            )
        } else {
            link.preferredFramesPerSecond = 60
        }

        link.add(to: .main, forMode: .common)
        glassMoveLink = link
    }
}

// MARK: Glass animation helpers
private extension TabBarNode {
    
    private func liquidStretch(at t: CGFloat) -> CGFloat {
        let A = glassAnimStretchAmplitude
        if A <= 0.0001 { return 1.0 }

        let rampUpEnd: CGFloat = 0.25

        let holdEnd: CGFloat = 0.78

        if t <= rampUpEnd {
            let p = max(0.0, min(1.0, t / rampUpEnd))
            return 1.0 + A * easeOutCubic(p)
        } else if t <= holdEnd || self.isPressHolding {
            return 1.0 + A
        } else {
            let p = max(0.0, min(1.0, (t - holdEnd) / (1.0 - holdEnd)))
            let down = 1.0 - easeOutCubic(p)
            return 1.0 + A * down
        }
    }

    private func liquidBrightness(at t: CGFloat) -> CGFloat {
        let B = glassAnimBrightnessAmplitude
        if B <= 0.0001 { return 0.0 }

        let rampUpEnd: CGFloat = 0.25
        let holdEnd: CGFloat = 0.78

        if t <= rampUpEnd {
            let p = max(0.0, min(1.0, t / rampUpEnd))
            return B * easeOutCubic(p)
        } else if t <= holdEnd || self.isPressHolding {
            return B
        } else {
            let p = max(0.0, min(1.0, (t - holdEnd) / (1.0 - holdEnd)))
            let down = 1.0 - easeOutCubic(p)
            return B * down
        }
    }
    
    // Computes stretch for drag-release settle.
    // Starts at max stretch and decays with oscillation.
    private func releaseStretch(at t: CGFloat) -> CGFloat {
        let A = self.glassAnimStretchAmplitude
        if A <= 0.0001 { return 1.0 }

        let damping = exp(-2.1 * t)
        let oscillation = cos(2.0 * .pi * (2.2 * t)) // ~2 oscillations

        var value = 1.0 + A * damping * oscillation
        if t > 0.99 { value = 1.0 }

        return min(1.0 + A, max(1.0, value))
    }

    // Computes brightness for drag-release settle.
    // Starts near max brightness and decays as stretch settles.
    private func releaseBrightness(at t: CGFloat) -> CGFloat {
        let B = self.glassAnimBrightnessAmplitude
        if B <= 0.0001 { return 0.0 }

        let A = max(0.0001, self.glassAnimStretchAmplitude)
        let stretch = releaseStretch(at: t)
        let factor = min(1.0, abs(stretch - 1.0) / A)

        let damping = exp(-1.6 * t)
        return min(0.20, B * factor * damping)
    }

    // Controls crossfade for drag-release settle.
    // Keeps glass visible, then fades back to highlight near the end.
    private func applyReleasePhaseState(t: CGFloat) {
        let fadeStart: CGFloat = 0.70

        let glassAlpha: CGFloat

        if t < fadeStart {
            glassAlpha = 1.0
        } else {
            let p = max(0.0, min(1.0, (t - fadeStart) / (1.0 - fadeStart)))
            glassAlpha = 1.0 - p
        }

        self.glassNode.configuration.alpha = Float(glassAlpha)
    }

    private func scaledAboutCenter(_ frame: CGRect, scaleX: CGFloat, scaleY: CGFloat) -> CGRect {
        let c = frame.center
        let w = frame.width * scaleX
        let h = frame.height * scaleY
        return CGRect(
            x: c.x - w / 2.0,
            y: c.y - h / 2.0,
            width: w,
            height: h
        )
    }
    
    private func scaledAboutCenter(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let c = frame.center
        let w = frame.width * scale
        let h = frame.height * scale
        return CGRect(x: c.x - w / 2.0, y: c.y - h / 2.0, width: w, height: h)
    }

    private func applyPhaseState(t: CGFloat) {
        let phase1End: CGFloat = 0.18
        let phase3Start: CGFloat = 0.70

        let glassAlpha: CGFloat

        if t <= phase1End {
            let p = max(0.0, min(1.0, t / phase1End))
            glassAlpha = p
        } else if t < phase3Start || self.isPressHolding {
            glassAlpha = 1.0
        } else {
            let p = max(0.0, min(1.0, (t - phase3Start) / (1.0 - phase3Start)))
            glassAlpha = 1.0 - p
        }

        self.glassNode.configuration.alpha = Float(glassAlpha)
    }
}

// MARK: Glass Drag helpers
extension TabBarNode: UIGestureRecognizerDelegate {
    // Sets up pan-based drag for the glass.
    // Drag starts only after finger moves beyond a threshold.
    private func setupGlassDragGestureIfNeeded() {
        guard self.glassDragRecognizer == nil else { return }

        let gr = UIPanGestureRecognizer(target: self, action: #selector(handleGlassPan(_:)))
        gr.maximumNumberOfTouches = 1
        gr.cancelsTouchesInView = false
        gr.delegate = self

        self.view.addGestureRecognizer(gr)
        self.glassDragRecognizer = gr
    }
    
    // Arms drag only if gesture began on glass.
    // Starts drag when movement exceeds 10pt.
    @objc private func handleGlassPan(_ gr: UIPanGestureRecognizer) {
        let location = gr.location(in: self.view)
        let now = CACurrentMediaTime()

        switch gr.state {
        case .began:
            guard let capsuleFrame = self.lastCapsuleFrame else {
                self.isGlassDragArmed = false
                self.glassDragStartedOnGlass = false
                return
            }

            let corridorHit = capsuleFrame.insetBy(dx: 0, dy: -18).contains(location)
            self.isGlassDragArmed = corridorHit
            self.glassDragStartPoint = location

            self.glassDragStartedOnGlass = self.glassNode.frame.insetBy(dx: -18, dy: -12).contains(location)
            
            self.glassDragStartPoint = location

            if self.isGlassDragArmed {
                self.suppressTapUntil = now + 0.20
            }

        case .changed:
            guard self.isGlassDragArmed else { return }

            let dx = location.x - self.glassDragStartPoint.x
            let dy = location.y - self.glassDragStartPoint.y
            let dist = hypot(dx, dy)

            if !self.isGlassDragging {
                // If finger is mostly still, allow long-tap recognizer to win.
                if dist <= 10.0 { return }

                // Movement started -> drag wins, cancel long-tap recognizer.
                self.tapRecognizer?.cancel()
                beginGlassDrag(
                    at: location,
                    now: now,
                    startedOnGlass: self.glassDragStartedOnGlass
                )
            } else {
                cancelPendingTabSwitch()
                
                updateGlassDrag(at: location, now: now)
            }

        case .ended:
            self.isGlassDragArmed = false
            self.glassDragStartedOnGlass = false
            self.glassDragCatchUpUntil = 0
            if self.isGlassDragging {
                endGlassDrag(at: location, now: now, cancelled: false)
            }

        case .cancelled, .failed:
            self.isGlassDragArmed = false
            self.glassDragStartedOnGlass = false
            self.glassDragCatchUpUntil = 0

            if self.isGlassDragging {
                endGlassDrag(at: location, now: now, cancelled: true)
            }

        default:
            break
        }
    }

    // Starts dragging if the press began on the current glass hit area.
    // Interrupts running animation and primes snapshot for the whole corridor.
    private func beginGlassDrag(at location: CGPoint, now: CFTimeInterval, startedOnGlass: Bool) {
        guard let capsuleFrame = self.lastCapsuleFrame else { return }

        cancelPendingTabSwitch()
        self.tapRecognizer?.cancel()

        self.suppressTapUntil = now + 0.25

        if self.isGlassAnimating {
            self.stopGlassMove(completed: false)
        }

        stopGlassDragLink()

        self.suppressTabItemContextGestures()
        self.glassDragBaseFrame = (self.glassAnimBaseFrame == .zero) ? self.glassNode.frame : self.glassAnimBaseFrame
        self.isPressHolding = true
        self.isGlassDragging = true
        self.glassDragBoostStartTime = now

        
        self.glassDragTargetCenterX = location.x

        if startedOnGlass {
            self.glassDragCurrentCenterX = location.x
            self.glassDragCatchUpUntil = 0
        } else {
            self.glassDragCurrentCenterX = self.glassNode.frame.midX
            self.glassDragCatchUpUntil = now + 0.10
        }

        self.glassDragLastX = location.x
        self.glassDragLastTime = now
        self.glassDragVelocityX = 0

        primeSnapshotForDrag(capsuleFrame: capsuleFrame)

        self.glassNode.configuration.alpha = 1.0

        startGlassDragLink()
    }

    // Updates drag target and velocity; rendering is done on display-link.
    // This keeps stable 60fps even if touch events jitter.
    private func updateGlassDrag(at location: CGPoint, now: CFTimeInterval) {
        guard self.isGlassDragging else { return }

        let dt = max(0.0001, now - self.glassDragLastTime)
        let dx = location.x - self.glassDragLastX
        let v = dx / CGFloat(dt)

        self.glassDragVelocityX = self.glassDragVelocityX * 0.80 + v * 0.20
        self.glassDragTargetCenterX = location.x

        self.glassDragLastX = location.x
        self.glassDragLastTime = now
    }

    // Ends dragging and triggers tab selection only on release.
    // Starts a settle animation that shrinks/fades while moving to the nearest tab.
    private func endGlassDrag(at location: CGPoint, now: CFTimeInterval, cancelled: Bool) {
        guard self.isGlassDragging else { return }
        self.restoreTabItemContextGestures()

        self.isGlassDragging = false
        stopGlassDragLink()

        if cancelled {
            self.bounceGlassOnTap()
            return
        }

        guard let capsuleFrame = self.lastCapsuleFrame else {
            self.bounceGlassOnTap()
            return
        }

        self.suppressTapUntil = now + 0.20

        // Clamp release base frame to corridor.
        var releaseBase = self.glassDragBaseFrame
        let minX = capsuleFrame.minX
        let maxX = capsuleFrame.maxX - releaseBase.width
        let originX = location.x - releaseBase.width * 0.5
        releaseBase.origin.x = min(max(originX, minX), maxX)

        self.glassAnimBaseFrame = releaseBase

        // Compute nearest tab + its target frame (same logic as tap).
        let targetIndex = self.nearestTabIndex(at: location) ?? (self.selectedIndex ?? 0)
        guard let targetFrame = self.makeGlassFrame(for: targetIndex, capsuleFrame: capsuleFrame) else {
            self.bounceGlassOnTap()
            return
        }
        
        let currentBase = targetFrame

        let absScaleX = self.glassNode.frame.width  / max(1.0, currentBase.width)
        let absScaleY = self.glassNode.frame.height / max(1.0, currentBase.height)

        let startDelta = deltaFromScales(scaleX: absScaleX, scaleY: absScaleY)
        let currentCenterX = self.glassNode.frame.midX

        let shouldSwitch = (targetIndex != self.selectedIndex)
        
        let denom: CGFloat = max(0.001, (GlassSize.baseScale - startDelta))
        let startUniform = max(minUniformToReachTabSize, min(1.5, absScaleX / denom))
        let fromX = currentCenterX - currentBase.width * 0.5

        self.startGlassReleaseSettle(
            to: targetFrame,
            fromX: fromX,
            startDelta: startDelta,
            startUniform: startUniform,
            startBrightness: CGFloat(self.glassNode.configuration.brightnessBoost),
            velocityX: self.glassDragVelocityX
        )

        if shouldSwitch {
            self.pendingSwitchIsLongTap = false
            self.scheduleTabSwitch(index: targetIndex)
        }
    }
    
    // Disables tab-item context gestures while dragging glass.
    // Prevents context overlay from appearing during pan/drag.
    private func suppressTabItemContextGestures() {
        for container in self.tabBarNodeContainers {
            container.imageNode.containerNode.cancelGesture()
            container.imageNode.containerNode.isGestureEnabled = false
        }
    }

    // Restores tab-item context gestures after drag ends.
    // Uses tabBarItems contextActionType as the source of truth.
    private func restoreTabItemContextGestures() {
        let count = min(self.tabBarItems.count, self.tabBarNodeContainers.count)
        guard count > 0 else { return }

        for i in 0 ..< count {
            let enabled = self.tabBarItems[i].contextActionType != .none
            self.tabBarNodeContainers[i].imageNode.containerNode.isGestureEnabled = enabled
        }
    }


    // Starts 60fps loop for drag rendering.
    // Uses common runloop mode to keep updates during interactions.
    private func startGlassDragLink() {
        let link = CADisplayLink(target: self, selector: #selector(stepGlassDrag))

        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        } else {
            link.preferredFramesPerSecond = 60
        }

        link.add(to: .main, forMode: .common)
        self.glassDragLink = link
    }

    // Stops drag display-link loop.
    // Keeps glass at its last frame so animation can start from there.
    private func stopGlassDragLink() {
        self.glassDragLink?.invalidate()
        self.glassDragLink = nil
    }

    // Renders glass during drag at 60fps: follow finger, clamp, and render snapshot.
    // Brightness/height are near-max while the user controls the glass.
    @objc private func stepGlassDrag() {
        guard self.isGlassDragging, let capsuleFrame = self.lastCapsuleFrame else {
            stopGlassDragLink()
            return
        }

        let now = CACurrentMediaTime()

        // Smooth follow to avoid jitter.
        let follow: CGFloat = (now < self.glassDragCatchUpUntil) ? 0.90 : 0.35
        self.glassDragCurrentCenterX += (self.glassDragTargetCenterX - self.glassDragCurrentCenterX) * follow

        var base = self.glassDragBaseFrame

        // Ramp-in (старт “накачки” при начале drag)
        let rampDuration: CGFloat = 0.20
        let raw = CGFloat(now - self.glassDragBoostStartTime)
        let p = max(0.0, min(1.0, raw / rampDuration))
        let ramp = easeOutCubic(p)

        // Скорость -> фактор 0..1
        let screenW = self.view.bounds.width > 1 ? self.view.bounds.width : UIScreen.main.bounds.width
        let vRef = GlassSize.referenceVelocity(screenWidth: screenW)
        let speed = abs(self.glassDragVelocityX)
        let speedFactor = max(0.0, min(1.0, speed / max(1.0, vRef)))

        // Итоговая деформация зависит и от ramp, и от скорости
        let deform = ramp * speedFactor

        // delta: быстрее => больше в высоту (delta>0) и меньше в ширину
        let deltaTarget = GlassSize.deltaRange * deform

        // wobble вокруг цели (тоже масштабируем по скорости)
        let wobbleAmp = GlassSize.dragWobbleAmpAtMaxSpeed * deform
        let wobble = sin(CGFloat(now) * 2.0 * .pi * GlassSize.dragWobbleFreqHz) * wobbleAmp

        let delta = clampDelta(deltaTarget + wobble)
        let (sx, sy) = scalesFromDelta(delta)

        // Clamp по scaledWidth (иначе при изменении ширины вылезешь за capsule)
        let scaledWidth = base.width * sx
        let minCenterX = capsuleFrame.minX + scaledWidth * 0.5
        let maxCenterX = capsuleFrame.maxX - scaledWidth * 0.5
        self.glassDragCurrentCenterX = min(max(self.glassDragCurrentCenterX, minCenterX), maxCenterX)

        base.origin.x = self.glassDragCurrentCenterX - base.width * 0.5
        self.glassDragBaseFrame = base

        let frame = scaledAboutCenter(base, scaleX: sx, scaleY: sy)

        // Brightness (можешь подкрутить, но уже нормально ложится)
        let maxBrightness: Float = 0.30
        let b = max(0.0, min(1.0, deform))
        let brightness: Float = maxBrightness * Float(b)

        self.applyCapsuleFrame(frame)
        self.glassNode.configuration.alpha = 1.0
        self.glassNode.configuration.brightnessBoost = brightness

        self.glassNode.renderCurrentFrame(now: now)
    }


    // Primes the shared snapshot for the full drag corridor.
    // This prevents crop misses when user drags fast.
    private func primeSnapshotForDrag(capsuleFrame: CGRect) {
        guard let window = self.view.window else { return }

        let margin = GlassSize.primeMargin
        let maxScale: CGFloat = GlassSize.primeMaxScale

        let primeRect = scaledAboutCenter(capsuleFrame, scale: maxScale)
        let rectInWindow = self.view.convert(primeRect, to: window)

        let scale = window.screen.scale * self.glassNode.configuration.downscale
        self.glassEnvironment?.prime(rectsInWindow: [rectInWindow], scale: scale, margin: margin)

        self.glassNode.renderCurrentFrame(now: CACurrentMediaTime())
    }
    
    private func cancelPendingTabSwitch() {
        pendingSwitchWorkItem?.cancel()
        pendingSwitchWorkItem = nil
        pendingSwitchIndex = nil
        pendingSwitchIsLongTap = false
    }

    private func scheduleTabSwitch(index: Int) {
        cancelPendingTabSwitch()

        pendingSwitchIndex = index
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingSwitchIndex == index else { return }

            // чтобы selectedIndex.didSet не запускал второй moveGlass (у тебя это уже учтено)
            self.suppressNextSelectedIndexMove = true  // см. didSet :contentReference[oaicite:3]{index=3}
            self.itemSelected(index, self.pendingSwitchIsLongTap, self.sourceNodesForItemSelected(at: index))

            self.pendingSwitchWorkItem = nil
            self.pendingSwitchIndex = nil
            self.pendingSwitchIsLongTap = false
        }

        pendingSwitchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + self.glassAnimDuration, execute: work)
    }

}


// ------------------------------------------------------
// MARK: Separator (чисто копипастю чтобы пофиксить билд)
// ------------------------------------------------------


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

    public var refraction: Float = 0.4
    public var chroma: Float = 0.10

    public var shadowOffset: Float = 10.0   // px (в текстуре)
    public var shadowBlur: Float = 18.0     // px
    public var shadowStrength: Float = 0.06 // 0..1

    public var rimThickness: Float = 1.5    // px
    public var rimStrength: Float = 0.9     // 0..1

    public var alpha: Float = 1.0
    public var brightnessBoost: Float = 0.0

    public init() {}
}

public enum GlassSize {
    public static let minScale: CGFloat  = 0.8
    public static let baseScale: CGFloat = 1.2
    public static let maxScale: CGFloat  = 1.6

    public static let deltaRange: CGFloat = 0.4
    
    public static let settleDuration: CFTimeInterval = 0.20
    public static let settlePhase1End: CGFloat = 0.60
    public static let settlePhase1Delta: CGFloat = -0.10

    public static let dragWobbleFreqHz: CGFloat = 6.0
    public static let dragWobbleAmpAtMaxSpeed: CGFloat = 0.04

    public static func referenceVelocity(screenWidth: CGFloat) -> CGFloat {
        screenWidth / 1.2
    }

    public static let primeMaxScale: CGFloat = 1.55
    public static let primeMargin = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
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

        if let s = snapshot,
           abs(s.scale - scale) < 0.0001,
           s.rectInWindow.contains(rectInWindow),
           let cropped = crop(snapshot: s, to: rectInWindow) {
            return cropped
        }

        let shouldBypassRateLimit = (snapshot == nil) // первый снимок — всегда делаем
        if shouldBypassRateLimit || canRefreshSnapshot(now: now) {
            
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

        if let s = snapshot,
           abs(s.scale - scale) < 0.0001,
           s.rectInWindow.contains(rectInWindow),
           let cropped = crop(snapshot: s, to: rectInWindow) {
            return cropped
        }

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

import Metal
import MetalKit
import simd
import UIKit

// Couldn't build .metal in separate file
private enum LiquidGlassShaderSource {
    static let metal: String = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float2 size;
        float2 center;
        float  refraction;
        float  chroma;

        float  shadowOffset;
        float  shadowBlur;
        float  shadowStrength;

        float  rimThickness;
        float  rimStrength;
        float2 lightDir;

        float  alpha;

        float  brightnessBoost;   // NEW 0..0.2
        float  edgeBlurWidthPx;     // ширина ободка (в пикселях), = 10pt * scale
        float  edgeBlurRadiusPx;    // “сила” размытия на самой границе (в пикселях)
        float  edgeNoiseStrength;   // шум в ободке (0..~0.06)
        float  edgeBlurMix;         // сколько подмешивать blur (0..1)

        uint   shapeType;
        float  cornerRadiusPx;
        float2 _pad;
    };

    vertex VOut lg_vertex(const device float *v [[buffer(0)]], uint vid [[vertex_id]]) {
        VOut o;
        float2 pos = float2(v[vid * 4 + 0], v[vid * 4 + 1]);
        float2 uv  = float2(v[vid * 4 + 2], v[vid * 4 + 3]);
        o.position = float4(pos, 0.0, 1.0);
        o.uv = uv;
        return o;
    }

    static inline float sdRoundedRect(float2 p, float2 halfSize, float r) {
        float2 q = abs(p) - halfSize + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }
    
    static inline float hash21(float2 p) {
        // быстрый псевдорандом 0..1
        float h = dot(p, float2(127.1, 311.7));
        return fract(sin(h) * 43758.5453123);
    }

    fragment half4 lg_fragment(
        VOut in [[stage_in]],
        constant Uniforms& u [[buffer(0)]],
        texture2d<half, access::sample> bg [[texture(0)]],
        sampler s [[sampler(0)]]
    ) {
        float2 p = in.uv * u.size;
        float2 c = u.center * u.size;
        float2 toCenterPx = (p - c);

        // --- Shape SDF (circle / rounded rect) ---
        float dist;
        if (u.shapeType == 0) {
            float radius = min(u.size.x, u.size.y) * 0.5;
            dist = length(toCenterPx) - radius;
        } else {
            float2 halfSize = (u.size * 0.5) - float2(1.0);
            dist = sdRoundedRect(toCenterPx, halfSize, u.cornerRadiusPx);
        }

        // Anti-aliased inside mask (rounded corners clipping)
        float aa = 1.0;
        float inside = smoothstep(0.0, -aa, dist);

        // ============================================================
        // EDGE-BASED REFRACTION + EDGE-ONLY CHROMA  (target look)
        // ============================================================

        float radiusForFalloff = min(u.size.x, u.size.y) * 0.5;
        float normalizedDist = clamp(length(toCenterPx) / max(radiusForFalloff, 1.0), 0.0, 1.0);

        float2 dir = normalize(toCenterPx + float2(1e-5));

        // 0 in the center, rising sharply towards the edges
        const float edgeStart = 0.45;
        const float edgeExp   = 6.0;
        float edgeMask = smoothstep(edgeStart, 1.0, normalizedDist);
        float edgeSharp = pow(edgeMask, edgeExp);

        // Offset in pixels (scaled by radius)
        float2 refractedOffsetPx = dir * (edgeSharp * u.refraction * radiusForFalloff);

        // Chrome only on the edges
        float chromaK = edgeSharp * u.chroma;
        float2 offR = refractedOffsetPx * (1.0 + chromaK);
        float2 offB = refractedOffsetPx * (1.0 - chromaK);

        float2 uvG = (p + refractedOffsetPx) / u.size;
        float2 uvR = (p + offR) / u.size;
        float2 uvB = (p + offB) / u.size;

        half4 colG = bg.sample(s, uvG);
        half4 colR = bg.sample(s, uvR);
        half4 colB = bg.sample(s, uvB);

        half4 outCol = colG;
        outCol.r = colR.r;
        outCol.b = colB.b;

        // Slight milkiness/lightening INSIDE the lens
        float extraLift = clamp(u.brightnessBoost, 0.0, 0.10);
        float lift = 0.04 + extraLift; // базовый + динамический
        lift = clamp(lift, 0.0, 0.14); // не выходим за 14%
    
        // ---- lens blur (UIVisualEffect-ish) ----
        // Blur should be here
        
        // Important: the basic "snapshot" is shown only inside the form
        outCol.rgb *= inside;

        // Basic alpha is strictly based on the shape mask (clipping rounded corners)
        outCol.a = half(inside * u.alpha);        

        // ============================================================
        // Symmetrical rim + border (without unilateral rimBias)
        // ============================================================

        float edgeAbs = abs(dist);

        // soft rim inside
        float rim = smoothstep(u.rimThickness, 0.0, edgeAbs) * u.rimStrength;
        outCol.rgb += half3(1.05h, 1.05h, 1.10h) * half(rim) * half(inside);

        // thin edge border (360°)
        const float borderW = 1.0;
        const float borderAlpha = 0.10;
        half3 borderColor = half3(0.92h, 0.96h, 1.00h);

        float border = smoothstep(borderW, 0.0, edgeAbs);
        outCol.rgb = mix(outCol.rgb, borderColor, half(borderAlpha * border * u.alpha));
        outCol.a = max(outCol.a, half(borderAlpha * border * u.alpha));

        if (outCol.a <= 0.001h) {
            return half4(0.0h);
        }

        return outCol;
    }

    """
}
//float nd = normalizedDist;                 // 0..1
//float edge = edgeSharp;                    // уже есть
//float blurK = inside * (0.20 + 0.80 * edge); // blur больше у края, но есть и в центре
//
//// радиус blur в пикселях: 1..~8 (тюнится)
//float blurPx = mix(1.2, 8.0, blurK);
//float2 texel = (blurPx / u.size);
//
//// 9 taps (крест + диагонали)
//half3 s0 = bg.sample(s, uvG).rgb;
//half3 s1 = bg.sample(s, uvG + texel * float2( 1, 0)).rgb;
//half3 s2 = bg.sample(s, uvG + texel * float2(-1, 0)).rgb;
//half3 s3 = bg.sample(s, uvG + texel * float2( 0, 1)).rgb;
//half3 s4 = bg.sample(s, uvG + texel * float2( 0,-1)).rgb;
//half3 s5 = bg.sample(s, uvG + texel * float2( 1, 1)).rgb;
//half3 s6 = bg.sample(s, uvG + texel * float2(-1, 1)).rgb;
//half3 s7 = bg.sample(s, uvG + texel * float2( 1,-1)).rgb;
//half3 s8 = bg.sample(s, uvG + texel * float2(-1,-1)).rgb;
//
//half3 blurred = (s0*2.0h + s1+s2+s3+s4 + s5+s6+s7+s8) / half(10.0);
//
//// подмешиваем blur к текущему outCol
//outCol.rgb = mix(outCol.rgb, blurred, half(blurK * 0.85));

final class LiquidGlassRenderer: NSObject, MTKViewDelegate {

    // MARK: Public
    var configuration: LiquidGlassConfiguration = .init()
    var shape: LiquidGlassShape = .circle

    // MARK: Private
    private unowned let mtkView: MTKView
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary

    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let vertexBuffer: MTLBuffer

    private var backgroundTexture: MTLTexture?
    private let textureLoader: MTKTextureLoader

    init(mtkView: MTKView) {
        guard let dev = mtkView.device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device is not available")
        }
        self.mtkView = mtkView
        self.device = dev

        guard let q = dev.makeCommandQueue() else { fatalError("No command queue") }
        self.queue = q

        let options = MTLCompileOptions()
        // options.languageVersion = .version2_4

        do {
            self.library = try dev.makeLibrary(source: LiquidGlassShaderSource.metal, options: options)
        } catch {
            fatalError("Failed to compile LiquidGlass shader: \(error)")
        }

        self.textureLoader = MTKTextureLoader(device: dev)

        // Fullscreen quad (pos.xy, uv.xy)
        let quad: [Float] = [
            -1, -1,  0, 1,
             1, -1,  1, 1,
            -1,  1,  0, 0,
             1,  1,  1, 0
        ]
        self.vertexBuffer = dev.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<Float>.size, options: [])!

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.sampler = dev.makeSamplerState(descriptor: samplerDesc)!

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library.makeFunction(name: "lg_vertex")
        pipelineDesc.fragmentFunction = library.makeFunction(name: "lg_fragment")
        pipelineDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        let att = pipelineDesc.colorAttachments[0]!
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .sourceAlpha
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.sourceAlphaBlendFactor = .one
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.pipeline = try! dev.makeRenderPipelineState(descriptor: pipelineDesc)
        
        super.init()
        mtkView.delegate = self
    }

    func updateBackground(cgImage: CGImage) {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft
        ]
        self.backgroundTexture = try? textureLoader.newTexture(cgImage: cgImage, options: options)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = mtkView.currentDrawable,
              let rpd = mtkView.currentRenderPassDescriptor,
              let bg = backgroundTexture
        else { return }

        // uniforms
        var u = Uniforms()
        u.size = SIMD2<Float>(Float(bg.width), Float(bg.height))
        u.center = SIMD2<Float>(0.5, 0.5)
        u.refraction = configuration.refraction
        u.chroma = configuration.chroma
        u.shadowOffset = configuration.shadowOffset
        u.shadowBlur = configuration.shadowBlur
        u.shadowStrength = configuration.shadowStrength
        u.rimThickness = configuration.rimThickness
        u.rimStrength = configuration.rimStrength
//        u.lightDir = simd_normalize(configuration.lightDir)
        u.alpha = configuration.alpha
        u.brightnessBoost = configuration.brightnessBoost
        
        let pxPerPt = max(Float(bg.width) / Float(mtkView.drawableSize.width), 1.0)

        u.edgeBlurWidthPx   = 10.0 * pxPerPt
        u.edgeBlurRadiusPx  = 8.0 * pxPerPt
        u.edgeNoiseStrength = 0.035
        u.edgeBlurMix       = 1.0

        switch shape {
        case .circle:
            u.shapeType = 0
            u.cornerRadiusPx = 0
        case .roundedRect(let r):
            u.shapeType = 1
            // конвертим cornerRadius из points в пиксели текстуры (примерно)
            let scale = max(Float(bg.width) / Float(mtkView.drawableSize.width), 1.0)
            u.cornerRadiusPx = Float(r) * scale
        }

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        enc.setFragmentTexture(bg, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }
}

// MARK: - Metal uniforms (must match .metal)

struct Uniforms {
    var size: SIMD2<Float> = .zero
    var center: SIMD2<Float> = .init(0.5, 0.5)

    var refraction: Float = 0
    var chroma: Float = 0

    var shadowOffset: Float = 0
    var shadowBlur: Float = 0
    var shadowStrength: Float = 0

    var rimThickness: Float = 0
    var rimStrength: Float = 0
    var lightDir: SIMD2<Float> = .init(-0.5, -0.8)

    var alpha: Float = 1

    /// 0..0.2 — extra lift к «молочности»
    var brightnessBoost: Float = 0      // NEW
    
    var edgeBlurWidthPx: Float = 0
    var edgeBlurRadiusPx: Float = 0
    var edgeNoiseStrength: Float = 0
    var edgeBlurMix: Float = 0

    // 0 circle, 1 roundedRect
    var shapeType: UInt32 = 0
    var cornerRadiusPx: Float = 0

    // padding для выравнивания с metal Uniforms
    var _pad: SIMD2<Float> = .zero
}

