//
//  InputManager.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Implements Phase 5 (Input Subsystem): Relative mouse capture with CGAssociateMouseAndMouseCursorPosition,
//  cursor concealment, quick release hotkey, and high-performance keyboard translation table.
//

import Cocoa
import Carbon
import os

public final class InputManager: @unchecked Sendable {

    // MARK: - Estado de Entrada y Sincronización
    private var lock = os_unfair_lock()

    // Teclado: conjunto de retro_key presionadas actualmente
    private var pressedKeys = Set<UInt32>()
    public weak var core: LibretroCore?

    // Ratón: acumuladores de movimiento relativo en el hilo principal (AppKit)
    private var deltaAccumulatorX: Float = 0.0
    private var deltaAccumulatorY: Float = 0.0

    // Ratón: deltas congelados para el fotograma actual de emulación (Libretro)
    private var latchedDeltaX: Int16 = 0
    private var latchedDeltaY: Int16 = 0

    // Botones de ratón
    private var isLeftDown: Bool = false
    private var isRightDown: Bool = false
    private var isMiddleDown: Bool = false
    private var isWheelUp: Bool = false
    private var isWheelDown: Bool = false

    // Estado de captura de ratón
    public private(set) var isMouseCaptured: Bool = false

    // Modificadores activos para atajos de escape rápido
    private var isCommandDown: Bool = false
    private var isOptionDown: Bool = false

    // MARK: - Tabla Estática de Traducción: macOS keyCode -> retro_key
    // Mapea los códigos virtuales de teclado de Carbon (kVK_*) a las constantes de libretro.h (RETROK_*)

