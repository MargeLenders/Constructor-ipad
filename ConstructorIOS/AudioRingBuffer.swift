//
//  AudioRingBuffer.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Implements Phase 4: Lock-Free Single Producer Single Consumer (SPSC) Ring Buffer
//  for real-time CoreAudio rendering with underrun/overrun protection and zero allocations.
//

import Foundation
import Darwin

/// Búfer circular Lock-Free de un solo productor (Libretro) y un solo consumidor (CoreAudio).
/// Garantiza seguridad en tiempo real: cero asignaciones de memoria, cero bloqueos (locks)
/// y sincronización mediante barreras de memoria en arquitectura ARM64.
public final class AudioRingBuffer: @unchecked Sendable {

    /// Capacidad total en fotogramas de audio (cada fotograma = 1 muestra Left + 1 muestra Right)
    public let capacityFrames: UInt32

    /// Máscara binaria para envoltorio rápido sin operaciones de módulo (%)
    private let mask: UInt32

    /// Búfer contiguo de muestras Int16 intercaladas preasignado en memoria heap
    private let buffer: UnsafeMutablePointer<Int16>

    /// Puntero de escritura (modificado exclusivamente por el hilo de emulación de Libretro)
    private var writeHead: UInt32 = 0

    /// Puntero de lectura (modificado exclusivamente por el hilo de tiempo real de CoreAudio)
    private var readHead: UInt32 = 0

    // MARK: - Inicialización y Ciclo de Vida

    /// Inicializa el búfer circular asegurando que la capacidad sea potencia de 2.
    /// Para 44.1 kHz, 16384 fotogramas proporcionan ~371 ms de margen elástico contra jitter.
    public init(capacityFrames: UInt32 = 16384) {
        var cap: UInt32 = 1
        while cap < capacityFrames {
            cap <<= 1
        }
        self.capacityFrames = cap
        self.mask = cap - 1

        // 2 canales estéreo por fotograma (Left, Right)
        let totalSamples = Int(cap * 2)
        self.buffer = .allocate(capacity: totalSamples)
        self.buffer.initialize(repeating: 0, count: totalSamples)
    }

    deinit {
        buffer.deallocate()
    }

    // MARK: - Escritura (Hilo Productor: Libretro retro_audio_sample_batch_t)

    /// Escribe un lote de fotogramas estéreo Int16 intercalados (L, R, L, R...).
    /// Tiempo de ejecución O(1), sin locks y con protección contra desbordamiento (overrun).
    public func write(interleavedData: UnsafePointer<Int16>, frames: Int) {
        guard frames > 0 else { return }
        let framesToWrite = UInt32(frames)

        let currentRead = readHead
        let currentWrite = writeHead
        let occupied = currentWrite &- currentRead
        let freeSpace = capacityFrames &- occupied

        var effectiveWrite = currentWrite
        var effectiveFrames = framesToWrite

        // Detección y manejo de desbordamiento (Overrun)
        if framesToWrite > freeSpace {
            if framesToWrite >= capacityFrames {
                // El lote supera toda la capacidad del búfer: descartamos las muestras más antiguas
                let offset = Int(framesToWrite - (capacityFrames - 1)) * 2
                let src = interleavedData.advanced(by: offset)
                effectiveFrames = capacityFrames - 1
                effectiveWrite = currentRead &+ 1
                writeHead = effectiveWrite
                return writeChunk(src: src, count: effectiveFrames, at: effectiveWrite)
            } else {
                // Adelantamos la cabeza de lectura para preservar baja latencia continua
                readHead = (currentWrite &+ framesToWrite) &- (capacityFrames - 1)
            }
        }

        writeChunk(src: interleavedData, count: effectiveFrames, at: effectiveWrite)
    }

    /// Escribe un único fotograma estéreo (L, R) procedente de retro_audio_sample_t.
    public func writeSample(left: Int16, right: Int16) {
        var samplePair = (left, right)
        withUnsafePointer(to: &samplePair) { ptr in
            ptr.withMemoryRebound(to: Int16.self, capacity: 2) { int16Ptr in
                write(interleavedData: int16Ptr, frames: 1)
            }
        }
    }

