//
//  GameMTKView_iOS.swift
//  ConstructorIOS
//
//  Created for Constructor (1997) Native iPadOS Apple Silicon Wrapper.
//  Subclase de MTKView (UIKit) optimizada para renderizado Metal a 60 FPS
//  y captura táctil directa, gestos de 2 dedos, Apple Pencil y teclado físico.
//

import UIKit
import MetalKit

public final class GameMTKView_iOS: MTKView, UIPencilInteractionDelegate {

    public let renderer: MetalRenderer
    public var inputManager: InputManager_iOS?

    // Gestos
    private var twoFingerTapGesture: UITapGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var twoFingerPanGesture: UIPanGestureRecognizer!
    private var hoverGesture: UIHoverGestureRecognizer?

    public init(frame frameRect: CGRect, device: MTLDevice, renderer: MetalRenderer, inputManager: InputManager_iOS? = nil) {
        self.renderer = renderer
        self.inputManager = inputManager
        super.init(frame: frameRect, device: device)
        setupViewConfiguration()
        setupGestureRecognizers()
    }

    public required init(coder: NSCoder) {
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Apple Silicon Metal device no disponible.")
        }
        do {
            self.renderer = try MetalRenderer(device: defaultDevice)
        } catch {
            fatalError("Fallo al inicializar MetalRenderer: \(error)")
        }
        super.init(coder: coder)
        self.device = defaultDevice
        setupViewConfiguration()
        setupGestureRecognizers()
    }

    private func setupViewConfiguration() {
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        self.delegate = renderer

        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 60

        self.isMultipleTouchEnabled = true
        self.isOpaque = true
        self.backgroundColor = .black
    }

    private func setupGestureRecognizers() {
        // 1. Toque con 2 dedos = Clic derecho instantáneo
        twoFingerTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTapGesture.numberOfTouchesRequired = 2
        twoFingerTapGesture.cancelsTouchesInView = false
        twoFingerTapGesture.delaysTouchesBegan = false
        self.addGestureRecognizer(twoFingerTapGesture)

        // 2. Pulsación larga = Clic derecho alternativo
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.35
        longPressGesture.cancelsTouchesInView = false
        longPressGesture.delaysTouchesBegan = false
        self.addGestureRecognizer(longPressGesture)

        // 3. Arrastre con 2 dedos = Paneo del mapa (desplazamiento de cámara)
        twoFingerPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPanGesture(_:)))
        twoFingerPanGesture.minimumNumberOfTouches = 2
        twoFingerPanGesture.maximumNumberOfTouches = 2
        twoFingerPanGesture.cancelsTouchesInView = true
        twoFingerPanGesture.delaysTouchesBegan = false
        self.addGestureRecognizer(twoFingerPanGesture)

        // Evitar que arrastrar con 2 dedos dispare accidentalmente el toque con 2 dedos (clic derecho)
        twoFingerTapGesture.require(toFail: twoFingerPanGesture)

        // 4. Apple Pencil: Doble toque en el lápiz = Clic derecho
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        self.addInteraction(pencilInteraction)

        // 5. Apple Pencil Hover (iPad Pro M2/M4)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        self.addGestureRecognizer(hover)
        self.hoverGesture = hover
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        print("📐 [GameMTKView] layoutSubviews bounds=\(self.bounds.size), targetAspect=\(renderer.targetAspectRatio)")
        inputManager?.updateViewport(bounds: self.bounds.size, targetAspect: renderer.targetAspectRatio)
    }

    // MARK: - Receptores de Gestos

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            let location = gesture.location(in: self)
            print("✌️ [Gesture] TwoFingerTap at \(location)")
            inputManager?.triggerRightClick(at: location)
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let location = gesture.location(in: self)
            print("⏱️ [Gesture] LongPress at \(location)")
            inputManager?.triggerRightClick(at: location)
        }
    }

    @objc private func handleTwoFingerPanGesture(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            print("✌️ [Gesture] TwoFingerPan began")
            inputManager?.cancelTouch()
            inputManager?.beginTwoFingerPan()
            gesture.setTranslation(.zero, in: self)
        case .changed:
            let delta = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            let velocity = gesture.velocity(in: self)
            inputManager?.handleTwoFingerPanDelta(delta: delta, velocity: velocity)
        case .ended:
            let velocity = gesture.velocity(in: self)
            print("✌️ [Gesture] TwoFingerPan ended with velocity=\(velocity)")
            inputManager?.endTwoFingerPan(velocity: velocity)
        case .cancelled:
            print("✌️ [Gesture] TwoFingerPan cancelled")
            inputManager?.endTwoFingerPan(velocity: .zero)
        default:
            break
        }
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        let location = gesture.location(in: self)
        inputManager?.handlePencilHover(at: location)
    }

    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        inputManager?.triggerRightClick()
    }

    // MARK: - Toque Directo (Direct Touch Events)

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let primaryTouch = touches.first else { return }

        // Si son 2 dedos, el gesto de 2 dedos o pan toma precedencia
        if event?.allTouches?.count ?? 0 > 1 {
            return
        }

        let point = primaryTouch.location(in: self)
        print("📱 [GameMTKView] touchesBegan at: \(point)")
        inputManager?.handleTouchBegan(at: point, isPrimary: true)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let primaryTouch = touches.first else { return }

        if event?.allTouches?.count ?? 0 > 1 {
            return
        }

        let point = primaryTouch.location(in: self)
        let prevPoint = primaryTouch.previousLocation(in: self)
        print("📱 [GameMTKView] touchesMoved to: \(point)")
        inputManager?.handleTouchMoved(to: point, previousPoint: prevPoint)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        print("📱 [GameMTKView] touchesEnded")
        inputManager?.handleTouchEnded()
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        print("📱 [GameMTKView] touchesCancelled")
        inputManager?.handleTouchEnded()
    }

    // MARK: - Teclado Físico (Magic Keyboard / Smart Keyboard)

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                let retroKey = retroKey(for: key.keyCode)
                if retroKey != 0 {
                    inputManager?.setKey(retroKey, isDown: true)
                }
            }
        }
        super.pressesBegan(presses, with: event)
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let key = press.key {
                let retroKey = retroKey(for: key.keyCode)
                if retroKey != 0 {
                    inputManager?.setKey(retroKey, isDown: false)
                }
            }
        }
        super.pressesEnded(presses, with: event)
    }

    private func retroKey(for keyCode: UIKeyboardHIDUsage) -> UInt32 {
        switch keyCode {
        case .keyboardEscape: return UInt32(RETROK_ESCAPE.rawValue)
        case .keyboardReturnOrEnter: return UInt32(RETROK_RETURN.rawValue)
        case .keyboardSpacebar: return UInt32(RETROK_SPACE.rawValue)
        case .keyboardTab: return UInt32(RETROK_TAB.rawValue)
        case .keyboardDeleteOrBackspace: return UInt32(RETROK_BACKSPACE.rawValue)
        case .keyboardUpArrow: return UInt32(RETROK_UP.rawValue)
        case .keyboardDownArrow: return UInt32(RETROK_DOWN.rawValue)
        case .keyboardLeftArrow: return UInt32(RETROK_LEFT.rawValue)
        case .keyboardRightArrow: return UInt32(RETROK_RIGHT.rawValue)
        case .keyboardF1: return UInt32(RETROK_F1.rawValue)
        case .keyboardF2: return UInt32(RETROK_F2.rawValue)
        case .keyboardF3: return UInt32(RETROK_F3.rawValue)
        case .keyboardF4: return UInt32(RETROK_F4.rawValue)
        case .keyboardF5: return UInt32(RETROK_F5.rawValue)
        case .keyboardF6: return UInt32(RETROK_F6.rawValue)
        case .keyboardF7: return UInt32(RETROK_F7.rawValue)
        case .keyboardF8: return UInt32(RETROK_F8.rawValue)
        case .keyboardF9: return UInt32(RETROK_F9.rawValue)
        case .keyboardF10: return UInt32(RETROK_F10.rawValue)
        case .keyboardF11: return UInt32(RETROK_F11.rawValue)
        case .keyboardF12: return UInt32(RETROK_F12.rawValue)
        case .keyboardA: return UInt32(RETROK_a.rawValue)
        case .keyboardB: return UInt32(RETROK_b.rawValue)
        case .keyboardC: return UInt32(RETROK_c.rawValue)
        case .keyboardD: return UInt32(RETROK_d.rawValue)
        case .keyboardE: return UInt32(RETROK_e.rawValue)
        case .keyboardF: return UInt32(RETROK_f.rawValue)
        case .keyboardG: return UInt32(RETROK_g.rawValue)
        case .keyboardH: return UInt32(RETROK_h.rawValue)
        case .keyboardI: return UInt32(RETROK_i.rawValue)
        case .keyboardJ: return UInt32(RETROK_j.rawValue)
        case .keyboardK: return UInt32(RETROK_k.rawValue)
        case .keyboardL: return UInt32(RETROK_l.rawValue)
        case .keyboardM: return UInt32(RETROK_m.rawValue)
        case .keyboardN: return UInt32(RETROK_n.rawValue)
        case .keyboardO: return UInt32(RETROK_o.rawValue)
        case .keyboardP: return UInt32(RETROK_p.rawValue)
        case .keyboardQ: return UInt32(RETROK_q.rawValue)
        case .keyboardR: return UInt32(RETROK_r.rawValue)
        case .keyboardS: return UInt32(RETROK_s.rawValue)
        case .keyboardT: return UInt32(RETROK_t.rawValue)
        case .keyboardU: return UInt32(RETROK_u.rawValue)
        case .keyboardV: return UInt32(RETROK_v.rawValue)
        case .keyboardW: return UInt32(RETROK_w.rawValue)
        case .keyboardX: return UInt32(RETROK_x.rawValue)
        case .keyboardY: return UInt32(RETROK_y.rawValue)
        case .keyboardZ: return UInt32(RETROK_z.rawValue)
        case .keyboard1: return UInt32(RETROK_1.rawValue)
        case .keyboard2: return UInt32(RETROK_2.rawValue)
        case .keyboard3: return UInt32(RETROK_3.rawValue)
        case .keyboard4: return UInt32(RETROK_4.rawValue)
        case .keyboard5: return UInt32(RETROK_5.rawValue)
        case .keyboard6: return UInt32(RETROK_6.rawValue)
        case .keyboard7: return UInt32(RETROK_7.rawValue)
        case .keyboard8: return UInt32(RETROK_8.rawValue)
        case .keyboard9: return UInt32(RETROK_9.rawValue)
        case .keyboard0: return UInt32(RETROK_0.rawValue)
        default: return 0
        }
    }
}
