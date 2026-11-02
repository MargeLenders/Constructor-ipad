//
//  TestRunner.swift
//  ConstructorHostTests
//
//  Ejecutable de pruebas automatizadas para validar el comportamiento del motor
//  (RingBuffer, Metal Coordinate Mapping, Input Subsystem y C-ABI) desde CLI o CI/CD.
//

import Foundation
import Metal
import Carbon

// MARK: - Framework Ligero de Aserciones

struct TestContext {
    var passedCount: Int = 0
    var failedCount: Int = 0

    mutating func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if condition {
            passedCount += 1
            print("  ✅ [PASS] \(message)")
        } else {
            failedCount += 1
            print("  ❌ [FAIL] \(message) (\(URL(fileURLWithPath: file).lastPathComponent):\(line))")
        }
    }

    mutating func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
        if a == b {
            passedCount += 1
            print("  ✅ [PASS] \(message)")
        } else {
            failedCount += 1
            print("  ❌ [FAIL] \(message) -> Expected: \(b), Got: \(a) (\(URL(fileURLWithPath: file).lastPathComponent):\(line))")
        }
    }

    mutating func checkEqualFloat(_ a: Float32, _ b: Float32, accuracy: Float32 = 0.0001, _ message: String, file: String = #file, line: Int = #line) {
        if abs(a - b) <= accuracy {
            passedCount += 1
            print("  ✅ [PASS] \(message)")
        } else {
            failedCount += 1
            print("  ❌ [FAIL] \(message) -> Expected: \(b), Got: \(a) (Diff: \(abs(a - b))) (\(URL(fileURLWithPath: file).lastPathComponent):\(line))")
        }
    }
}

// MARK: - Ejecución de Suites de Prueba

@main
struct TestRunner {

    static func main() {
        print("==================================================")
        print("🚀 INICIANDO SUITE DE TESTS AUTOMATIZADOS: CONSTRUCTOR HOST")
        print("==================================================\n")

        var ctx = TestContext()

        testAudioRingBuffer(ctx: &ctx)
        testInputManager(ctx: &ctx)
        testMetalCoordinateMapping(ctx: &ctx)

        print("\n==================================================")
        print("📊 RESULTADOS FINALES:")
        print("   Total Pasados: \(ctx.passedCount)")
        print("   Total Fallidos: \(ctx.failedCount)")
        print("==================================================")

        if ctx.failedCount > 0 {
            exit(1)
        } else {
            print("🎉 ¡TODOS LOS TESTS HAN PASADO SATISFACTORIAMENTE!\n")
            exit(0)
        }
    }

