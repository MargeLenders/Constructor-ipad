//
//  Shaders.metal
//  ConstructorHost
//
//  Metal Shading Language (MSL) Shaders for Constructor (1997).
//  Implements:
//  1. Automatic 4:3 Aspect Ratio preservation with hardware Pillarboxing/Letterboxing.
//  2. Sharp-Bilinear sub-pixel filtering to eliminate blurriness and pixel shimmering on Retina displays.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Structures

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float2 viewportSize;       // Ancho y alto del drawable de MTKView en píxeles físicos
    float2 textureSize;        // Ancho y alto de la resolución actual de DOS (320x200 o 640x480)
    float targetAspectRatio;   // 4:3 = 1.33333333
    uint filterMode;           // 0: Sharp Bilinear, 1: Nearest Neighbor, 2: Standard Bilinear
};

// MARK: - Vertex Shader
// Genera un quad a pantalla completa mediante 4 vértices calculados a partir de vertexID (sin buffers de vértices en CPU)
// y aplica corrección de escala en clip-space [-1.0, 1.0] para mantener estrictamente la relación 4:3.

vertex VertexOut gameVertexShader(uint vertexID [[vertex_id]],
                                  constant Uniforms &uniforms [[buffer(0)]]) {
    // Vértices del quad en orden triangle-strip
    // 0: Abajo-Izquierda, 1: Abajo-Derecha, 2: Arriba-Izquierda, 3: Arriba-Derecha
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    // Coordenadas UV normalizadas [0.0, 1.0]
    // En Metal, Y=1 en clip-space es arriba, mientras que en UV (0,0) es la esquina superior izquierda
    float2 texCoords[4] = {
        float2(0.0, 1.0), // Abajo-Izquierda
        float2(1.0, 1.0), // Abajo-Derecha
        float2(0.0, 0.0), // Arriba-Izquierda
        float2(1.0, 0.0)  // Arriba-Derecha
    };

    // Cálculo de relación de aspecto del viewport
    float viewAspect = uniforms.viewportSize.x / max(uniforms.viewportSize.y, 1.0);
    float targetAspect = uniforms.targetAspectRatio > 0.0 ? uniforms.targetAspectRatio : (4.0 / 3.0);

    float2 scale = float2(1.0, 1.0);
    if (viewAspect > targetAspect) {
        // Ventana más ancha que 4:3 -> Pillarboxing (barras negras laterales)
        scale.x = targetAspect / viewAspect;
    } else {
        // Ventana más alta que 4:3 -> Letterboxing (barras negras arriba y abajo)
        scale.y = viewAspect / targetAspect;
    }

    VertexOut out;
    out.position = float4(positions[vertexID] * scale, 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// MARK: - Fragment Shader
// Procesa las muestras del framebuffer de DOSBox-Pure.

fragment float4 gameFragmentShader(VertexOut in [[stage_in]],
                                   texture2d<float> gameTexture [[texture(0)]],
                                   sampler linearSampler [[sampler(0)]],
                                   sampler pointSampler [[sampler(1)]],
                                   constant Uniforms &uniforms [[buffer(0)]]) {
    // 1. Modo Vecino Más Cercano (Nearest Neighbor)
    if (uniforms.filterMode == 1) {
        return gameTexture.sample(pointSampler, in.texCoord);
    }

    // 2. Modo Bilineal Estándar (Soft Bilinear)
    if (uniforms.filterMode == 2) {
        return gameTexture.sample(linearSampler, in.texCoord);
    }

    // 3. Modo Sharp-Bilinear (Por defecto y óptimo para pantallas Retina)
    // Escala los píxeles de DOS con nitidez entera idéntica a Nearest Neighbor,
    // pero aplica una interpolación bilineal ultra-fina exclusivamente en la frontera
    // sub-píxel entre téxeles para evitar deformaciones o parpadeo ("shimmering").
    float2 texelSize = 1.0 / max(uniforms.textureSize, float2(1.0));
    float2 texCoordPixels = in.texCoord * uniforms.textureSize;

    // Centros de los téxeles
    float2 center = floor(texCoordPixels - 0.5) + 0.5;
    float2 f = (texCoordPixels - 0.5) - floor(texCoordPixels - 0.5);

    // Factor de escalado de la pantalla con respecto a la resolución de DOS
    float2 screenScale = max(float2(1.0), uniforms.viewportSize / max(uniforms.textureSize, float2(1.0)));

    // Afilar la transición fraccionaria (sub-pixel sharpening)
    float2 sharp_f = clamp((f - 0.5) * screenScale + 0.5, 0.0, 1.0);

    float2 sampleCoord = (center + sharp_f) * texelSize;
    return gameTexture.sample(linearSampler, sampleCoord);
}
