#include "LibNativeBridge.h"

#import <Babylon/AppRuntime.h>
#import <Babylon/Graphics/Device.h>
#import <Babylon/ScriptLoader.h>
#import <Babylon/Plugins/NativeCamera.h>
#import <Babylon/Plugins/NativeEngine.h>
#import <Babylon/Plugins/NativeInput.h>
#import <Babylon/Plugins/NativeOptimizations.h>
#import <Babylon/Plugins/NativeXr.h>
#import <Babylon/Polyfills/Canvas.h>
#import <Babylon/Polyfills/Console.h>
#import <Babylon/Polyfills/Window.h>
#import <Babylon/Polyfills/XMLHttpRequest.h>
#import <Babylon/ShaderCache.h>
#import <Babylon/DebugTrace.h>
#import <optional>
#import <fstream>

#define ENABLE_PERSISTENT_SHADER_CACHE 1
#ifdef BABYLON_DEBUG_TRACE
#define ON_DEBUG_TRACE(x) x
#else
#define ON_DEBUG_TRACE(x)
#endif

id<MTLDevice> mtlDevice;

std::optional<Babylon::Graphics::Device> device{};
std::optional<Babylon::Graphics::DeviceUpdate> update{};
std::optional<Babylon::AppRuntime> runtime{};
std::optional<Babylon::Polyfills::Canvas> nativeCanvas{};
std::optional<Babylon::Plugins::NativeXr> nativeXr{};
Babylon::Plugins::NativeInput* nativeInput{};
bool isXrActive{};
float screenScale{1.0f};
std::string appCacheFilePath;

// CJK just for debug/profiling this test
bool haveRendered = false;
typedef void (^StatusCallback)(BOOL status);
StatusCallback onFirstRenderCallback;
typedef void (^StatsCallback)(float fps);
StatsCallback onStatsUpdateCallback;
int renderedFrames = 0;
double lastRenderTimestamp = 0;

// CJK make sure we wait on the load before we render
pthread_mutex_t engineReadyMutex;

@implementation LibNativeBridge

- (instancetype)init
{
    self = [super init];
    
    pthread_mutex_init(&engineReadyMutex, NULL);
    pthread_mutex_lock(&engineReadyMutex);

    mtlDevice = MTLCreateSystemDefaultDevice();
   
    return self;
}

- (void)saveShaderCache
{
#if ENABLE_PERSISTENT_SHADER_CACHE
   // Try to save the shader cache, but only if have some shaders as Uninitialize called first on init
   if (device && Babylon::ShaderCache::Enabled() && !appCacheFilePath.empty())
   {
       std::ofstream fileSerialize(appCacheFilePath, std::ios::binary);
       if (fileSerialize.good())
       {
           ON_DEBUG_TRACE( uint32_t shaderCount = ) Babylon::ShaderCache::Serialize(fileSerialize);
           DEBUG_TRACE("Saved %d shaders to %s", shaderCount, appCacheFilePath.c_str());
       }
       else
       {
           DEBUG_TRACE("Could not save shaders to %s", appCacheFilePath.c_str());
       }
   }
#endif
}

// called from applicationWillTerminate
- (void)terminate
{
    [self saveShaderCache];
    
    // would normally call dealloc here too, but will trigger exceptions currently when called on iOS during termination
}

- (void)dealloc
{
    if (device)
    {
        update->Finish();
        device->FinishRenderingCurrentFrame();
    }
    
    nativeInput = {};
    nativeXr.reset();
    nativeCanvas.reset();
    runtime.reset();
    update.reset();
    device.reset();
}

- (id<MTLDevice>) currentDevice
{
    return mtlDevice;
}