    // MARK: - Test Suite 1: AudioRingBuffer
    static func testAudioRingBuffer(ctx: inout TestContext) {
        print("▶ Ejecutando Suite: AudioRingBuffer (Lock-Free SPSC & Audio Safety)...")

        let ring = AudioRingBuffer(capacityFrames: 1024)

        // 1. Escritura y lectura básica con conversión Int16 a Float32
        let samples: [Int16] = [1000, -1000, 32767, -32768]
        samples.withUnsafeBufferPointer { ptr in
            ring.write(interleavedData: ptr.baseAddress!, frames: 2)
        }

        ctx.checkEqual(ring.availableFrames, 2, "El RingBuffer reporta 2 frames disponibles tras escritura")

        var leftOut = [Float32](repeating: 0, count: 2)
        var rightOut = [Float32](repeating: 0, count: 2)
        leftOut.withUnsafeMutableBufferPointer { lPtr in
            rightOut.withUnsafeMutableBufferPointer { rPtr in
                ring.read(intoLeft: lPtr.baseAddress!, right: rPtr.baseAddress!, frames: 2)
            }
        }

        ctx.checkEqualFloat(leftOut[0], Float32(1000) / 32768.0, "Canal Left frame 0 escalado correctamente a Float32")
        ctx.checkEqualFloat(rightOut[0], Float32(-1000) / 32768.0, "Canal Right frame 0 escalado correctamente a Float32")
        ctx.checkEqualFloat(leftOut[1], Float32(32767) / 32768.0, "Canal Left frame 1 (Int16.max) escalado a ~1.0")
        ctx.checkEqualFloat(rightOut[1], -1.0, "Canal Right frame 1 (Int16.min) escalado exactamente a -1.0")
        ctx.checkEqual(ring.availableFrames, 0, "El RingBuffer queda vacío tras consumo completo")

        // 2. Underrun Protection (Relleno con silencio 0.0f)
        let singleSample: [Int16] = [16384, -16384]
        singleSample.withUnsafeBufferPointer { ptr in
            ring.write(interleavedData: ptr.baseAddress!, frames: 1)
        }

        var underrunL = [Float32](repeating: 99.0, count: 4)
        var underrunR = [Float32](repeating: 99.0, count: 4)
        underrunL.withUnsafeMutableBufferPointer { lPtr in
            underrunR.withUnsafeMutableBufferPointer { rPtr in
                ring.read(intoLeft: lPtr.baseAddress!, right: rPtr.baseAddress!, frames: 4)
            }
        }

        ctx.checkEqualFloat(underrunL[0], 0.5, "Frame disponible se lee correctamente durante underrun")
        ctx.checkEqualFloat(underrunR[0], -0.5, "Frame disponible se lee correctamente durante underrun")
        ctx.checkEqualFloat(underrunL[1], 0.0, "Underrun Frame 1 Left acolchado con silencio (0.0f)")
        ctx.checkEqualFloat(underrunR[1], 0.0, "Underrun Frame 1 Right acolchado con silencio (0.0f)")
        ctx.checkEqualFloat(underrunL[2], 0.0, "Underrun Frame 2 Left acolchado con silencio (0.0f)")
        ctx.checkEqualFloat(underrunR[3], 0.0, "Underrun Frame 3 Right acolchado con silencio (0.0f)")

        // 3. Overrun Protection (Desbordamiento controlado sin crash)
        let smallRing = AudioRingBuffer(capacityFrames: 64)
        let overflowData = [Int16](repeating: 1234, count: 128 * 2)
        overflowData.withUnsafeBufferPointer { ptr in
            smallRing.write(interleavedData: ptr.baseAddress!, frames: 128)
        }
        ctx.check(smallRing.availableFrames <= 64, "Overrun: el búfer no desborda su capacidad elástica máxima")

        // 4. Test Concurrente Multihilo (Productor vs Consumidor SPSC)
        let concurrentRing = AudioRingBuffer(capacityFrames: 4096)
        let totalFramesToStream = 20_000
        let group = DispatchGroup()

        // Hilo Productor (Simula retro_run generando 735 frames a 60 fps)
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            var sent = 0
            let chunk = [Int16](repeating: 777, count: 256 * 2)
            while sent < totalFramesToStream {
                chunk.withUnsafeBufferPointer { ptr in
                    concurrentRing.write(interleavedData: ptr.baseAddress!, frames: 256)
                }
                sent += 256
                usleep(1000) // 1 ms
            }
            group.leave()
        }

