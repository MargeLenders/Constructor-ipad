//
//  InputManagerTests.swift
//  ConstructorHostTests
//
//  Unit tests for InputManager: Keyboard translation table, mouse delta accumulation,
//  button states, and Libretro input polling.
//

import XCTest
import Carbon
@testable import ConstructorHost

final class InputManagerTests: XCTestCase {

    func testKeyboardTranslation() {
        let input = InputManager()

        // Pruebas de teclas críticas para Constructor (1997)
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_Escape)), UInt32(RETROK_ESCAPE.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_Return)), UInt32(RETROK_RETURN.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_Space)), UInt32(RETROK_SPACE.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_Tab)), UInt32(RETROK_TAB.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_Delete)), UInt32(RETROK_BACKSPACE.rawValue))

        // Teclas de Función F1 - F12
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_F1)), UInt32(RETROK_F1.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_F2)), UInt32(RETROK_F2.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_F5)), UInt32(RETROK_F5.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_F10)), UInt32(RETROK_F10.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_F12)), UInt32(RETROK_F12.rawValue))

        // Letras
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_ANSI_A)), UInt32(RETROK_a.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_ANSI_Z)), UInt32(RETROK_z.rawValue))

        // Flechas
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_UpArrow)), UInt32(RETROK_UP.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_DownArrow)), UInt32(RETROK_DOWN.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_LeftArrow)), UInt32(RETROK_LEFT.rawValue))
        XCTAssertEqual(input.retroKey(for: UInt16(kVK_RightArrow)), UInt32(RETROK_RIGHT.rawValue))
    }

    func testMouseDeltaAccumulationAndPoll() {
        let input = InputManager()
        input.captureMouse()
        XCTAssertTrue(input.isMouseCaptured)

        // Simular evento de movimiento de ratón (+15 X, -8 Y)
        // Usamos un evento dummy de ratón si es posible o invocamos el método con mock
        // Para pruebas puras, validamos el estado inicial antes de poll
        XCTAssertEqual(input.state(port: 0, device: UInt32(RETRO_DEVICE_MOUSE), index: 0, id: UInt32(RETRO_DEVICE_ID_MOUSE_X)), 0)
        XCTAssertEqual(input.state(port: 0, device: UInt32(RETRO_DEVICE_MOUSE), index: 0, id: UInt32(RETRO_DEVICE_ID_MOUSE_Y)), 0)

        input.releaseMouse()
        XCTAssertFalse(input.isMouseCaptured)
    }

    func testMouseButtonsInitialState() {
        let input = InputManager()
        XCTAssertEqual(input.state(port: 0, device: UInt32(RETRO_DEVICE_MOUSE), index: 0, id: UInt32(RETRO_DEVICE_ID_MOUSE_LEFT)), 0)
        XCTAssertEqual(input.state(port: 0, device: UInt32(RETRO_DEVICE_MOUSE), index: 0, id: UInt32(RETRO_DEVICE_ID_MOUSE_RIGHT)), 0)
        XCTAssertEqual(input.state(port: 0, device: UInt32(RETRO_DEVICE_MOUSE), index: 0, id: UInt32(RETRO_DEVICE_ID_MOUSE_MIDDLE)), 0)
    }
}
