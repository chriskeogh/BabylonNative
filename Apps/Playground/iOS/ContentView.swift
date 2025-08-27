//
//  ContentView.swift
//  SwiftLumi
//
//  Created by Chris on 26/08/2025.
//

import SwiftUI
import MetalKit

extension View {
    @ViewBuilder func isHidden(_ isHidden: Bool) -> some View {
        if isHidden {
            self.hidden()
        } else {
            self
        }
    }
}

extension TimeInterval{
    
    func stringFromTimeInterval() -> String {
        
        let time = NSInteger(self)
        let ms = Int((self.truncatingRemainder(dividingBy: 1)) * 1000)
        let seconds = time % 60
        return String(format: "%0.1d.%0.3d",seconds,ms)
    }
}

struct ContentView: View {
    
    @Observable
    class ViewModel {
        var LumiViewVisible : Bool = false
        var LumiViewReady : Bool = false
        var startAppTime = Date()
        var startLumiTime = Date()
        var lumiPreLoadTimeString : String = "x.x"
        var lumiAppearLoadTimeString : String = "x.x"
        var lumiFpsString : String = ""
        var babylonLumi : LibNativeBridge = LibNativeBridge()
    }
    
    @State private var viewModel = ViewModel()
    
    let timer = Timer.publish(every: 0.05, on: .current, in: .commonModes).autoconnect()
    let backgroundMetalView : MTKView;
    
    init() {
        
        self.backgroundMetalView = MTKView()
        self.backgroundMetalView.device = self.viewModel.babylonLumi.currentDevice()
        self.backgroundMetalView.isHidden = true
        self.backgroundMetalView.enableSetNeedsDisplay = true
        self.backgroundMetalView.isPaused = true
        self.backgroundMetalView.colorPixelFormat = .bgra8Unorm_srgb
        self.backgroundMetalView.depthStencilPixelFormat = .depth32Float
        self.backgroundMetalView.framebufferOnly = false
        self.backgroundMetalView.drawableSize = CGSize(width:8, height:8)
        
        //CJK start js and as most experience as we can up to first render
        self.viewModel.babylonLumi.preload( backgroundMetalView,
            onPreLoadDone: { [self] _ in
                viewModel.LumiViewReady = true
                viewModel.lumiPreLoadTimeString = "\(Date().timeIntervalSince(viewModel.startAppTime).stringFromTimeInterval())"
            },
            onFirstRenderDone: { [self] _ in
                viewModel.lumiAppearLoadTimeString = "\(Date().timeIntervalSince(viewModel.startLumiTime).stringFromTimeInterval())"
            },
            onStats: { [self] fps in
            viewModel.lumiFpsString = "\(fps.rounded())"
            }
        )
    }
    
    var body: some View {
        return Group {
            if viewModel.LumiViewVisible {
                ZStack {
                    LumiMetalView(babylonLumi: viewModel.babylonLumi)
                    VStack{
                        Text("View \(viewModel.lumiAppearLoadTimeString)")
                        Text("Preload \(viewModel.lumiPreLoadTimeString)")
                        Text("FPS \(viewModel.lumiFpsString)")
                   }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            else {
                ZStack {
                    LinearGradient(
                        colors: [
                            .white,
                            .blue ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack {
                        Image(systemName: "globe")
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                        Text("Welcome to Copilot in Swift!").padding()
                        Button( "Show Native Lumi", action: {
                            debugPrint("Going into Lumi mode..")
                            viewModel.startLumiTime = Date() // start our timer
                            viewModel.LumiViewVisible = true // will switch implictly to LumiMetalView next refresh
                        }).foregroundColor( .white )
                        ProgressView().isHidden(viewModel.LumiViewReady)
                        Text("\(viewModel.lumiPreLoadTimeString)").font(Font.system(size:30, design: .monospaced)).onReceive(timer) {_ in
                            if (!viewModel.LumiViewReady)
                            {
                                viewModel.lumiPreLoadTimeString = "\(Date().timeIntervalSince(viewModel.startAppTime).stringFromTimeInterval())"
                            }
                        }
                      
                    }.padding()
                }.ignoresSafeArea()
            }
        }
    }
}

#Preview {
    ContentView()
}