        // Hilo Consumidor (Simula CoreAudio solicitando bloques de 128 frames)
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            var received = 0
            var outL = [Float32](repeating: 0, count: 128)
            var outR = [Float32](repeating: 0, count: 128)
            while received < totalFramesToStream {
                outL.withUnsafeMutableBufferPointer { lPtr in
                    outR.withUnsafeMutableBufferPointer { rPtr in
                        concurrentRing.read(intoLeft: lPtr.baseAddress!, right: rPtr.baseAddress!, frames: 128)
                    }
                }
                received += 128
                usleep(500) // 0.5 ms
            }
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + 5.0)
        ctx.checkEqual(waitResult, .success, "Test de concurrencia multihilo SPSC finalizó sin bloqueos ni deadlocks")
    }

    // MARK: - Test Suite 2: InputManager
    static func testInputManager(ctx: inout TestContext) {
        print("\n▶ Ejecutando Suite: InputManager (Keyboard Table & Mouse Trap)...")

        let input = InputManager()

        // 1. Teclas Críticas
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_Escape)), UInt32(RETROK_ESCAPE.rawValue), "Escape traduce a RETROK_ESCAPE (27)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_Return)), UInt32(RETROK_RETURN.rawValue), "Return traduce a RETROK_RETURN (13)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_Space)), UInt32(RETROK_SPACE.rawValue), "Space traduce a RETROK_SPACE (32)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_Tab)), UInt32(RETROK_TAB.rawValue), "Tab traduce a RETROK_TAB (9)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_Delete)), UInt32(RETROK_BACKSPACE.rawValue), "Delete traduce a RETROK_BACKSPACE (8)")

        // 2. Teclas de Función F1 - F12
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_F1)), UInt32(RETROK_F1.rawValue), "F1 traduce a RETROK_F1 (282)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_F5)), UInt32(RETROK_F5.rawValue), "F5 traduce a RETROK_F5 (286)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_F12)), UInt32(RETROK_F12.rawValue), "F12 traduce a RETROK_F12 (293)")

        // 3. Flechas de Dirección
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_UpArrow)), UInt32(RETROK_UP.rawValue), "UpArrow traduce a RETROK_UP (273)")
        ctx.checkEqual(input.retroKey(for: UInt16(kVK_DownArrow)), UInt32(RETROK_DOWN.rawValue), "DownArrow traduce a RETROK_DOWN (274)")

        // 4. Captura y Liberación de Ratón
        ctx.check(!input.isMouseCaptured, "El ratón no está capturado inicialmente")
        input.captureMouse()
        ctx.check(input.isMouseCaptured, "captureMouse() marca isMouseCaptured = true")
        input.releaseMouse()
        ctx.check(!input.isMouseCaptured, "releaseMouse() restaura isMouseCaptured = false")

        // 5. Consulta inicial de botones de ratón
        ctx.checkEqual(input.state(port: 0, device: 2, index: 0, id: 2), 0, "Botón Izquierdo liberado por defecto (0)")
        ctx.checkEqual(input.state(port: 0, device: 2, index: 0, id: 3), 0, "Botón Derecho liberado por defecto (0)")
    }

    // MARK: - Test Suite 3: MetalRenderer (Coordinate Mapping & Aspect Ratio)
    static func testMetalCoordinateMapping(ctx: inout TestContext) {
        print("\n▶ Ejecutando Suite: MetalRenderer (Pillarboxing 4:3 & Coordinate Mapping)...")

        guard let device = MTLCreateSystemDefaultDevice() else {
            ctx.check(false, "No se pudo obtener el dispositivo Metal del sistema")
            return
        }

        guard let renderer = try? MetalRenderer(device: device) else {
            ctx.check(false, "Fallo al inicializar MetalRenderer")
            return
        }

        // Establecemos resolución SVGA 640x480 mediante un fotograma dummy
        let dummy = [UInt32](repeating: 0xFFFFFFFF, count: 640 * 480)
        dummy.withUnsafeBufferPointer { ptr in
            renderer.updateFrame(data: ptr.baseAddress!, width: 640, height: 480, pitch: 640 * 4)
        }

        ctx.checkEqual(renderer.currentWidth, 640, "MetalRenderer actualiza currentWidth = 640")
        ctx.checkEqual(renderer.currentHeight, 480, "MetalRenderer actualiza currentHeight = 480")

        // Viewport panorámico 16:9 (1920x1080)
        // Rectángulo 4:3 = 1440x1080 con offset horizontal X de 240 px a cada lado.
        let viewSize = CGSize(width: 1920, height: 1080)

        // Clic en la barra negra izquierda (X = 100) -> nil
        let leftBar = renderer.convertWindowPointToGamePoint(CGPoint(x: 100, y: 500), viewSize: viewSize)
        ctx.check(leftBar == nil, "Clic en barra negra izquierda de Pillarbox retorna nil")

        // Clic en la barra negra derecha (X = 1800) -> nil
        let rightBar = renderer.convertWindowPointToGamePoint(CGPoint(x: 1800, y: 500), viewSize: viewSize)
        ctx.check(rightBar == nil, "Clic en barra negra derecha de Pillarbox retorna nil")

        // Clic en la esquina superior izquierda útil (X = 240, Y = 0) -> (0, 0)
        if let p0 = renderer.convertWindowPointToGamePoint(CGPoint(x: 240, y: 0), viewSize: viewSize) {
            ctx.checkEqualFloat(Float32(p0.x), 0.0, accuracy: 0.5, "Esquina superior izquierda mapea a DOS X = 0")
            ctx.checkEqualFloat(Float32(p0.y), 0.0, accuracy: 0.5, "Esquina superior izquierda mapea a DOS Y = 0")
        } else {
            ctx.check(false, "Esquina superior izquierda útil no debería retornar nil")
        }

        // Clic en el centro exacto (X = 960, Y = 540) -> (320, 240)
        if let pCenter = renderer.convertWindowPointToGamePoint(CGPoint(x: 960, y: 540), viewSize: viewSize) {
            ctx.checkEqualFloat(Float32(pCenter.x), 320.0, accuracy: 0.5, "Centro de pantalla mapea a DOS X = 320")
            ctx.checkEqualFloat(Float32(pCenter.y), 240.0, accuracy: 0.5, "Centro de pantalla mapea a DOS Y = 240")
        } else {
            ctx.check(false, "Centro de pantalla útil no debería retornar nil")
        }

        // Clic en la esquina inferior derecha útil (X = 1680, Y = 1080) -> (640, 480)
        if let pMax = renderer.convertWindowPointToGamePoint(CGPoint(x: 1680, y: 1080), viewSize: viewSize) {
            ctx.checkEqualFloat(Float32(pMax.x), 640.0, accuracy: 0.5, "Esquina inferior derecha mapea a DOS X = 640")
            ctx.checkEqualFloat(Float32(pMax.y), 480.0, accuracy: 0.5, "Esquina inferior derecha mapea a DOS Y = 480")
        } else {
            ctx.check(false, "Esquina inferior derecha útil no debería retornar nil")
        }
    }
}