- (void)preload:(MTKView*)hiddenView onPreLoadDone:(void (^)(BOOL success))onPreloadDone onFirstRenderDone:(void (^)(BOOL success))onFirstRender onStats:(void (^)(float fps))onStatsUpdate
{
     
    onFirstRenderCallback = onFirstRender;
    onStatsUpdateCallback = onStatsUpdate;
    
    Babylon::DebugTrace::EnableDebugTrace(true);
    Babylon::DebugTrace::SetTraceOutput([](const char* trace) { NSLog(@"%s", trace); });
   
    // CJK: Go for it.. but in a thread
    //  we use dispatch_after so that we at least return to caller before it gets going
    //
    // Debug: change delay secs you want, handy for debugging (to make sure render waits for it)
    // but we are using dispatch_get_main_queue so that render and resize match the thread this happens on
    // Right now this portion of the load is pretty quick, but we could go further here and make more threaded wrt main
    //
    int64_t StartDelay = (int64_t)(1*NSEC_PER_MSEC); // 1ms
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, StartDelay), dispatch_get_main_queue(), ^{
   
        // CJK give Babylon a device but a dummy window, so not fully headless but not fully rendering to screen either.
        // Ideally bgfx Mtl impl would aallow device but null Window, but without changes to bgfx it will always try to create
        // a framebuffer and if fails will make a NOOP render context etc, which is not what we want

        Babylon::Graphics::Configuration graphicsConfig{};
        graphicsConfig.Device = mtlDevice;
        graphicsConfig.Window = hiddenView;
        graphicsConfig.Width = 8;
        graphicsConfig.Height = 8;
        
        device.emplace(graphicsConfig);
        update.emplace(device->GetUpdate("update"));
        
        Babylon::ShaderCache::Enabled(true);
        
#if ENABLE_PERSISTENT_SHADER_CACHE
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *cacheDirectory = [paths objectAtIndex:0];
        if (cacheDirectory)
        {
            appCacheFilePath = [cacheDirectory UTF8String];
            appCacheFilePath.append("/");
            appCacheFilePath.append("PlaygroundShaderCache.bin");
        }
        if (!appCacheFilePath.empty())
        {
            std::ifstream file(appCacheFilePath, std::ios::binary);
            if (file.good())
            {
                ON_DEBUG_TRACE( uint32_t deserializedCount = ) Babylon::ShaderCache::Deserialize(file);
                DEBUG_TRACE("Loaded %d shaders from %s", deserializedCount, appCacheFilePath.c_str());
            }
            else
            {
                DEBUG_TRACE("Could not load shaders from %s", appCacheFilePath.c_str());
            }
        }
#endif
        
        device->StartRenderingCurrentFrame();
        update->Start();
        
        runtime.emplace();
        
        runtime->Dispatch([](Napi::Env env)
                          {
            device->AddToJavaScript(env);
            
            Babylon::Polyfills::Console::Initialize(env, [](const char* message, auto) {
                NSLog(@"[Console]  %s", message);
            });
            
            nativeCanvas.emplace(Babylon::Polyfills::Canvas::Initialize(env));
            
            Babylon::Polyfills::Window::Initialize(env);
            
            Babylon::Polyfills::XMLHttpRequest::Initialize(env);
            
            Babylon::Plugins::NativeCamera::Initialize(env);
            
            Babylon::Plugins::NativeEngine::Initialize(env);
            
            Babylon::Plugins::NativeOptimizations::Initialize(env);
            
            // CJK just to avoid any potential extra debugging, ignore XR:
            //nativeXr.emplace(Babylon::Plugins::NativeXr::Initialize(env));
            //nativeXr->UpdateWindow(xrView);
            //nativeXr->SetSessionStateChangedCallback([](bool isXrActive){ ::isXrActive = isXrActive; });
            
            nativeInput = &Babylon::Plugins::NativeInput::CreateForJavaScript(env);
        });
        
        Babylon::ScriptLoader loader{ *runtime };
        // loader.LoadScript("app:///Scripts/ammo.js");
        // loader.LoadScript("app:///Scripts/recast.js");
        // loader.LoadScript("app:///Scripts/babylon.max.js");
        // loader.LoadScript("app:///Scripts/babylonjs.loaders.js");
        // loader.LoadScript("app:///Scripts/babylonjs.materials.js");
        // loader.LoadScript("app:///Scripts/babylon.gui.js");
        loader.LoadScript("app:///Scripts/experience.js");
        
        
        pthread_mutex_unlock(&engineReadyMutex);
        
        //CJK TODO find best representative place for this
        //    want it to be say once js script waiting for render?
        onPreloadDone(true);
    });
}

- (void)resize:(MTKView*)view width:(int)inWidth height:(int)inHeight
{
    // CJK wait on first render for engine to init, block thread
    // TODO replace with something nicer, semaphore etc
    pthread_mutex_lock(&engineReadyMutex);
    if (device)
    {
        update->Finish();
        device->FinishRenderingCurrentFrame();

        // CJK If are given a view, asssume want to update to that, ignore if null
        if (view)
        {
            device->UpdateWindow(view);
        }
        device->UpdateSize(static_cast<size_t>(inWidth), static_cast<size_t>(inHeight));

        device->StartRenderingCurrentFrame();
        update->Start();
    }
    pthread_mutex_unlock(&engineReadyMutex);
   
}

- (void)render
{
    // CJK wait on first render for engine to init, block thread
    // TODO replace with something nicer, semaphore etc
    if (!haveRendered)
    {
        pthread_mutex_lock(&engineReadyMutex);
        pthread_mutex_unlock(&engineReadyMutex);
    }
    
    if (device)
    {
        update->Finish();
        device->FinishRenderingCurrentFrame();
            
        //CJK Debug gather some stats for easy display in Swift app
        ++renderedFrames;
        if (renderedFrames == 100)
        {
            double timestamp = [[NSDate date] timeIntervalSince1970];
            if (lastRenderTimestamp > 0 )
            {
                double timeFor100FramesInSeconds = timestamp - lastRenderTimestamp;
                float fps = 100 / timeFor100FramesInSeconds;
                onStatsUpdateCallback(fps);
            }
            lastRenderTimestamp = timestamp;
            renderedFrames = 0;
        }
               
        device->StartRenderingCurrentFrame();
        update->Start();
        
        //CJK Debug let app know we are rendering: not just first one, but actually see a few draw calls in stats
        //    Assuming stats not great, so should come up with proper callback on "have things in scene and rendering"
        if (!haveRendered) {\
            auto stats = device->GetStats();
            if (stats.NumDraw > 5)
            {
                haveRendered = true;
                onFirstRenderCallback(true);
            }
        }
    }
}

- (void)setTouchDown:(int)pointerId x:(int)inX y:(int)inY
{
    if (nativeInput != nullptr) {
        nativeInput->TouchDown(pointerId, inX * screenScale, inY * screenScale);
    }
}

- (void)setTouchMove:(int)pointerId x:(int)inX y:(int)inY
{
    if (nativeInput != nullptr) {
        nativeInput->TouchMove(pointerId, inX * screenScale, inY * screenScale);
    }
}

- (void)setTouchUp:(int)pointerId x:(int)inX y:(int)inY
{
    if (nativeInput != nullptr) {
        nativeInput->TouchUp(pointerId, inX * screenScale, inY * screenScale);
    }
}

- (bool)isXRActive
{
    return ::isXrActive;
}

@end
