//
//  InputManager_iOS.swift
//  ConstructorIOS
//
//  Created for Constructor (1997) Native iPadOS Apple Silicon Wrapper.
//  Subistema de entrada táctil DIRECTA pura (sin HUD ni trackpad virtual):
//  - Toque de 1 dedo / Apple Pencil = Clic izquierdo en coordenadas absolutas de pantalla.
//  - Toque de 2 dedos o pulsación larga = Clic derecho con feedback háptico.
//  - Arrastre con 2 dedos = Paneo del mapa (flechas de dirección / cámara).
//  - Soporte de gestos de Apple Pencil (doble toque / squeeze = clic derecho).
//  - Soporte de teclado externo (Magic Keyboard).
//

import UIKit
import os

public final class InputManager_iOS: @unchecked Sendable {

    // MARK: - Estado de Entrada y Sincronización
    private var lock = os_unfair_lock()

    // Teclas presionadas (para flechas de paneo o teclado externo)
    private var pressedKeys = Set<UInt32>()

    // Puntero Absoluto (RETRO_DEVICE_POINTER)
    // Coordenadas normalizadas [-32767, 32767] requeridas por Libretro
    private var pointerX: Int16 = 0
    private var pointerY: Int16 = 0
    private var isPointerPressed: Bool = false

    // Ratón Relativo (RETRO_DEVICE_MOUSE)
    private var deltaAccumulatorX: Float = 0.0
    private var deltaAccumulatorY: Float = 0.0
    private var latchedDeltaX: Int16 = 0
    private var latchedDeltaY: Int16 = 0

    // Botones de ratón
    private var isLeftDown: Bool = false
    private var isRightDown: Bool = false
    private var isTouchActive: Bool = false

    // Temporizadores de pulso de clic (para toques rápidos en cristal táctil)
    private var leftClickPulseFrames: Int = 0
    private var rightClickPulseFrames: Int = 0

    // Rectángulo del juego en coordenadas de pantalla (calculado según aspect ratio 4:3)
    public private(set) var gameRect: CGRect = .zero

    // Generador de respuesta háptica para confirmación de clic derecho táctil
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    // Enlace débil al núcleo Libretro para inyección directa de teclas
    public weak var core: LibretroCore?

    // Paneo con 2 dedos proporcional y fluido con inercia
    private var panAccumulatorX: CGFloat = 0.0
    private var panAccumulatorY: CGFloat = 0.0
    private var inertiaTimer: Timer?
    private var inertiaVelocity: CGPoint = .zero

    public init() {
        hapticFeedback.prepare()
    }

    private var lastBounds: CGSize = .zero
    private var lastTargetAspect: Float = 4.0 / 3.0

