//
//  GameView_iOS.swift
//  ConstructorIOS
//
//  Created for Constructor (1997) Native iPadOS Apple Silicon Wrapper.
//  Adaptador UIViewRepresentable para integrar GameMTKView_iOS e InputManager_iOS en SwiftUI.
//

import SwiftUI
import MetalKit

public struct GameView_iOS: UIViewRepresentable {

    public let renderer: MetalRenderer
    public let inputManager: InputManager_iOS?

    public init(renderer: MetalRenderer, inputManager: InputManager_iOS? = nil) {
        self.renderer = renderer
        self.inputManager = inputManager
    }

    public func makeUIView(context: Context) -> GameMTKView_iOS {
        let view = GameMTKView_iOS(frame: .zero, device: renderer.device, renderer: renderer, inputManager: inputManager)
        return view
    }

    public func updateUIView(_ uiView: GameMTKView_iOS, context: Context) {
        uiView.inputManager = inputManager
    }
}
