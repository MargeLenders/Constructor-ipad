//
//  GameView.swift
//  ConstructorHost
//
//  Created for Constructor (1997) Native macOS Apple Silicon Wrapper.
//  Adaptador NSViewRepresentable para integrar GameMTKView e InputManager en SwiftUI.
//

import SwiftUI
import MetalKit

public struct GameView: NSViewRepresentable {

    public let renderer: MetalRenderer
    public let inputManager: InputManager?

    public init(renderer: MetalRenderer, inputManager: InputManager? = nil) {
        self.renderer = renderer
        self.inputManager = inputManager
    }

    public func makeNSView(context: Context) -> GameMTKView {
        let view = GameMTKView(frame: .zero, device: renderer.device, renderer: renderer, inputManager: inputManager)
        return view
    }

    public func updateNSView(_ nsView: GameMTKView, context: Context) {
        nsView.inputManager = inputManager
    }
}
