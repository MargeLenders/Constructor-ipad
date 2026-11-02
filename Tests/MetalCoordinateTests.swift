//
//  MetalCoordinateTests.swift
//  ConstructorHostTests
//
//  Unit tests for aspect ratio preservation (4:3) and pillarbox/letterbox
//  coordinate conversion from window space to DOS coordinates.
//

import XCTest
import Metal
@testable import ConstructorHost

final class MetalCoordinateTests: XCTestCase {

    func testPillarboxCoordinateMapping() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device no disponible en este entorno.")
        }

        let renderer = try MetalRenderer(device: device)

        // Simulamos que el juego está en SVGA (640x480)
        // Para establecer dimensiones internas, inyectamos un fotograma dummy
        let dummyPixels = [UInt32](repeating: 0xFF0000FF, count: 640 * 480)
        dummyPixels.withUnsafeBufferPointer { ptr in
            renderer.updateFrame(data: ptr.baseAddress!, width: 640, height: 480, pitch: 640 * 4)
        }

        XCTAssertEqual(renderer.currentWidth, 640)
        XCTAssertEqual(renderer.currentHeight, 480)

        // Viewport panorámico 16:9 (1920x1080)
        // El rectángulo 4:3 útil mide 1440x1080 con márgenes laterales (pillarbox) de 240 px a cada lado.
        let viewSize = CGSize(width: 1920, height: 1080)

        // 1. Clic en la barra negra izquierda (X = 100) -> Debe retornar nil
        let leftBarPoint = CGPoint(x: 100, y: 540)
        XCTAssertNil(renderer.convertWindowPointToGamePoint(leftBarPoint, viewSize: viewSize))

        // 2. Clic en la barra negra derecha (X = 1800) -> Debe retornar nil
        let rightBarPoint = CGPoint(x: 1800, y: 540)
        XCTAssertNil(renderer.convertWindowPointToGamePoint(rightBarPoint, viewSize: viewSize))

        // 3. Clic en la esquina superior izquierda del área útil (X = 240, Y = 0) -> Debe mapear a (0, 0)
        let topLeft = CGPoint(x: 240, y: 0)
        let gameTopLeft = renderer.convertWindowPointToGamePoint(topLeft, viewSize: viewSize)
        XCTAssertNotNil(gameTopLeft)
        XCTAssertEqual(gameTopLeft!.x, 0, accuracy: 0.5)
        XCTAssertEqual(gameTopLeft!.y, 0, accuracy: 0.5)

        // 4. Clic en el centro exacto (X = 240 + 720 = 960, Y = 540) -> Debe mapear a (320, 240)
        let centerPoint = CGPoint(x: 960, y: 540)
        let gameCenter = renderer.convertWindowPointToGamePoint(centerPoint, viewSize: viewSize)
        XCTAssertNotNil(gameCenter)
        XCTAssertEqual(gameCenter!.x, 320, accuracy: 0.5)
        XCTAssertEqual(gameCenter!.y, 240, accuracy: 0.5)

        // 5. Clic en la esquina inferior derecha del área útil (X = 1680, Y = 1080) -> Debe mapear a (640, 480)
        let bottomRight = CGPoint(x: 1680, y: 1080)
        let gameBottomRight = renderer.convertWindowPointToGamePoint(bottomRight, viewSize: viewSize)
        XCTAssertNotNil(gameBottomRight)
        XCTAssertEqual(gameBottomRight!.x, 640, accuracy: 0.5)
        XCTAssertEqual(gameBottomRight!.y, 480, accuracy: 0.5)
    }
}