    private func writeChunk(src: UnsafePointer<Int16>, count: UInt32, at startPos: UInt32) {
        let startIdx = startPos & mask
        let framesToEnd = capacityFrames - startIdx

        if count <= framesToEnd {
            let dst = buffer.advanced(by: Int(startIdx * 2))
            dst.update(from: src, count: Int(count * 2))
        } else {
            // Envoltura alrededor del límite del búfer
            let firstChunk = framesToEnd
            let secondChunk = count - firstChunk

            let dst1 = buffer.advanced(by: Int(startIdx * 2))
            dst1.update(from: src, count: Int(firstChunk * 2))

            let dst2 = buffer
            dst2.update(from: src.advanced(by: Int(firstChunk * 2)), count: Int(secondChunk * 2))
        }

        // Barrera de memoria Store-Release: asegura que las muestras estén escritas en RAM
        // antes de hacer visible la nueva posición de writeHead para el consumidor CoreAudio.
        OSMemoryBarrier()
        writeHead = startPos &+ count
    }

    // MARK: - Lectura (Hilo Consumidor: CoreAudio Real-Time Render Block)

    /// Lee fotogramas del búfer circular, desintercalando y convirtiendo muestras Int16 a Float32 [-1.0, 1.0].
    /// Es estrictamente Real-Time Safe (sin alloc, sin locks, sin I/O).
    /// Si hay déficit de muestras (Underrun), rellena el remanente con silencio (0.0f) para evitar chasquidos.
    public func read(intoLeft leftOut: UnsafeMutablePointer<Float32>,
                     right rightOut: UnsafeMutablePointer<Float32>,
                     frames: Int) {
        guard frames > 0 else { return }
        let framesNeeded = UInt32(frames)

        // Barrera de memoria Load-Acquire: garantiza lectura coherente del índice del productor
        OSMemoryBarrier()
        let currentWrite = writeHead
        let currentRead = readHead
        let available = currentWrite &- currentRead

        let framesToRead = min(available, framesNeeded)
        let scale: Float32 = 1.0 / 32768.0

        if framesToRead > 0 {
            let startIdx = currentRead & mask
            let framesToEnd = capacityFrames - startIdx

            if framesToRead <= framesToEnd {
                var src = buffer.advanced(by: Int(startIdx * 2))
                for i in 0..<Int(framesToRead) {
                    leftOut[i] = Float32(src.pointee) * scale
                    rightOut[i] = Float32(src.advanced(by: 1).pointee) * scale
                    src = src.advanced(by: 2)
                }
            } else {
                let firstChunk = Int(framesToEnd)
                let secondChunk = Int(framesToRead - framesToEnd)

                var src1 = buffer.advanced(by: Int(startIdx * 2))
                for i in 0..<firstChunk {
                    leftOut[i] = Float32(src1.pointee) * scale
                    rightOut[i] = Float32(src1.advanced(by: 1).pointee) * scale
                    src1 = src1.advanced(by: 2)
                }

                var src2 = buffer
                for i in 0..<secondChunk {
                    leftOut[firstChunk + i] = Float32(src2.pointee) * scale
                    rightOut[firstChunk + i] = Float32(src2.advanced(by: 1).pointee) * scale
                    src2 = src2.advanced(by: 2)
                }
            }

            // Publicamos la lectura consumida mediante barrera
            OSMemoryBarrier()
            readHead = currentRead &+ framesToRead
        }

        // Protección contra Underrun: Si no hay suficientes muestras generadas por DOSBox,
        // inyectamos silencio absoluto (0.0f) para evitar ruido blanco o clics por datos residuales.
        if framesToRead < framesNeeded {
            let missing = Int(framesNeeded - framesToRead)
            let offset = Int(framesToRead)
            memset(leftOut.advanced(by: offset), 0, missing * MemoryLayout<Float32>.size)
            memset(rightOut.advanced(by: offset), 0, missing * MemoryLayout<Float32>.size)
        }
    }

    /// Cantidad de fotogramas listos para lectura inmediata en el búfer.
    public var availableFrames: UInt32 {
        OSMemoryBarrier()
        return writeHead &- readHead
    }

    /// Reinicia los índices de lectura y escritura a cero.
    public func reset() {
        writeHead = 0
        readHead = 0
        OSMemoryBarrier()
    }
}
