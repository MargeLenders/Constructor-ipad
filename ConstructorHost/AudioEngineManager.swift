//
//  AudioEngineManager.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Implements Phase 4: Integración con AVAudioEngine y AVAudioSourceNode en tiempo real.
//

import Foundation
import AVFoundation

public enum AudioEngineError: LocalizedError {
    case formatCreationFailed
    case engineStartFailed(error: String)

    public var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "No se pudo instanciar AVAudioFormat para el audio estéreo Float32 a 44.1 kHz."
        case .engineStartFailed(let err):
            return "Fallo al arrancar AVAudioEngine: \(err)"
        }
    }
}

public final class AudioEngineManager: @unchecked Sendable {

    public let engine: AVAudioEngine
    public let ringBuffer: AudioRingBuffer
    private var sourceNode: AVAudioSourceNode?
    public let sampleRate: Double

    // MARK: - Inicialización

    /// Inicializa el subsistema de audio con la frecuencia de muestreo de DOS (típicamente 44100 Hz).
    public init(sampleRate: Double = 44100.0, bufferCapacity: UInt32 = 16384) {
        self.sampleRate = sampleRate
        self.engine = AVAudioEngine()
        self.ringBuffer = AudioRingBuffer(capacityFrames: bufferCapacity)
        setupAudioPipeline()
    }

    // MARK: - Configuración de AVAudioSourceNode y Conexiones

    private func setupAudioPipeline() {
        let ring = self.ringBuffer

        // AVAudioSourceNode ejecuta su bloque de renderizado directamente en el hilo I/O de CoreAudio
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // Validar que existan ambos canales estéreo no intercalados (Float32)
            guard abl.count >= 2,
                  let leftBuffer = abl[0].mData?.assumingMemoryBound(to: Float32.self),
                  let rightBuffer = abl[1].mData?.assumingMemoryBound(to: Float32.self) else {
                return noErr
            }

            // Lectura libre de locks con protección contra underrun
            ring.read(intoLeft: leftBuffer, right: rightBuffer, frames: Int(frameCount))
            return noErr
        }
        self.sourceNode = node

        // Formato canónico de CoreAudio: Float32, no intercalado, 2 canales
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("Error crítico al crear el formato de audio para AVAudioSourceNode.")
        }

        engine.attach(node)

        // Conectar el nodo fuente al mezclador principal.
        // Si el hardware de salida del Mac opera a 48 kHz (estándar en Apple Silicon),
        // AVAudioEngine realiza la conversión de frecuencia de muestreo por hardware de forma transparente.
        engine.connect(node, to: engine.mainMixerNode, format: sourceFormat)
    }

    // MARK: - Enlace con LibretroCore

    /// Conecta los callbacks de audio del núcleo de emulación directamente al Ring Buffer.
    public func attach(to core: LibretroCore) {
        let ring = self.ringBuffer

        // Inyección del consumidor por lotes (retro_audio_sample_batch_t)
        core.onAudioBatch = { interleavedData, frames in
            ring.write(interleavedData: interleavedData, frames: frames)
            return frames
        }

        // Inyección del consumidor muestra por muestra (retro_audio_sample_t)
        core.onAudioSample = { left, right in
            ring.writeSample(left: left, right: right)
        }
    }

    // MARK: - Control de Volumen y Ciclo de Vida

    /// Volumen maestro (0.0 silencio a 1.0 volumen máximo)
    public var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0.0, min(1.0, newValue)) }
    }

    /// Inicia el motor de audio de CoreAudio
    public func start() throws {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            throw AudioEngineError.engineStartFailed(error: error.localizedDescription)
        }
    }

    /// Pausa el motor de audio
    public func pause() {
        if engine.isRunning {
            engine.pause()
        }
    }

    /// Detiene el motor de audio y resetea el búfer circular
    public func stop() {
        if engine.isRunning {
            engine.stop()
        }
        ringBuffer.reset()
    }
}
