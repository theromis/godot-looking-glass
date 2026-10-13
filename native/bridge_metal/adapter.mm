#include "adapter.hpp"
#include <atomic>
#include <cmath>
#include <dlfcn.h>
namespace looking_glass {
static std::atomic<bool> session_owned{false};
bool MetalAdapter::fail(const std::string &message) { error_ = message; return false; }
MetalAdapter::~MetalAdapter() {
    if (!close()) {
        // Failed SDK teardown must not unload code or free textures still in use.
        // Intentionally pin this failed session until process exit.
        (void)CFBridgingRetain(device_);
        (void)CFBridgingRetain(queue_);
        (void)CFBridgingRetain(output_);
        (void)CFBridgingRetain(previous_outputs_);
    }
}
bool MetalAdapter::load(const std::string &path) {
    if (library_) return fail("Adapter already loaded");
    library_ = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!library_) return fail("Cannot load SDK library");
#define LG_SYMBOL(field, name) field = reinterpret_cast<decltype(field)>(dlsym(library_, name)); if (!field) { close(); return fail(std::string("Missing SDK symbol: ") + name); }
    LG_SYMBOL(initialize_, "initialize_bridge")
    LG_SYMBOL(shutdown_, "uninitialize_bridge")
    LG_SYMBOL(version_fn_, "get_bridge_version")
    LG_SYMBOL(window_fn_, "instance_window_metal")
    LG_SYMBOL(create_, "create_metal_texture_with_iosurface")
    LG_SYMBOL(release_, "release_metal_texture")
    LG_SYMBOL(draw_, "draw_interop_quilt_texture_metal")
#undef LG_SYMBOL
    unsigned long major=0,minor=0,build=0;
    int chars=0;
    if (!version_fn_(&major,&minor,&build,&chars,nullptr)) { close(); return fail("Cannot query SDK version"); }
    if (major != 2 || minor < 6) { close(); return fail("Unsupported SDK version; expected 2.6 or later within major 2"); }
    version_=std::to_string(major)+"."+std::to_string(minor)+"."+std::to_string(build);
    error_.clear();
    return true;
}
bool MetalAdapter::open(id<MTLDevice> device, unsigned long index) {
    if (!library_ || initialized_ || !device) return fail("Invalid adapter state/device");
    if (index == static_cast<unsigned long>(FIRST_LOOKING_GLASS_DEVICE) || index == static_cast<unsigned long>(OFFSCREEN_WINDOW)) return fail("Explicit calibrated display index required");
    bool expected=false;
    if (!session_owned.compare_exchange_strong(expected,true)) return fail("Another adapter owns the native SDK session");
    owns_session_=true;
    if (!initialize_("Godot Looking Glass Metal diagnostic")) { close(); return fail("SDK initialization failed"); }
    initialized_=true;
    device_=device;
    queue_=[device newCommandQueue];
    if (!queue_ || !window_fn_((__bridge void *)device,&window_,index)) { close(); return fail("Cannot create SDK window for selected display"); }
    error_.clear();
    return true;
}
bool MetalAdapter::submit_once(id<MTLTexture> source, id<MTLCommandBuffer> producer, unsigned long columns, unsigned long rows, float aspect, float zoom) {
    if (!initialized_ || submitted_ || output_ || !source || !producer) return fail("One-shot submission requires open session without an existing target, texture and producer command buffer");
    if (source.device != device_ || producer.commandQueue.device != device_) return fail("Metal device mismatch");
    if (!columns || !rows || source.width%columns || source.height%rows || !std::isfinite(aspect) || aspect<=0 || !std::isfinite(zoom) || zoom<=0) return fail("Invalid quilt geometry");
    if (source.textureType != MTLTextureType2D || source.sampleCount != 1 || source.arrayLength != 1 || (source.pixelFormat != MTLPixelFormatRGBA16Float && source.pixelFormat != MTLPixelFormatRGBA8Unorm)) return fail("Expected single-sample 2D RGBA16Float or RGBA8Unorm quilt");
    if (producer.status == MTLCommandBufferStatusNotEnqueued || producer.status == MTLCommandBufferStatusEnqueued) return fail("Producer must already be committed");
    [producer waitUntilCompleted];
    if (producer.status != MTLCommandBufferStatusCompleted) return fail("Producer GPU work failed");
    submitted_=true; // No retry can overwrite or leak a previously allocated output.
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:source.pixelFormat width:source.width height:source.height mipmapped:NO];
    descriptor.usage=MTLTextureUsageShaderRead;
    descriptor.storageMode=MTLStorageModeShared;
    void *native_output=nullptr;
    if (!create_(window_,(__bridge void *)descriptor,&native_output) || !native_output) return fail("SDK output allocation failed");
    output_=(__bridge id<MTLTexture>)native_output;
    sdk_owns_output_=true;
    // Keep an ARC reference even during SDK release and session teardown.
    if (output_.device != device_ || output_.pixelFormat != source.pixelFormat || output_.width != source.width || output_.height != source.height) return fail("SDK texture does not match requested format/device/size");
    id<MTLCommandBuffer> copy=[queue_ commandBuffer];
    id<MTLBlitCommandEncoder> blit=[copy blitCommandEncoder];
    if (!copy || !blit) return fail("Cannot create GPU copy commands");
    [blit copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(source.width,source.height,1) toTexture:output_ destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding];
    [copy commit];
    [copy waitUntilCompleted];
    if (copy.status != MTLCommandBufferStatusCompleted) return fail("GPU copy failed");
    if (!draw_(window_,(__bridge void *)output_,columns,rows,aspect,zoom)) return fail("SDK quilt submission failed");
    error_.clear();
    return true;
}
bool MetalAdapter::append_immutable(id<MTLTexture> source, id<MTLCommandBuffer> producer, unsigned long columns, unsigned long rows, float aspect) {
    if (!initialized_ || !source || source.pixelFormat!=MTLPixelFormatRGBA8Unorm) return fail("Sequence requires open session and RGBA8 source");
    uint64_t bytes=static_cast<uint64_t>(source.width)*source.height*4;
    if (previous_outputs_.count+(output_?1:0)>=16 || bytes>128*1024*1024 || sequence_bytes_>128*1024*1024-bytes) return fail("Immutable sequence budget exceeded (16 frames / 128 MiB texture payload)");
    if (output_) {
        if (!submitted_) return fail("Cannot archive an unsubmitted direct target");
        if (!sdk_owns_output_) return fail("Cannot extend a released sequence");
        if (!previous_outputs_) previous_outputs_=[NSMutableArray new];
        [previous_outputs_ addObject:output_];
        output_=nil; sdk_owns_output_=false;
    }
    submitted_=false;
    if (!submit_once(source,producer,columns,rows,aspect)) return false;
    sequence_bytes_+=bytes;
    return true;
}
bool MetalAdapter::prepare_direct_rgba8(unsigned long width, unsigned long height) {
    if (!initialized_ || output_ || submitted_ || !width || !height || width>8192 || height>8192 || width*height>128*1024*1024/4) return fail("Direct target requires open unused session and bounded RGBA8 dimensions");
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared;
    descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    void *native=nullptr;
    if (!create_(window_,(__bridge void *)descriptor,&native) || !native) return fail("Direct SDK target allocation failed");
    output_=(__bridge id<MTLTexture>)native;
    sdk_owns_output_=true;
    if (output_.device!=device_ || output_.pixelFormat!=MTLPixelFormatRGBA8Unorm || output_.width!=width || output_.height!=height) return fail("Direct SDK target descriptor mismatch");
    return true;
}
bool MetalAdapter::submit_direct(id<MTLCommandBuffer> producer, unsigned long columns, unsigned long rows, float aspect, bool experimental_reuse) {
    if (!initialized_ || !output_ || (submitted_ && !experimental_reuse) || !producer || producer.commandQueue.device!=device_ || !columns || !rows || output_.width%columns || output_.height%rows || !std::isfinite(aspect) || aspect<=0) return fail("Invalid direct producer/geometry or already submitted target");
    if (producer.status==MTLCommandBufferStatusNotEnqueued || producer.status==MTLCommandBufferStatusEnqueued) return fail("Direct producer must be committed");
    [producer waitUntilCompleted];
    if (producer.status!=MTLCommandBufferStatusCompleted) return fail("Direct producer failed");
    submitted_=true;
    if (!draw_(window_,(__bridge void *)output_,columns,rows,aspect,1)) return fail("Direct target draw failed");
    return true;
}
bool MetalAdapter::pump_latest_immutable(unsigned long columns, unsigned long rows, float aspect) {
    if (![NSThread isMainThread] || !initialized_ || !output_ || !submitted_ || !columns || !rows || output_.width%columns || output_.height%rows || !std::isfinite(aspect) || aspect<=0) return fail("Pump requires main thread and submitted immutable quilt with valid geometry");
    auto show=reinterpret_cast<decltype(&show_window)>(dlsym(library_,"show_window"));
    auto pump=reinterpret_cast<void(*)()>(dlsym(library_,"SDL_PumpEvents"));
    if (!show || !show(window_,true)) return fail("Cannot show Bridge window");
    if (pump) pump();
    if (!draw_(window_,(__bridge void *)output_,columns,rows,aspect,1)) return fail("Immutable pump draw failed");
    return true; // No overwrite, texture reuse or consumer-fence assertion.
}
bool MetalAdapter::show_immutable(unsigned long columns, unsigned long rows, float aspect, double seconds, double frames_per_second) {
    if (![NSThread isMainThread] || !output_ || !submitted_ || !std::isfinite(seconds) || seconds<=0 || seconds>30 || !std::isfinite(frames_per_second) || frames_per_second<=0 || frames_per_second>60) return fail("Immutable display requires main thread, submitted quilt and bounded duration/rate");
    auto show=reinterpret_cast<decltype(&show_window)>(dlsym(library_,"show_window"));
    auto pump=reinterpret_cast<void(*)()>(dlsym(library_,"SDL_PumpEvents"));
    if (!show || !show(window_,true)) return fail("Cannot show Bridge window");
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds];
    NSDate *started=[NSDate date];
    while ([deadline timeIntervalSinceNow]>0) {
        if (pump) pump();
        NSUInteger frame=static_cast<NSUInteger>(-[started timeIntervalSinceNow]*frames_per_second)%(previous_outputs_.count+1);
        id<MTLTexture> selected=frame<previous_outputs_.count?previous_outputs_[frame]:output_;
        if (!draw_(window_,(__bridge void *)selected,columns,rows,aspect,1)) return fail("Immutable resubmission failed");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return true; // Texture never modified; no consumer completion-fence claim.
}
bool MetalAdapter::close() {
    while (initialized_ && previous_released_<previous_outputs_.count) {
        if (!release_(window_,(__bridge void *)previous_outputs_[previous_released_])) return fail("Sequence texture release failed; session remains pinned");
        ++previous_released_;
    }
    if (output_ && initialized_ && sdk_owns_output_) {
        if (!release_(window_,(__bridge void *)output_)) return fail("SDK texture release failed; session remains pinned");
        sdk_owns_output_=false;
    }
    if (initialized_ && !shutdown_()) return fail("SDK shutdown failed; session remains pinned");
    output_=nil; previous_outputs_=nil; previous_released_=0; sequence_bytes_=0; queue_=nil; device_=nil;
    window_=0; initialized_=false; submitted_=false;
    if (library_) dlclose(library_);
    library_=nullptr;
    if (owns_session_) session_owned=false;
    owns_session_=false;
    return true;
}
}
