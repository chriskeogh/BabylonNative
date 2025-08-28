//
//  MetalView.swift
//  SwiftLumi
//
//  Created by Chris on 26/08/2025.
//

import SwiftUI
import MetalKit

// see say https://www.delasign.com/blog/metal-uiview-triangle/
// https://carlosmbe.medium.com/swift-x-metal-for-3d-graphics-rendering-part-1-setting-up-in-swiftui-d2e90d6e5ec3


struct LumiMetalView: UIViewRepresentable {
    
    var babylonLumi : LibNativeBridge
    
    init( babylonLumi : LibNativeBridge)
    {
        self.babylonLumi = babylonLumi
        
        
    }
    
    func makeCoordinator() -> LumiBabylonRenderer {
        LumiBabylonRenderer(self)
    }
    
    func makeUIView(context: UIViewRepresentableContext<LumiMetalView>) -> MTKView {
        
        let mtkView = MTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        
        // Constant draw mode (!paused and don't need to isssue setNeedsDisplay calls)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        // Set expected frame buffer format
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.depthStencilPixelFormat = .depth32Float
        
        // Use the same device as Babylon made on init
        mtkView.device = babylonLumi.currentDevice()
              
        mtkView.framebufferOnly = false
        mtkView.drawableSize = mtkView.frame.size
        
        // Simple gesture recognizer
        let gesture = UIBabylonGestureRecognizer(
            target: self,
            onTouchDown: babylonLumi.setTouchDown,
            onTouchMove: babylonLumi.setTouchMove,
            onTouchUp: babylonLumi.setTouchUp
        )
        mtkView.addGestureRecognizer(gesture)
    
        
        return mtkView
    }
        
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<LumiMetalView>) {
  
    }
    
}

class LumiBabylonRenderer : NSObject, MTKViewDelegate {
   
    var parent : LumiMetalView
    var haveRendered : Bool = false
    
    init(_ parent : LumiMetalView) {
        self.parent = parent
        super.init()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        let screenScale = view.contentScaleFactor
        let width : Int32 = Int32(size.width) //* screenScale)
        let height : Int32 = Int32(size.height) // * screenScale)
        debugPrint("resize: w:\(width) h:\(height) scale:\(screenScale), on \(view)")
        self.parent.babylonLumi.resize( view, width: width, height: height );
    }

    func draw(in view: MTKView) {
        //debugPrint("render: \(view)")
        self.parent.babylonLumi.render();
  
        
    }
    
}
