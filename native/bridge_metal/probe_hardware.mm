// Real SDK diagnostic: one immutable quilt; no streaming or consumer-fence claim.
#include <bridge.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <iostream>
#include <vector>
#define RESOLVE(name) auto name##_fn=reinterpret_cast<decltype(&name)>(dlsym(library,#name)); if(!name##_fn) return 2
int main(int argc,char **argv) { @autoreleasepool {
    if(argc<2 || argc>4) return 2;
    bool onscreen=false;
    bool allocation_only=false;
    MTLPixelFormat format=MTLPixelFormatRGBA16Float;
    for(int i=2;i<argc;++i) {
        if(std::string(argv[i])=="--rgba8") format=MTLPixelFormatRGBA8Unorm;
        else if(std::string(argv[i])=="--onscreen") onscreen=true;
        else if(std::string(argv[i])=="--allocation-only") allocation_only=true;
        else return 2;
    }
    if(onscreen && allocation_only) return 2;
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if(!library) return 2;
    RESOLVE(initialize_bridge); RESOLVE(uninitialize_bridge); RESOLVE(get_displays);
    RESOLVE(get_default_quilt_settings_for_display); RESOLVE(get_viewcone_for_display);
    RESOLVE(instance_offscreen_window_metal); RESOLVE(create_metal_texture_with_iosurface);
    RESOLVE(instance_window_metal);
    RESOLVE(show_window);
    RESOLVE(release_metal_texture); RESOLVE(draw_interop_quilt_texture_metal);
    RESOLVE(get_offscreen_window_texture_metal);
    if(!initialize_bridge_fn("Godot Looking Glass real GPU diagnostic")) return 1;
    int count=0; bool ok=get_displays_fn(&count,nullptr);
    std::vector<unsigned long> indices(count>0 && count<32?count:0);
    ok=ok && !indices.empty() && get_displays_fn(&count,indices.data());
    float aspect=0,cone=0; int width=0,height=0,columns=0,rows=0;
    if(ok) ok=get_default_quilt_settings_for_display_fn(indices[0],&aspect,&width,&height,&columns,&rows) && get_viewcone_for_display_fn(indices[0],&cone);
    std::cout<<"devices="<<count<<" index="<<(indices.empty()?0:indices[0])<<" preset="<<width<<"x"<<height<<" grid="<<columns<<"x"<<rows<<" aspect="<<aspect<<" cone="<<cone<<std::endl;
    id<MTLDevice> device=MTLCreateSystemDefaultDevice(); WINDOW_HANDLE window=0;
    ok=ok && columns>0 && rows>0 && columns<=16 && rows<=16 && aspect>0 && device;
    if(ok) ok=onscreen?instance_window_metal_fn((__bridge void *)device,&window,indices[0]):instance_offscreen_window_metal_fn((__bridge void *)device,&window,indices[0]);
    std::cout<<"window_created="<<ok<<" kind="<<(onscreen?"onscreen":"offscreen")<<" window="<<window<<std::endl;
    if(ok && onscreen) {
        bool shown=show_window_fn(window,true);
        std::cout<<"show_window="<<shown<<std::endl;
        ok=shown;
    }
    void *native=nullptr; id<MTLTexture> texture=nil;
    if(ok) {
        auto desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:columns*64 height:rows*64 mipmapped:NO];
        desc.storageMode=MTLStorageModeShared; desc.usage=allocation_only?MTLTextureUsageShaderRead:MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
        ok=create_metal_texture_with_iosurface_fn(window,(__bridge void *)desc,&native) && native;
        if(ok) texture=(__bridge id<MTLTexture>)native;
    }
    std::cout<<"sdk_texture="<<ok<<" requested_format="<<format<<std::endl;
    if(ok && !allocation_only) {
        auto queue=[device newCommandQueue]; auto command=[queue commandBuffer];
        auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=texture;
        pass.colorAttachments[0].loadAction=MTLLoadActionClear;
        pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0.2,0.4,0.6,1);
        auto encoder=[command renderCommandEncoderWithDescriptor:pass]; [encoder endEncoding];
        [command commit]; [command waitUntilCompleted];
        ok=command.status==MTLCommandBufferStatusCompleted && draw_interop_quilt_texture_metal_fn(window,native,columns,rows,aspect,1);
        std::cout<<"gpu_producer_and_draw="<<ok<<std::endl;
        if(!onscreen) {
            void *output=nullptr;
            bool retrieved=get_offscreen_window_texture_metal_fn(window,&output) && output;
            if(retrieved) { id<MTLTexture> result=(__bridge id<MTLTexture>)output; std::cout<<"offscreen_output="<<result.width<<"x"<<result.height<<" format="<<result.pixelFormat<<std::endl; }
            else std::cout<<"offscreen_output=false"<<std::endl;
        } else if(ok) {
            std::cout<<"Holding immutable blue test image for 30 seconds; no completion-fence claim"<<std::endl;
            auto pump=reinterpret_cast<void(*)()>(dlsym(library,"SDL_PumpEvents"));
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:30];
            while([deadline timeIntervalSinceNow]>0) {
                if(pump) pump();
                // Resubmit the same immutable texture; never rewrite it while
                // Bridge may consume it. This is not animated quilt streaming.
                if(!draw_interop_quilt_texture_metal_fn(window,native,columns,rows,aspect,1)) { ok=false; break; }
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
        }
        // Output retrieval is not interpreted as a GPU consumer completion fence.
    }
    if(allocation_only) std::cout<<"allocation_only=true no_draw_attempted=true"<<std::endl;
    bool released=!native || release_metal_texture_fn(window,native);
    bool stopped=uninitialize_bridge_fn();
    std::cout<<"release="<<released<<" shutdown="<<stopped<<std::endl;
    if(stopped) dlclose(library);
    return ok && released && stopped?0:1;
} }
