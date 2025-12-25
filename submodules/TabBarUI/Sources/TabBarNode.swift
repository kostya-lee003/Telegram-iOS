import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Display
import UIKitRuntimeUtils
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import LiquidGlassUI

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
        // glass
        let frame = snapRectToPixels(frame)
        self.glassNode.isHidden = false
        self.glassNode.frame = frame
        self.glassNode.shape = .roundedRect(cornerRadius: frame.height / 2.0 + 20)
    }
    
    private func stopGlassMove(completed: Bool) {
        self.glassMoveLink?.invalidate()
        self.glassMoveLink = nil
        self.isGlassAnimating = false

        // сбрасываем liquid-состояние
        self.glassAnimStretchAmplitude = 0.0
        self.glassAnimBrightnessAmplitude = 0.0
        self.glassNode.configuration.brightnessBoost = 0.0

        if completed {
            var finalBase = self.glassAnimBaseFrame
            finalBase.origin.x = self.glassAnimToX

            self.applyPhaseState(t: 1.0)
            let (sx, sy) = scalesFromDelta(0.0)
            self.applyCapsuleFrame(scaledAboutCenter(finalBase, scaleX: sx, scaleY: sy))
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

        let maxStretch: CGFloat = 0.50    // +60% к высоте при очень быстрой анимации
        let maxBrightness: CGFloat = 0.30 // +40% яркости максимум

        self.glassAnimStretchAmplitude = maxStretch
        self.glassAnimBrightnessAmplitude = maxBrightness

        // на старте никаких лишних бликов
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
        self.glassAnimDuration = GlassSize.settleDuration
        self.glassAnimStartDelta = startDelta

        self.glassAnimBaseFrame = targetFrame
        self.glassAnimFromX = fromX
        self.glassAnimToX = toX

        self.glassAnimBrightnessAmplitude = max(0.0, min(0.20, startBrightness))

        // Keep glass visible immediately (release starts from "manual control" look).
        self.glassNode.configuration.alpha = 1.0
        self.glassNode.configuration.brightnessBoost = Float(self.glassAnimBrightnessAmplitude)

        var fromBase = targetFrame
        fromBase.origin.x = fromX
        let (sx, sy) = scalesFromDelta(startDelta)
        let fromFrame = scaledAboutCenter(fromBase, scaleX: sx, scaleY: sy)
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

        switch self.glassMotionPhase {
        case .tapMove:
            delta = tapDelta(at: t)
            brightness = CGFloat(0.08)
            self.applyPhaseState(t: t)

        case .dragReleaseSettle:
            delta = releaseDelta(at: t, startDelta: self.glassAnimStartDelta)

            let k = min(1.0, abs(delta) / GlassSize.deltaRange)
            brightness = CGFloat(0.08 + 0.22 * k)
            self.applyReleasePhaseState(t: t)
        }

        let (sx, sy) = scalesFromDelta(delta)
        let frame = scaledAboutCenter(base, scaleX: sx, scaleY: sy)
        self.applyCapsuleFrame(frame)

        self.glassNode.configuration.brightnessBoost = Float(brightness)

        if self.glassNode.configuration.alpha > 0.001 {
            self.glassNode.renderCurrentFrame(now: now)
        }

        if t >= 1.0 - 0.0001 {
            self.stopGlassMove(completed: true)
            self.glassMotionPhase = .tapMove
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

        // Switch screen ONLY on release.
        if targetIndex != self.selectedIndex {
            self.suppressNextSelectedIndexMove = true
            self.itemSelected(targetIndex, false, self.sourceNodesForItemSelected(at: targetIndex))
        }

        let currentCenterX = self.glassNode.frame.midX

        // startUniform: absScaleX ≈ (baseScale - delta) * uniform
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
