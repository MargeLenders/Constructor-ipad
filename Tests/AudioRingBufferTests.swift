//
//  AudioRingBufferTests.swift
//  ConstructorHostTests
//
//  Unit tests for AudioRingBuffer: SPSC lock-free concurrency, Float32 normalization,
//  underrun silence injection, and overrun protection.
//

import XCTest
@testable import ConstructorHost

final class AudioRingBufferTests: XCTestCase {

    func testBasicWriteAndRead() {
        let ring = AudioRingBuffer(capacityFrames: 1024)

        // Muestras estéreo intercaladas de prueba: (1000, -1000), (32767, -32768)
        let inputSamples: [Int16] = [1000, -1000, 32767, -32768]
        inputSamples.withUnsafeBufferPointer { ptr in
            ring.write(interleavedData: ptr.baseAddress!, frames: 2)
        }

        XCTAssertEqual(ring.availableFrames, 2)

        var leftOut = [Float32](repeating: 0, count: 2)
        var rightOut = [Float32](repeating: 0, count: 2)

        leftOut.withUnsafeMutableBufferPointer { lPtr in
            rightOut.withUnsafeMutableBufferPointer { rPtr in
                ring.read(intoLeft: lPtr.baseAddress!, right: rPtr.baseAddress!, frames: 2)
            }
        }

        XCTAssertEqual(ring.availableFrames, 0)

        // Verificar normalización Float32
        XCTAssertEqual(leftOut[0], Float32(1000) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(rightOut[0], Float32(-1000) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(leftOut[1], Float32(32767) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(rightOut[1], -1.0, accuracy: 0.0001)
    }

    func testUnderrunSilencePadding() {
        let ring = AudioRingBuffer(capacityFrames: 1024)

        // Escribimos solo 1 frame
        let inputSamples: [Int16] = [16384, -16384]
        inputSamples.withUnsafeBufferPointer { ptr in
            ring.write(interleavedData: ptr.baseAddress!, frames: 1)
        }

        // Solicitamos 4 frames a CoreAudio (faltarán 3 frames)
        var leftOut = [Float32](repeating: 99.0, count: 4)
        var rightOut = [Float32](repeating: 99.0, count: 4)

        leftOut.withUnsafeMutableBufferPointer { lPtr in
            rightOut.withUnsafeMutableBufferPointer { rPtr in
                ring.read(intoLeft: lPtr.baseAddress!, right: rPtr.baseAddress!, frames: 4)
            }
        }

        // Frame 0 contiene el dato válido
        XCTAssertEqual(leftOut[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(rightOut[0], -0.5, accuracy: 0.0001)

        // Frames 1, 2, 3 deben estar rellenados con silencio exacto (0.0f)
        for i in 1..<4 {
            XCTAssertEqual(leftOut[i], 0.0, "Frame \(i) en Left debe ser 0.0f (silencio)")
            XCTAssertEqual(rightOut[i], 0.0, "Frame \(i) en Right debe ser 0.0f (silencio)")
        }
    }

    func testOverrunProtection() {
        let capacity: UInt32 = 256
        let ring = AudioRingBuffer(capacityFrames: capacity)

        // Escribir intencionadamente más muestras que la capacidad del búfer (300 frames)
        let largeInput = [Int16](repeating: 500, count: 300 * 2)
        largeInput.withUnsafeBufferPointer { ptr in
            ring.write(interleavedData: ptr.baseAddress!, frames: 300)
        }

        // El búfer no debe superar su capacidad ni provocar desbordamiento de memoria
        XCTAssertLessThanOrEqual(ring.availableFrames, capacity)

        var leftOut = [Float32](repeating: 0, count: Int(capacity))
        var rightOut = [Float32](repeating: 0, count: Int(capacity))

        leftOut.withUnsafeMutableBufferPointer { lPtr in
            rightOut.withUnsafeMutableBufferPointer { rPtr in
                ring.read(intoLeft: lPtr.baseAddress!, right: rPtr.baseAddress!, frames: Int(capacity))
            }
        }

        // No debe haber provocado fallo de memoria
        XCTAssertEqual(ring.availableFrames, 0)
    }

    func testSingleSampleWrite() {
        let ring = AudioRingBuffer(capacityFrames: 64)
        ring.writeSample(left: 3276, right: -3276)

        XCTAssertEqual(ring.availableFrames, 1)

        var l: Float32 = 0
        var r: Float32 = 0
        ring.read(intoLeft: &l, right: &r, frames: 1)

        XCTAssertEqual(l, 0.1, accuracy: 0.001)
        XCTAssertEqual(r, -0.1, accuracy: 0.001)
    }
}