    /// Actualiza el viewport del juego para mapear los toques considerando barras negras (pillarbox/letterbox)
    public func updateViewport(bounds: CGSize? = nil, targetAspect: Float? = nil) {
        os_unfair_lock_lock(&lock)
        if let b = bounds, b.width > 0, b.height > 0 {
            lastBounds = b
        }
        if let t = targetAspect, t > 0 {
            lastTargetAspect = t
        }
        let viewW = Float(lastBounds.width)
        let viewH = Float(lastBounds.height)
        guard viewW > 0, viewH > 0 else {
            os_unfair_lock_unlock(&lock)
            return
        }

        let aspect = lastTargetAspect
        let viewAspect = viewW / viewH
        var renderW = viewW
        var renderH = viewH
        var offX: Float = 0
        var offY: Float = 0

        if viewAspect > aspect {
            // Pantalla más ancha que 4:3 (iPad Pro 11" o iPad Air)
            renderW = viewH * aspect
            offX = (viewW - renderW) * 0.5
        } else {
            // Pantalla 4:3 o más estrecha
            renderH = viewW / aspect
            offY = (viewH - renderH) * 0.5
        }

        self.gameRect = CGRect(x: CGFloat(offX), y: CGFloat(offY), width: CGFloat(renderW), height: CGFloat(renderH))
        print("📐 [InputManager] updateViewport: gameRect=\(self.gameRect), bounds=\(lastBounds), targetAspect=\(aspect)")
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Conversión de Coordenadas Táctiles

    /// Convierte un punto de la vista de UIKit a coordenadas Libretro [-32767, 32767]
    private func screenToRetro(point: CGPoint) -> (x: Int16, y: Int16) {
        guard gameRect.width > 0, gameRect.height > 0 else { return (0, 0) }

        let clampedX = min(max(point.x, gameRect.minX), gameRect.maxX)
        let clampedY = min(max(point.y, gameRect.minY), gameRect.maxY)

        let normX = Float((clampedX - gameRect.minX) / gameRect.width)   // 0.0 ... 1.0
        let normY = Float((clampedY - gameRect.minY) / gameRect.height)  // 0.0 ... 1.0

        let rx = Int16(clamping: Int(round((normX * 2.0 - 1.0) * 32767.0)))
        let ry = Int16(clamping: Int(round((normY * 2.0 - 1.0) * 32767.0)))
        return (rx, ry)
    }

    // MARK: - Manejo de Toques Directos (Direct Touch)

    public func handleTouchBegan(at point: CGPoint, isPrimary: Bool) {
        stopInertia()
        let (rx, ry) = screenToRetro(point: point)
        print("📱 [InputManager] handleTouchBegan point=\(point) -> retro=(\(rx), \(ry)) isPrimary=\(isPrimary)")

        os_unfair_lock_lock(&lock)
        pointerX = rx
        pointerY = ry
        isPointerPressed = true
        if isPrimary {
            isLeftDown = true
            leftClickPulseFrames = 4 // Garantiza al menos 4 fotogramas (~66ms) para registro fiable en DOS
            isTouchActive = true
        }
        os_unfair_lock_unlock(&lock)
    }

    public func handleTouchMoved(to point: CGPoint, previousPoint: CGPoint) {
        let (rx, ry) = screenToRetro(point: point)
        print("📱 [InputManager] handleTouchMoved point=\(point) -> retro=(\(rx), \(ry))")

        os_unfair_lock_lock(&lock)
        pointerX = rx
        pointerY = ry
        isPointerPressed = true
        // En toque directo absoluto, no acumulamos deltas relativos
        deltaAccumulatorX = 0.0
        deltaAccumulatorY = 0.0
        os_unfair_lock_unlock(&lock)
    }

    public func handleTouchEnded() {
        print("📱 [InputManager] handleTouchEnded")
        os_unfair_lock_lock(&lock)
        isPointerPressed = false
        isTouchActive = false
        // Si el pulso mínimo ya cumplió sus fotogramas, soltamos inmediatamente.
        // Si no, poll() lo soltará tras cumplir los fotogramas necesarios.
        if leftClickPulseFrames == 0 {
            isLeftDown = false
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Cancela inmediatamente cualquier pulsación de clic izquierdo pendiente
    public func cancelTouch() {
        stopInertia()
        os_unfair_lock_lock(&lock)
        isPointerPressed = false
        isTouchActive = false
        isLeftDown = false
        leftClickPulseFrames = 0
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Manejo de Clic Derecho Táctil (Gesto de 2 dedos o Long Press)

    public func triggerRightClick(at point: CGPoint? = nil) {
        stopInertia()
        if let pt = point {
            let (rx, ry) = screenToRetro(point: pt)
            print("📱 [InputManager] triggerRightClick at point=\(pt) -> retro=(\(rx), \(ry))")
            os_unfair_lock_lock(&lock)
            pointerX = rx
            pointerY = ry
            os_unfair_lock_unlock(&lock)
        }

        os_unfair_lock_lock(&lock)
        isRightDown = true
        rightClickPulseFrames = 4 // Mantener presionado durante 4 fotogramas para que DOS lo registre
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async { [weak self] in
            self?.hapticFeedback.impactOccurred()
        }
    }

    // MARK: - Paneo del Mapa con 2 Dedos (Desplazamiento Fluido con Inercia)

    public func beginTwoFingerPan() {
        stopInertia()
        panAccumulatorX = 0.0
        panAccumulatorY = 0.0
        print("✌️ [InputManager] beginTwoFingerPan")
    }

    public func handleTwoFingerPanDelta(delta: CGPoint, velocity: CGPoint) {
        // En Constructor, el mapa se desplaza con las flechas del teclado.
        // Arrastre táctil natural:
        // - Deslizar dedos hacia la izquierda (delta.x < 0) revela la derecha (cámara hacia la derecha: RETROK_RIGHT)
        // - Deslizar dedos hacia la derecha (delta.x > 0) revela la izquierda (cámara hacia la izquierda: RETROK_LEFT)
        // - Deslizar dedos hacia arriba (delta.y < 0) revela abajo (cámara hacia abajo: RETROK_DOWN)
        // - Deslizar dedos hacia abajo (delta.y > 0) revela arriba (cámara hacia arriba: RETROK_UP)

        let stepPoints: CGFloat = 8.0
        let maxPulsesPerEvent: Int = 3

        panAccumulatorX += delta.x
        var pulsesX = 0
        while panAccumulatorX <= -stepPoints && pulsesX < maxPulsesPerEvent {
            pulseKey(UInt32(RETROK_RIGHT.rawValue))
            panAccumulatorX += stepPoints
            pulsesX += 1
        }
        while panAccumulatorX >= stepPoints && pulsesX < maxPulsesPerEvent {
            pulseKey(UInt32(RETROK_LEFT.rawValue))
            panAccumulatorX -= stepPoints
            pulsesX += 1
        }
        if panAccumulatorX < -stepPoints * 2 { panAccumulatorX = -stepPoints * 2 }
        if panAccumulatorX > stepPoints * 2 { panAccumulatorX = stepPoints * 2 }

        panAccumulatorY += delta.y
        var pulsesY = 0
        while panAccumulatorY <= -stepPoints && pulsesY < maxPulsesPerEvent {
            pulseKey(UInt32(RETROK_DOWN.rawValue))
            panAccumulatorY += stepPoints
            pulsesY += 1
        }
        while panAccumulatorY >= stepPoints && pulsesY < maxPulsesPerEvent {
            pulseKey(UInt32(RETROK_UP.rawValue))
            panAccumulatorY -= stepPoints
            pulsesY += 1
        }
        if panAccumulatorY < -stepPoints * 2 { panAccumulatorY = -stepPoints * 2 }
        if panAccumulatorY > stepPoints * 2 { panAccumulatorY = stepPoints * 2 }
    }

    public func endTwoFingerPan(velocity: CGPoint) {
        let speed = hypot(velocity.x, velocity.y)
        print("✌️ [InputManager] endTwoFingerPan velocity=\(velocity) speed=\(speed)")
        if speed >= 250.0 {
            startInertia(velocity: velocity)
        } else {
            stopInertia()
        }
    }

    private func pulseKey(_ key: UInt32) {
        os_unfair_lock_lock(&lock)
        pressedKeys.insert(key)
        os_unfair_lock_unlock(&lock)
        core?.sendKeyEvent(down: true, keycode: key)

        os_unfair_lock_lock(&lock)
        pressedKeys.remove(key)
        os_unfair_lock_unlock(&lock)
        core?.sendKeyEvent(down: false, keycode: key)
    }

    private func startInertia(velocity: CGPoint) {
        stopInertia()
        self.inertiaVelocity = velocity

        let friction: CGFloat = 0.90
        let dt: CGFloat = 1.0 / 60.0

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.inertiaTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(dt), repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                self.inertiaVelocity.x *= friction
                self.inertiaVelocity.y *= friction

                let currentSpeed = hypot(self.inertiaVelocity.x, self.inertiaVelocity.y)
                if currentSpeed < 100.0 {
                    self.stopInertia()
                    return
                }

                let stepDelta = CGPoint(
                    x: self.inertiaVelocity.x * dt,
                    y: self.inertiaVelocity.y * dt
                )
                self.handleTwoFingerPanDelta(delta: stepDelta, velocity: self.inertiaVelocity)
            }
        }
    }

    public func stopInertia() {
        if Thread.isMainThread {
            inertiaTimer?.invalidate()
            inertiaTimer = nil
            inertiaVelocity = .zero
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.inertiaTimer?.invalidate()
                self?.inertiaTimer = nil
                self?.inertiaVelocity = .zero
            }
        }
    }

    // MARK: - Soporte de Apple Pencil Hover (Puntero flotante M2/M4)

    public func handlePencilHover(at point: CGPoint) {
        let (rx, ry) = screenToRetro(point: point)
        os_unfair_lock_lock(&lock)
        pointerX = rx
        pointerY = ry
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Soporte de Teclado Externo (Magic Keyboard)

    public func setKey(_ retroKey: UInt32, isDown: Bool) {
        os_unfair_lock_lock(&lock)
        if isDown {
            pressedKeys.insert(retroKey)
        } else {
            pressedKeys.remove(retroKey)
        }
        os_unfair_lock_unlock(&lock)

        print("🎹 [InputManager] setKey key=\(retroKey) isDown=\(isDown)")
        core?.sendKeyEvent(down: isDown, keycode: retroKey)
    }

    // MARK: - Callbacks de Libretro (retro_input_poll_t y retro_input_state_t)

    public func poll() {
        os_unfair_lock_lock(&lock)
        latchedDeltaX = Int16(clamping: Int(deltaAccumulatorX))
        latchedDeltaY = Int16(clamping: Int(deltaAccumulatorY))
        deltaAccumulatorX = 0.0
        deltaAccumulatorY = 0.0

        if leftClickPulseFrames > 0 {
            leftClickPulseFrames -= 1
            if leftClickPulseFrames == 0 && !isTouchActive {
                isLeftDown = false
            }
        }

        if rightClickPulseFrames > 0 {
            rightClickPulseFrames -= 1
            if rightClickPulseFrames == 0 {
                isRightDown = false
            }
        }
        os_unfair_lock_unlock(&lock)
    }

    public func state(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        guard port == 0 else { return 0 }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let deviceType = device & 0xFF

        switch deviceType {
        case UInt32(RETRO_DEVICE_POINTER):
            switch id {
            case UInt32(RETRO_DEVICE_ID_POINTER_X):
                return pointerX
            case UInt32(RETRO_DEVICE_ID_POINTER_Y):
                return pointerY
            case UInt32(RETRO_DEVICE_ID_POINTER_PRESSED):
                return isPointerPressed ? 1 : 0
            default:
                return 0
            }

        case UInt32(RETRO_DEVICE_MOUSE):
            switch id {
            case UInt32(RETRO_DEVICE_ID_MOUSE_X):
                return latchedDeltaX
            case UInt32(RETRO_DEVICE_ID_MOUSE_Y):
                return latchedDeltaY
            case UInt32(RETRO_DEVICE_ID_MOUSE_LEFT):
                return isLeftDown ? 1 : 0
            case UInt32(RETRO_DEVICE_ID_MOUSE_RIGHT):
                return isRightDown ? 1 : 0
            default:
                return 0
            }

        case UInt32(RETRO_DEVICE_KEYBOARD):
            return pressedKeys.contains(id) ? 1 : 0

        default:
            return 0
        }
    }

    public func attach(to core: LibretroCore) {
        self.core = core
        core.onInputPoll = { [weak self] in
            self?.poll()
        }
        core.onInputState = { [weak self] port, device, index, id in
            return self?.state(port: port, device: device, index: index, id: id) ?? 0
        }
    }
}
