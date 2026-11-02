//
//  MetalRenderer.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Implements Phase 3 (Metal Video Pipeline): MTKViewDelegate, dynamic texture resizing,
//  double-buffering thread safety, and sharp-bilinear rendering.
//

import Foundation
import Metal
import MetalKit
import os

// MARK: - Modos de Filtrado Gráfico

public enum PixelFilterMode: UInt32, CaseIterable, Sendable {
    case sharpBilinear = 0
    case nearest = 1
    case standardBilinear = 2
}

// MARK: - Estructura de Uniforms (C-ABI Compatible)

public struct RenderUniforms {
    public var viewportSize: SIMD2<Float>
    public var textureSize: SIMD2<Float>
    public var targetAspectRatio: Float
    public var filterMode: UInt32

    public init(viewportSize: SIMD2<Float>, textureSize: SIMD2<Float>, targetAspectRatio: Float, filterMode: UInt32) {
        self.viewportSize = viewportSize
        self.textureSize = textureSize
        self.targetAspectRatio = targetAspectRatio
        self.filterMode = filterMode
    }
}

// MARK: - MetalRenderer Implementation

public final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {

    // MARK: Metal Core Objects
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var linearSampler: MTLSamplerState!
    private var pointSampler: MTLSamplerState!

    // MARK: Double Buffering de Texturas
    // `textureA` y `textureB` se alternan para evitar condiciones de carrera entre
    // el hilo de emulación (que invoca updateFrame a ~60 Hz) y el bucle de renderizado de Metal.
    private var textureA: MTLTexture?
    private var textureB: MTLTexture?
    private var isWritingToA: Bool = false
    private var activeReadTexture: MTLTexture?

    // Cerrojo ultraligero para sincronización de punteros de textura sin bloqueo de hilos
    private var lock = os_unfair_lock()

    // MARK: Dimensiones y Configuración de Pantalla
    public var filterMode: PixelFilterMode = .sharpBilinear
    public var targetAspectRatio: Float = 4.0 / 3.0
    public private(set) var currentWidth: Int = 0
    public private(set) var currentHeight: Int = 0

    // MARK: - Inicialización

    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("No se pudo instanciar MTLCommandQueue para el dispositivo Metal seleccionado.")
        }
        self.commandQueue = queue
        super.init()

        try buildPipelineState()
        buildSamplers()
    }

    // MARK: - Construcción del Pipeline y Compilación de Shaders

    private func buildPipelineState() throws {
        let library: MTLLibrary

        // Intento 1: Cargar la biblioteca precompilada del bundle (.metallib generado por Xcode)
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            // Intento 2 (Fallback): Compilación de MSL en tiempo de ejecución en el driver de Apple Silicon.
            // Esto garantiza funcionamiento inmediato sin requerir configuración previa de build rules de Metal.
            let mslSource = """
            #include <metal_stdlib>
            using namespace metal;

            struct VertexOut {
                float4 position [[position]];
                float2 texCoord;
            };

            struct Uniforms {
                float2 viewportSize;
                float2 textureSize;
                float targetAspectRatio;
                uint filterMode;
            };

            vertex VertexOut gameVertexShader(uint vertexID [[vertex_id]],
                                              constant Uniforms &uniforms [[buffer(0)]]) {
                float2 positions[4] = {
                    float2(-1.0, -1.0),
                    float2( 1.0, -1.0),
                    float2(-1.0,  1.0),
                    float2( 1.0,  1.0)
                };

                float2 texCoords[4] = {
                    float2(0.0, 1.0),
                    float2(1.0, 1.0),
                    float2(0.0, 0.0),
                    float2(1.0, 0.0)
                };

                float viewAspect = uniforms.viewportSize.x / max(uniforms.viewportSize.y, 1.0);
                float targetAspect = uniforms.targetAspectRatio > 0.0 ? uniforms.targetAspectRatio : (4.0 / 3.0);

                float2 scale = float2(1.0, 1.0);
                if (viewAspect > targetAspect) {
                    scale.x = targetAspect / viewAspect;
                } else {
                    scale.y = viewAspect / targetAspect;
                }

                VertexOut out;
                out.position = float4(positions[vertexID] * scale, 0.0, 1.0);
                out.texCoord = texCoords[vertexID];
                return out;
            }

            fragment float4 gameFragmentShader(VertexOut in [[stage_in]],
                                               texture2d<float> gameTexture [[texture(0)]],
                                               sampler linearSampler [[sampler(0)]],
                                               sampler pointSampler [[sampler(1)]],
                                               constant Uniforms &uniforms [[buffer(0)]]) {
                if (uniforms.filterMode == 1) {
                    return gameTexture.sample(pointSampler, in.texCoord);
                }
                if (uniforms.filterMode == 2) {
                    return gameTexture.sample(linearSampler, in.texCoord);
                }

                float2 texelSize = 1.0 / max(uniforms.textureSize, float2(1.0));
                float2 texCoordPixels = in.texCoord * uniforms.textureSize;
                float2 center = floor(texCoordPixels - 0.5) + 0.5;
                float2 f = (texCoordPixels - 0.5) - floor(texCoordPixels - 0.5);

                float2 screenScale = max(float2(1.0), uniforms.viewportSize / max(uniforms.textureSize, float2(1.0)));
                float2 sharp_f = clamp((f - 0.5) * screenScale + 0.5, 0.0, 1.0);

                float2 sampleCoord = (center + sharp_f) * texelSize;
                return gameTexture.sample(linearSampler, sampleCoord);
            }
            """
            library = try device.makeLibrary(source: mslSource, options: nil)
        }

        guard let vertexFunc = library.makeFunction(name: "gameVertexShader"),
              let fragmentFunc = library.makeFunction(name: "gameFragmentShader") else {
            fatalError("No se pudieron localizar las funciones 'gameVertexShader' o 'gameFragmentShader' en la biblioteca Metal.")
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "Constructor Video Pipeline"
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
    }

    private func buildSamplers() {
        // Sampler lineal para sharp-bilinear y escalado suave
        let linearDesc = MTLSamplerDescriptor()
        linearDesc.minFilter = .linear
        linearDesc.magFilter = .linear
        linearDesc.mipFilter = .notMipmapped
        linearDesc.sAddressMode = .clampToEdge
        linearDesc.tAddressMode = .clampToEdge
        self.linearSampler = device.makeSamplerState(descriptor: linearDesc)

        // Sampler por punto para Nearest Neighbor estricto
        let pointDesc = MTLSamplerDescriptor()
        pointDesc.minFilter = .nearest
        pointDesc.magFilter = .nearest
        pointDesc.mipFilter = .notMipmapped
        pointDesc.sAddressMode = .clampToEdge
        pointDesc.tAddressMode = .clampToEdge
        self.pointSampler = device.makeSamplerState(descriptor: pointDesc)
    }

    // MARK: - Actualización de Fotograma desde Libretro (Hilo Productor)
    // Se invoca directamente desde `onVideoFrame` en `LibretroCore`.
    // Maneja transiciones de resolución dinámicas (320x200 -> 640x480) y actualiza la textura trasera.

    public func updateFrame(data: UnsafeRawPointer?, width: Int, height: Int, pitch: Int) {
        guard let data = data, width > 0, height > 0, pitch > 0 else {
            // Un puntero nil en Libretro representa un frame duplicado (sin cambios gráficos)
            return
        }

        os_unfair_lock_lock(&lock)
        let needsReallocation = (textureA == nil || width != currentWidth || height != currentHeight)
        if needsReallocation {
            // Creamos un par de texturas en memoria unificada (MTLStorageMode.shared)
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.storageMode = .shared
            desc.usage = [.shaderRead]

            self.textureA = device.makeTexture(descriptor: desc)
            self.textureB = device.makeTexture(descriptor: desc)
            self.currentWidth = width
            self.currentHeight = height
            self.activeReadTexture = textureA
            self.isWritingToA = false
        }

        // Seleccionamos la textura de escritura (back buffer)
        let writeTexture = isWritingToA ? textureA : textureB
        os_unfair_lock_unlock(&lock)

        guard let targetTexture = writeTexture else { return }

        // Copiamos los píxeles de CPU a GPU. En Apple Silicon (SoC con memoria unificada),
        // este reemplazo no copia por PCIe sino que sincroniza la caché del chip inmediatamente.
        let region = MTLRegionMake2D(0, 0, width, height)
        targetTexture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: pitch)

        // Publicación atómica de la nueva textura hacia el renderizador
        os_unfair_lock_lock(&lock)
        self.activeReadTexture = targetTexture
        self.isWritingToA.toggle()
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // El cálculo de aspect ratio y escala se recalcula en cada fotograma vía Uniforms
    }

    public func draw(in view: MTKView) {
        os_unfair_lock_lock(&lock)
        let texture = activeReadTexture
        let width = currentWidth
        let height = currentHeight
        os_unfair_lock_unlock(&lock)

        guard let currentTexture = texture, width > 0, height > 0,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        var uniforms = RenderUniforms(
            viewportSize: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            textureSize: SIMD2<Float>(Float(width), Float(height)),
            targetAspectRatio: targetAspectRatio,
            filterMode: filterMode.rawValue
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(currentTexture, index: 0)
        encoder.setFragmentSamplerState(linearSampler, index: 0)
        encoder.setFragmentSamplerState(pointSampler, index: 1)

        // Dibuja el quad (triangle strip de 4 vértices sin buffers CPU)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Conversión de Coordenadas para Entrada de Ratón (Fase 5)
    // Mapea un punto en coordenadas de vista de macOS (AppKit) a las coordenadas nativas
    // del juego (e.g. 640x480), descartando el offset de las barras negras de pillarbox/letterbox.

    public func convertWindowPointToGamePoint(_ point: CGPoint, viewSize: CGSize) -> CGPoint? {
        guard currentWidth > 0, currentHeight > 0, viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }

        let viewAspect = Float(viewSize.width / viewSize.height)
        let targetAspect = targetAspectRatio

        var gameRect = CGRect.zero
        if viewAspect > targetAspect {
            // Pillarboxing: el juego ocupa toda la altura, con márgenes laterales
            let gameWidth = viewSize.height * CGFloat(targetAspect)
            let xOffset = (viewSize.width - gameWidth) * 0.5
            gameRect = CGRect(x: xOffset, y: 0, width: gameWidth, height: viewSize.height)
        } else {
            // Letterboxing: el juego ocupa todo el ancho, con márgenes superior/inferior
            let gameHeight = viewSize.width / CGFloat(targetAspect)
            let yOffset = (viewSize.height - gameHeight) * 0.5
            gameRect = CGRect(x: 0, y: yOffset, width: viewSize.width, height: gameHeight)
        }

        // Comprobación inclusiva de límites para abarcar píxeles de frontera
        guard point.x >= gameRect.minX && point.x <= gameRect.maxX &&
              point.y >= gameRect.minY && point.y <= gameRect.maxY else {
            return nil // El cursor está sobre las barras negras
        }

        // Mapeo normalizado [0.0, 1.0] dentro del rectángulo útil
        let normX = min(max((point.x - gameRect.origin.x) / gameRect.width, 0.0), 1.0)
        let normY = min(max((point.y - gameRect.origin.y) / gameRect.height, 0.0), 1.0)

        // Coordenadas absolutas de DOS
        let dosX = normX * CGFloat(currentWidth)
        let dosY = normY * CGFloat(currentHeight)
        return CGPoint(x: dosX, y: dosY)
    }
}