    private static let keycodeTable: [UInt16: UInt32] = {
        var map = [UInt16: UInt32]()

        // Letras (ANSI A-Z)
        map[UInt16(kVK_ANSI_A)] = UInt32(RETROK_a.rawValue)
        map[UInt16(kVK_ANSI_B)] = UInt32(RETROK_b.rawValue)
        map[UInt16(kVK_ANSI_C)] = UInt32(RETROK_c.rawValue)
        map[UInt16(kVK_ANSI_D)] = UInt32(RETROK_d.rawValue)
        map[UInt16(kVK_ANSI_E)] = UInt32(RETROK_e.rawValue)
        map[UInt16(kVK_ANSI_F)] = UInt32(RETROK_f.rawValue)
        map[UInt16(kVK_ANSI_G)] = UInt32(RETROK_g.rawValue)
        map[UInt16(kVK_ANSI_H)] = UInt32(RETROK_h.rawValue)
        map[UInt16(kVK_ANSI_I)] = UInt32(RETROK_i.rawValue)
        map[UInt16(kVK_ANSI_J)] = UInt32(RETROK_j.rawValue)
        map[UInt16(kVK_ANSI_K)] = UInt32(RETROK_k.rawValue)
        map[UInt16(kVK_ANSI_L)] = UInt32(RETROK_l.rawValue)
        map[UInt16(kVK_ANSI_M)] = UInt32(RETROK_m.rawValue)
        map[UInt16(kVK_ANSI_N)] = UInt32(RETROK_n.rawValue)
        map[UInt16(kVK_ANSI_O)] = UInt32(RETROK_o.rawValue)
        map[UInt16(kVK_ANSI_P)] = UInt32(RETROK_p.rawValue)
        map[UInt16(kVK_ANSI_Q)] = UInt32(RETROK_q.rawValue)
        map[UInt16(kVK_ANSI_R)] = UInt32(RETROK_r.rawValue)
        map[UInt16(kVK_ANSI_S)] = UInt32(RETROK_s.rawValue)
        map[UInt16(kVK_ANSI_T)] = UInt32(RETROK_t.rawValue)
        map[UInt16(kVK_ANSI_U)] = UInt32(RETROK_u.rawValue)
        map[UInt16(kVK_ANSI_V)] = UInt32(RETROK_v.rawValue)
        map[UInt16(kVK_ANSI_W)] = UInt32(RETROK_w.rawValue)
        map[UInt16(kVK_ANSI_X)] = UInt32(RETROK_x.rawValue)
        map[UInt16(kVK_ANSI_Y)] = UInt32(RETROK_y.rawValue)
        map[UInt16(kVK_ANSI_Z)] = UInt32(RETROK_z.rawValue)

        // Números estándar (0-9)
        map[UInt16(kVK_ANSI_0)] = UInt32(RETROK_0.rawValue)
        map[UInt16(kVK_ANSI_1)] = UInt32(RETROK_1.rawValue)
        map[UInt16(kVK_ANSI_2)] = UInt32(RETROK_2.rawValue)
        map[UInt16(kVK_ANSI_3)] = UInt32(RETROK_3.rawValue)
        map[UInt16(kVK_ANSI_4)] = UInt32(RETROK_4.rawValue)
        map[UInt16(kVK_ANSI_5)] = UInt32(RETROK_5.rawValue)
        map[UInt16(kVK_ANSI_6)] = UInt32(RETROK_6.rawValue)
        map[UInt16(kVK_ANSI_7)] = UInt32(RETROK_7.rawValue)
        map[UInt16(kVK_ANSI_8)] = UInt32(RETROK_8.rawValue)
        map[UInt16(kVK_ANSI_9)] = UInt32(RETROK_9.rawValue)

        // Teclas de Función (F1-F12) - Críticas en Constructor
        map[UInt16(kVK_F1)]  = UInt32(RETROK_F1.rawValue)
        map[UInt16(kVK_F2)]  = UInt32(RETROK_F2.rawValue)
        map[UInt16(kVK_F3)]  = UInt32(RETROK_F3.rawValue)
        map[UInt16(kVK_F4)]  = UInt32(RETROK_F4.rawValue)
        map[UInt16(kVK_F5)]  = UInt32(RETROK_F5.rawValue)
        map[UInt16(kVK_F6)]  = UInt32(RETROK_F6.rawValue)
        map[UInt16(kVK_F7)]  = UInt32(RETROK_F7.rawValue)
        map[UInt16(kVK_F8)]  = UInt32(RETROK_F8.rawValue)
        map[UInt16(kVK_F9)]  = UInt32(RETROK_F9.rawValue)
        map[UInt16(kVK_F10)] = UInt32(RETROK_F10.rawValue)
        map[UInt16(kVK_F11)] = UInt32(RETROK_F11.rawValue)
        map[UInt16(kVK_F12)] = UInt32(RETROK_F12.rawValue)

        // Teclas de Control y Edición
        map[UInt16(kVK_Escape)]   = UInt32(RETROK_ESCAPE.rawValue)
        map[UInt16(kVK_Return)]   = UInt32(RETROK_RETURN.rawValue)
        map[UInt16(kVK_Tab)]      = UInt32(RETROK_TAB.rawValue)
        map[UInt16(kVK_Space)]    = UInt32(RETROK_SPACE.rawValue)
        map[UInt16(kVK_Delete)]   = UInt32(RETROK_BACKSPACE.rawValue)
        map[UInt16(kVK_ForwardDelete)] = UInt32(RETROK_DELETE.rawValue)

        // Cursores (Flechas de dirección)
        map[UInt16(kVK_UpArrow)]    = UInt32(RETROK_UP.rawValue)
        map[UInt16(kVK_DownArrow)]  = UInt32(RETROK_DOWN.rawValue)
        map[UInt16(kVK_LeftArrow)]  = UInt32(RETROK_LEFT.rawValue)
        map[UInt16(kVK_RightArrow)] = UInt32(RETROK_RIGHT.rawValue)

        // Navegación
        map[UInt16(kVK_Home)]     = UInt32(RETROK_HOME.rawValue)
        map[UInt16(kVK_End)]      = UInt32(RETROK_END.rawValue)
        map[UInt16(kVK_PageUp)]   = UInt32(RETROK_PAGEUP.rawValue)
        map[UInt16(kVK_PageDown)] = UInt32(RETROK_PAGEDOWN.rawValue)

        // Modificadores
        map[UInt16(kVK_Shift)]        = UInt32(RETROK_LSHIFT.rawValue)
        map[UInt16(kVK_RightShift)]   = UInt32(RETROK_RSHIFT.rawValue)
        map[UInt16(kVK_Control)]      = UInt32(RETROK_LCTRL.rawValue)
        map[UInt16(kVK_RightControl)] = UInt32(RETROK_RCTRL.rawValue)
        map[UInt16(kVK_Option)]       = UInt32(RETROK_LALT.rawValue)
        map[UInt16(kVK_RightOption)]  = UInt32(RETROK_RALT.rawValue)
        map[UInt16(kVK_CapsLock)]     = UInt32(RETROK_CAPSLOCK.rawValue)

        // Puntuación y Símbolos
        map[UInt16(kVK_ANSI_Minus)]        = UInt32(RETROK_MINUS.rawValue)
        map[UInt16(kVK_ANSI_Equal)]        = UInt32(RETROK_EQUALS.rawValue)
        map[UInt16(kVK_ANSI_LeftBracket)]  = UInt32(RETROK_LEFTBRACKET.rawValue)
        map[UInt16(kVK_ANSI_RightBracket)] = UInt32(RETROK_RIGHTBRACKET.rawValue)
        map[UInt16(kVK_ANSI_Semicolon)]    = UInt32(RETROK_SEMICOLON.rawValue)
        map[UInt16(kVK_ANSI_Quote)]        = UInt32(RETROK_QUOTE.rawValue)
        map[UInt16(kVK_ANSI_Backslash)]    = UInt32(RETROK_BACKSLASH.rawValue)
        map[UInt16(kVK_ANSI_Comma)]        = UInt32(RETROK_COMMA.rawValue)
        map[UInt16(kVK_ANSI_Period)]       = UInt32(RETROK_PERIOD.rawValue)
        map[UInt16(kVK_ANSI_Slash)]        = UInt32(RETROK_SLASH.rawValue)
        map[UInt16(kVK_ANSI_Grave)]        = UInt32(RETROK_BACKQUOTE.rawValue)

        // Teclado Numérico (Keypad)
        map[UInt16(kVK_ANSI_Keypad0)]        = UInt32(RETROK_KP0.rawValue)
        map[UInt16(kVK_ANSI_Keypad1)]        = UInt32(RETROK_KP1.rawValue)
        map[UInt16(kVK_ANSI_Keypad2)]        = UInt32(RETROK_KP2.rawValue)
        map[UInt16(kVK_ANSI_Keypad3)]        = UInt32(RETROK_KP3.rawValue)
        map[UInt16(kVK_ANSI_Keypad4)]        = UInt32(RETROK_KP4.rawValue)
        map[UInt16(kVK_ANSI_Keypad5)]        = UInt32(RETROK_KP5.rawValue)
        map[UInt16(kVK_ANSI_Keypad6)]        = UInt32(RETROK_KP6.rawValue)
        map[UInt16(kVK_ANSI_Keypad7)]        = UInt32(RETROK_KP7.rawValue)
        map[UInt16(kVK_ANSI_Keypad8)]        = UInt32(RETROK_KP8.rawValue)
        map[UInt16(kVK_ANSI_Keypad9)]        = UInt32(RETROK_KP9.rawValue)
        map[UInt16(kVK_ANSI_KeypadEnter)]    = UInt32(RETROK_KP_ENTER.rawValue)
        map[UInt16(kVK_ANSI_KeypadPlus)]     = UInt32(RETROK_KP_PLUS.rawValue)
        map[UInt16(kVK_ANSI_KeypadMinus)]    = UInt32(RETROK_KP_MINUS.rawValue)
        map[UInt16(kVK_ANSI_KeypadMultiply)] = UInt32(RETROK_KP_MULTIPLY.rawValue)
        map[UInt16(kVK_ANSI_KeypadDivide)]   = UInt32(RETROK_KP_DIVIDE.rawValue)
        map[UInt16(kVK_ANSI_KeypadDecimal)]  = UInt32(RETROK_KP_PERIOD.rawValue)
        map[UInt16(kVK_ANSI_KeypadEquals)]   = UInt32(RETROK_KP_EQUALS.rawValue)

        return map
    }()

