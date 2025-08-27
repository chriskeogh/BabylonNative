#pragma once

#include <Foundation/Foundation.h>
#include <MetalKit/MetalKit.h>


@interface LibNativeBridge : NSObject

- (instancetype)init;
- (id<MTLDevice>)currentDevice;
- (void)preload:(MTKView*)hiddenView onPreLoadDone:(void (^)(BOOL success))onPreloadDone onFirstRenderDone:(void (^)(BOOL success))onFirstRender onStats:(void (^)(float fps))onStatsUpdate;
- (void)dealloc;
- (void)terminate;
- (void)resize:(MTKView*)inView width:(int)inWidth height:(int)inHeight;
- (void)render;
- (void)setTouchDown:(int)pointerId x:(int)inX y:(int)inY;
- (void)setTouchMove:(int)pointerId x:(int)inX y:(int)inY;
- (void)setTouchUp:(int)pointerId x:(int)inX y:(int)inY;
- (bool)isXRActive;

@end