    public init() {}

    // MARK: - Traducción de Teclado

    public func retroKey(for keyCode: UInt16) -> UInt32? {
        return Self.keycodeTable[keyCode]
    }

    // MARK: - Captura y Liberación del Ratón (Mouse Trap)

    /// Activa la captura de ratón en modo relativo y oculta el cursor nativo de macOS.
    public func captureMouse() {
        guard !isMouseCaptured else { return }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
        NSCursor.hide()
        isMouseCaptured = true
    }

    /// Libera el ratón hacia macOS y restaura la visibilidad del cursor nativo.
    public func releaseMouse() {
        guard isMouseCaptured else { return }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        NSCursor.unhide()
        isMouseCaptured = false

        os_unfair_lock_lock(&lock)
        deltaAccumulatorX = 0
        deltaAccumulatorY = 0
        latchedDeltaX = 0
        latchedDeltaY = 0
        isLeftDown = false
        isRightDown = false
        isMiddleDown = false
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Manejo de Eventos de AppKit

    public func handleKeyDown(with event: NSEvent) {
        checkQuickRelease(modifiers: event.modifierFlags)

        if let retroKey = Self.keycodeTable[event.keyCode] {
            os_unfair_lock_lock(&lock)
            pressedKeys.insert(retroKey)
            os_unfair_lock_unlock(&lock)
            core?.sendKeyEvent(down: true, keycode: retroKey)
        }
    }

    public func handleKeyUp(with event: NSEvent) {
        if let retroKey = Self.keycodeTable[event.keyCode] {
            os_unfair_lock_lock(&lock)
            pressedKeys.remove(retroKey)
            os_unfair_lock_unlock(&lock)
            core?.sendKeyEvent(down: false, keycode: retroKey)
        }
    }

    public func handleFlagsChanged(with event: NSEvent) {
        checkQuickRelease(modifiers: event.modifierFlags)

        let flags = event.modifierFlags
        os_unfair_lock_lock(&lock)
        updateModifierKey(flags.contains(.shift), retroKey: UInt32(RETROK_LSHIFT.rawValue))
        updateModifierKey(flags.contains(.control), retroKey: UInt32(RETROK_LCTRL.rawValue))
        updateModifierKey(flags.contains(.option), retroKey: UInt32(RETROK_LALT.rawValue))
        updateModifierKey(flags.contains(.capsLock), retroKey: UInt32(RETROK_CAPSLOCK.rawValue))
        os_unfair_lock_unlock(&lock)
    }

    private func updateModifierKey(_ isDown: Bool, retroKey: UInt32) {
        if isDown {
            pressedKeys.insert(retroKey)
        } else {
            pressedKeys.remove(retroKey)
        }
    }

    /// Atajo de liberación rápida: Cmd + Option (o pérdida de foco) libera el ratón inmediatamente
    private func checkQuickRelease(modifiers: NSEvent.ModifierFlags) {
        let cmd = modifiers.contains(.command)
        let opt = modifiers.contains(.option)

        if cmd && opt && isMouseCaptured {
            releaseMouse()
        }
    }

    public func handleMouseDown(with event: NSEvent) {
        if !isMouseCaptured {
            captureMouse()
        }
        os_unfair_lock_lock(&lock)
        isLeftDown = true
        os_unfair_lock_unlock(&lock)
    }

    public func handleMouseUp(with event: NSEvent) {
        os_unfair_lock_lock(&lock)
        isLeftDown = false
        os_unfair_lock_unlock(&lock)
    }

    public func handleRightMouseDown(with event: NSEvent) {
        os_unfair_lock_lock(&lock)
        isRightDown = true
        os_unfair_lock_unlock(&lock)
    }

    public func handleRightMouseUp(with event: NSEvent) {
        os_unfair_lock_lock(&lock)
        isRightDown = false
        os_unfair_lock_unlock(&lock)
    }

    public func handleOtherMouseDown(with event: NSEvent) {
        os_unfair_lock_lock(&lock)
        isMiddleDown = true
        os_unfair_lock_unlock(&lock)
    }

    public func handleOtherMouseUp(with event: NSEvent) {
        os_unfair_lock_lock(&lock)
        isMiddleDown = false
        os_unfair_lock_unlock(&lock)
    }

    public func handleMouseMoved(with event: NSEvent) {
        guard isMouseCaptured else { return }
        os_unfair_lock_lock(&lock)
        deltaAccumulatorX += Float(event.deltaX)
        deltaAccumulatorY += Float(event.deltaY)
        os_unfair_lock_unlock(&lock)
    }

    public func handleScrollWheel(with event: NSEvent) {
        guard isMouseCaptured else { return }
        os_unfair_lock_lock(&lock)
        if event.deltaY > 0 {
            isWheelUp = true
        } else if event.deltaY < 0 {
            isWheelDown = true
        }
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Callbacks de Libretro (retro_input_poll_t y retro_input_state_t)

    /// Se invoca en cada fotograma antes de consultar los dispositivos de entrada.
    /// Congela los deltas acumulados de ratón y limpia el acumulador para el siguiente tick.
    public func poll() {
        os_unfair_lock_lock(&lock)
        latchedDeltaX = Int16(clamping: Int(deltaAccumulatorX))
        latchedDeltaY = Int16(clamping: Int(deltaAccumulatorY))
        deltaAccumulatorX = 0.0
        deltaAccumulatorY = 0.0
        os_unfair_lock_unlock(&lock)
    }

    /// Responde a la consulta de estado de hardware de DOSBox-Pure.
    public func state(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
        guard port == 0 else { return 0 }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        // Constante RETRO_DEVICE_MASK = ((1 << 8) - 1) = 0xFF
        let deviceType = device & 0xFF

        switch deviceType {
        case UInt32(RETRO_DEVICE_KEYBOARD):
            return pressedKeys.contains(id) ? 1 : 0

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
            case UInt32(RETRO_DEVICE_ID_MOUSE_MIDDLE):
                return isMiddleDown ? 1 : 0
            case UInt32(RETRO_DEVICE_ID_MOUSE_WHEELUP):
                let up = isWheelUp
                isWheelUp = false
                return up ? 1 : 0
            case UInt32(RETRO_DEVICE_ID_MOUSE_WHEELDOWN):
                let down = isWheelDown
                isWheelDown = false
                return down ? 1 : 0
            default:
                return 0
            }

        default:
            return 0
        }
    }

    // MARK: - Enlace con LibretroCore

    /// Conecta los callbacks de LibretroCore con este InputManager.
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
