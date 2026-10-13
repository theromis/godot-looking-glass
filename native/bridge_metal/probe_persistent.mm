#include <cmath>
#include <chrono>
#include <algorithm>
// Explicit bounded experiment. Current GL-context completion is not a public
// SDK consumer-completion contract; do not reuse this as production streaming.
#include <bridge.h>
#include "shared_frame.hpp"
#include "surface_publisher.hpp"
#import <Metal/Metal.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl3.h>
#include <dlfcn.h>
#include <iostream>
#include <vector>
#include <fstream>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <cerrno>
#define LOAD(name) auto name##_fn=reinterpret_cast<decltype(&name)>(dlsym(library,#name)); if(!name##_fn) return 2
int main(int argc,char **argv) { @autoreleasepool {
    if((argc<4 || argc>10) || std::string(argv[3])!="--experimental-reuse") return 2;
    bool large=false, verify_surface=false, uncapped=false, control_stdin=false;
    double duration=20.0;
    for(int arg=5;arg<argc;++arg) {
        if(std::string(argv[arg])=="--large") large=true;
        else if(std::string(argv[arg])=="--verify") verify_surface=true;
        else if(std::string(argv[arg])=="--uncapped") uncapped=true;
        else if(std::string(argv[arg])=="--control-stdin") control_stdin=true;
        else if(std::string(argv[arg]).rfind("--duration=",0)==0) { duration=std::stod(std::string(argv[arg]).substr(11)); if(!std::isfinite(duration) || duration<20 || duration>600) return 2; }
        else return 2;
    }
    const unsigned width=large?4092:704,height=large?4092:684;
    const size_t pitch=(width*4+255)&~size_t(255);
    bool pipe_input=argc>=5 && std::string(argv[4])=="--live-stdin";
    bool surface_input=argc>=5 && std::string(argv[4]).rfind("--live-surface=",0)==0;
    SurfaceMailbox surface_mailbox;
    SurfacePortReceiver surface_receiver;
    if(surface_input && !surface_mailbox.open(std::string(argv[4]).substr(15),width,height,true)) return 2;
    if(surface_input && !surface_receiver.open(std::string(argv[4]).substr(15))) return 2;
    if(surface_input) std::cout<<"SURFACE ready"<<std::endl;
    bool shared_input=argc>=5 && std::string(argv[4]).rfind("--live-shm=",0)==0;
    SharedFrame mailbox;
    if(shared_input && !mailbox.open(std::string(argv[4]).substr(11),width,height,true)) return 2;
    if(shared_input) std::cout<<"SHM ready"<<std::endl;
    bool live_input=surface_input || shared_input || pipe_input || (argc>=5 && std::string(argv[4]).rfind("--live-directory=",0)==0);
    std::vector<unsigned char> pipe_bytes;
    if(pipe_input) fcntl(STDIN_FILENO,F_SETFL,fcntl(STDIN_FILENO,F_GETFL)|O_NONBLOCK);
    std::string live_path=live_input && !pipe_input && !shared_input && !surface_input?std::string(argv[4]).substr(17)+"/latest.bin":"";
    bool frame_input=argc>=5 && !live_input;
    unsigned last_sequence=0;
    std::vector<std::vector<unsigned char>> frames;
    if(frame_input) {
        for(int i=0;i<2;++i) {
            std::string path=std::string(argv[4])+"/frame-"+std::to_string(i)+".rgba";
            std::ifstream file(path,std::ios::binary|std::ios::ate);
            if(!file || file.tellg()!=width*height*4) return 2;
            file.seekg(0);
            frames.emplace_back(width*height*4);
            if(!file.read(reinterpret_cast<char *>(frames.back().data()),frames.back().size())) return 2;
        }
    }
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if(!library) return 2;
    LOAD(get_displays);
    LOAD(initialize_bridge); LOAD(uninitialize_bridge); LOAD(instance_window_metal);
    LOAD(create_metal_texture_with_iosurface); LOAD(release_metal_texture);
    LOAD(draw_interop_quilt_texture_metal); LOAD(show_window);
    if(!initialize_bridge_fn("Bounded persistent Metal input experiment")) return 1;
    int count=0;
    bool listed=get_displays_fn(&count,nullptr);
    std::vector<unsigned long> displays(count>0 && count<=32?32:0);
    unsigned long requested=std::stoul(argv[2]);
    bool available=listed && !displays.empty() && get_displays_fn(&count,displays.data()) && count>0 && count<=32;
    if(available) displays.resize(count);
    if(!available || std::find(displays.begin(),displays.end(),requested)==displays.end()) {
        std::cerr<<"DISPLAY unavailable"<<std::endl;
        if(uninitialize_bridge_fn()) dlclose(library);
        return 1;
    }
    auto device=MTLCreateSystemDefaultDevice(); auto queue=[device newCommandQueue];
    if(!device || !queue) {
        std::cerr<<"METAL device unavailable"<<std::endl;
        if(uninitialize_bridge_fn()) dlclose(library);
        return 1;
    }
    WINDOW_HANDLE window=0;
    bool ok=instance_window_metal_fn((__bridge void *)device,&window,std::stoul(argv[2]));
    if(ok) ok=show_window_fn(window,true);
    void *native=nullptr;
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared;
    descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    if(ok) ok=create_metal_texture_with_iosurface_fn(window,(__bridge void *)descriptor,&native) && native;
    id<MTLTexture> texture=(__bridge id<MTLTexture>)native;
    NSError *error=nil;
    NSString *code=@"#include <metal_stdlib>\nusing namespace metal;\nkernel void fill(texture2d<float,access::write> dst [[texture(0)]], constant float4 &color [[buffer(0)]], uint2 p [[thread_position_in_grid]]) { if(p.x<dst.get_width() && p.y<dst.get_height()) dst.write(color,p); }";
    auto shader=[device newLibraryWithSource:code options:nil error:&error];
    auto pipeline=shader?[device newComputePipelineStateWithFunction:[shader newFunctionWithName:@"fill"] error:&error]:nil;
    ok=ok && pipeline && texture.device==device;
    id<MTLBuffer> uploads[2]={nil,nil};
    if(frame_input) for(int i=0;i<2;++i) {
        uploads[i]=[device newBufferWithBytes:frames[i].data() length:frames[i].size() options:MTLResourceStorageModeShared];
        ok=ok && uploads[i];
    }
    auto pump=reinterpret_cast<void(*)()>(dlsym(library,"SDL_PumpEvents"));
    IOSurfaceRef imported_surface=nullptr;
    id<MTLTexture> imported_texture=nil;
    uint32_t imported_id=0;
    CGLContextObj observed=nullptr;
    unsigned updates=0,finishes=0;
    bool stable_context=true,exact=true;
    if(control_stdin) fcntl(STDIN_FILENO,F_SETFL,fcntl(STDIN_FILENO,F_GETFL)|O_NONBLOCK);
    if(surface_input && ok) std::cout<<"SURFACE sdk_ready"<<std::endl;
    NSDate *started=[NSDate date];
    int previous=-1;
    double first_update=-1,last_update=0;
    double finish_ms=0,copy_ms=0,draw_ms=0;
    auto clock_now=[] { return std::chrono::steady_clock::now(); };
    auto elapsed_ms=[&](auto begin) { return std::chrono::duration<double,std::milli>(clock_now()-begin).count(); };
    while(ok && -[started timeIntervalSinceNow]<duration) {
        // Drain temporary Cocoa/Metal objects while persistent textures remain
        // strongly owned outside the iteration. This includes continue paths.
        @autoreleasepool {
        if(control_stdin) {
            char bytes[32]; ssize_t count=read(STDIN_FILENO,bytes,sizeof(bytes));
            if(count==0) break;
            if(count>0 && std::memchr(bytes,'q',count)) break;
            if(count<0 && errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR) { ok=false; break; }
        }
        int frame=int(-[started timeIntervalSinceNow]*2.0);
        if(uncapped || frame!=previous) {
            std::vector<unsigned char> incoming;
            unsigned sequence=0, surface_id=0, expected_checksum=0;
            if(live_input) {
                if(surface_input) {
                    if(!surface_mailbox.latest(last_sequence,surface_id,expected_checksum,sequence)) ok=false;
                    IOSurfaceRef received=nullptr;
                    if(!surface_receiver.receive(received)) { std::cerr<<"SURFACE port receive_failed"<<std::endl; ok=false; break; }
                    if(received) {
                        imported_texture=nil;
                        if(imported_surface) CFRelease(imported_surface);
                        imported_surface=received;
                        if(IOSurfaceGetWidth(imported_surface)!=width || IOSurfaceGetHeight(imported_surface)!=height) { ok=false; break; }
                        auto shared_descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
                        shared_descriptor.storageMode=MTLStorageModeShared; shared_descriptor.usage=MTLTextureUsageShaderRead;
                        imported_texture=[device newTextureWithDescriptor:shared_descriptor iosurface:imported_surface plane:0];
                        if(!imported_texture) { std::cerr<<"SURFACE import Metal_texture_failed"<<std::endl; ok=false; break; }
                        imported_id=IOSurfaceGetID(imported_surface);
                    }
                    if(sequence && (!imported_texture || surface_id!=imported_id)) { std::cerr<<"SURFACE import descriptor_mismatch"<<std::endl; ok=false; break; }
                } else if(shared_input) {
                    if(!mailbox.latest(last_sequence,incoming,sequence)) ok=false;
                } else if(pipe_input) {
                    const size_t packet_size=16+width*height*4;
                    unsigned char chunk[65536];
                    for(unsigned batch=0;batch<64;++batch) {
                        ssize_t count=read(STDIN_FILENO,chunk,sizeof(chunk));
                        if(count<0 && errno!=EAGAIN && errno!=EWOULDBLOCK) { ok=false; break; }
                        if(count<=0) break;
                        pipe_bytes.insert(pipe_bytes.end(),chunk,chunk+count);
                        while(pipe_bytes.size()>=packet_size) {
                            unsigned header[4]; std::memcpy(header,pipe_bytes.data(),16);
                            if(header[0]!=0x4c475131 || header[2]!=width || header[3]!=height || header[1]<=last_sequence) { ok=false; break; }
                            sequence=header[1];
                            incoming.assign(pipe_bytes.begin()+16,pipe_bytes.begin()+packet_size);
                            pipe_bytes.erase(pipe_bytes.begin(),pipe_bytes.begin()+packet_size);
                        }
                        if(!ok) break;
                    }
                } else {
                std::ifstream file(live_path,std::ios::binary|std::ios::ate);
                if(file && file.tellg()==16+width*height*4) {
                    file.seekg(0); unsigned header[4]={};
                    file.read(reinterpret_cast<char *>(header),16);
                    if(header[0]==0x4c475131 && header[2]==width && header[3]==height && header[1]>last_sequence) {
                        incoming.resize(width*height*4);
                        if(file.read(reinterpret_cast<char *>(incoming.data()),incoming.size())) sequence=header[1];
                    }
                }
                }
                if(!ok) break;
                if(!sequence) {
                    if(pipe_input && !pipe_bytes.empty()) { usleep(100); continue; }
                    if(pump) pump();
                    if(updates) draw_interop_quilt_texture_metal_fn(window,native,11,6,0.5625,1);
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:(uncapped?0.001:0.02)]];
                    continue;
                }
            }
            // Wait observed-context work only. The SDK may use other contexts or
            // schedule future work; no general consumer safety is asserted.
            if(updates) {
                CGLContextObj current=CGLGetCurrentContext();
                if(!current || current!=observed) { ok=false; stable_context=false; break; }
                for(int i=0;i<16 && glGetError()!=GL_NO_ERROR;++i) {}
                auto finish_started=clock_now();
                glFinish(); ++finishes; finish_ms+=elapsed_ms(finish_started);
                if(glGetError()!=GL_NO_ERROR) { ok=false; break; }
            }
            const float blue[]={0.2f,0.4f,0.6f,1};
            const float red[]={230.0f/255,26.0f/255,26.0f/255,1};
            auto copy_started=clock_now();
            auto command=[queue commandBuffer];
            if(surface_input) {
                auto blit=[command blitCommandEncoder];
                [blit copyFromTexture:imported_texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toTexture:texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
                [blit endEncoding];
            } else if(frame_input || live_input) {
                if(live_input) {
                    uploads[0]=[device newBufferWithLength:pitch*height options:MTLResourceStorageModeShared];
                    if(!uploads[0]) { ok=false; break; }
                    for(unsigned y=0;y<height;++y) std::memcpy(static_cast<unsigned char *>(uploads[0].contents)+y*pitch,incoming.data()+y*width*4,width*4);
                }
                auto blit=[command blitCommandEncoder];
                [blit copyFromBuffer:uploads[live_input?0:frame%2] sourceOffset:0 sourceBytesPerRow:pitch sourceBytesPerImage:pitch*height sourceSize:MTLSizeMake(width,height,1) toTexture:texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
                [blit endEncoding];
            } else {
            auto compute=[command computeCommandEncoder];
            [compute setComputePipelineState:pipeline]; [compute setTexture:texture atIndex:0];
            [compute setBytes:(frame%2?red:blue) length:sizeof(blue) atIndex:0];
            [compute dispatchThreads:MTLSizeMake(width,height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
            [compute endEncoding];
            }
            [command commit]; [command waitUntilCompleted];
            copy_ms+=elapsed_ms(copy_started);
            ok=command.status==MTLCommandBufferStatusCompleted;
            if(!surface_input || verify_surface) {
            // Explicit diagnostic readback proves both written patterns.
            std::vector<unsigned char> pixels(width*height*4);
            [texture getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
            const unsigned char b[]={51,102,153,255},r[]={230,26,26,255};
            if(surface_input) { exact=exact && surface_checksum(pixels)==expected_checksum; }
            else for(size_t i=0;i<pixels.size();++i) if(pixels[i]!=(live_input?incoming[i]:(frame_input?frames[frame%2][i]:(frame%2?r[i%4]:b[i%4])))) exact=false;
            }
            ok=ok && exact;
            if(surface_input && ok) ok=surface_mailbox.acknowledge(sequence);
            auto draw_started=clock_now();
            if(ok) ok=draw_interop_quilt_texture_metal_fn(window,native,11,6,0.5625,1);
            draw_ms+=elapsed_ms(draw_started);
            CGLContextObj current=CGLGetCurrentContext();
            if(!observed) observed=current;
            stable_context=stable_context && current && current==observed;
            ++updates; previous=frame;
            last_update=-[started timeIntervalSinceNow]; if(first_update<0) first_update=last_update;
            if(live_input) { last_sequence=sequence; std::cout<<"live_sequence="<<sequence<<std::endl; }
        }
        if(pump) pump();
        if(ok && updates) ok=draw_interop_quilt_texture_metal_fn(window,native,11,6,0.5625,1);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:(uncapped?0.001:0.02)]];
        } // Per-iteration autorelease pool.
    }
    std::cout<<"worker_mean_finish_ms="<<(finishes?finish_ms/finishes:0)<<" worker_mean_copy_wait_ms="<<(updates?copy_ms/updates:0)<<" worker_mean_new_frame_draw_ms="<<(updates?draw_ms/updates:0)<<std::endl;
    std::cout<<"worker_update_span_seconds="<<(last_update-first_update)<<" worker_update_rate_hz="<<((updates>1 && last_update>first_update)?(updates-1)/(last_update-first_update):0)<<std::endl;
    if(CGLGetCurrentContext()) glFinish();
    imported_texture=nil;
    if(imported_surface) CFRelease(imported_surface);
    bool released=!native || release_metal_texture_fn(window,native);
    bool stopped=uninitialize_bridge_fn();
    std::cout<<"persistent_updates="<<updates<<" exact_gpu_pixels="<<(surface_input?-1:int(exact))<<" observed_context_stable="<<stable_context<<" observed_gl_finishes="<<finishes<<" sdk_calls_ok="<<ok<<" release="<<released<<" shutdown="<<stopped<<std::endl;
    std::cout<<"consumer_completion_contract_verified=false experimental_reuse=true"<<std::endl;
    std::cout<<"gpu_surface_input="<<surface_input<<" diagnostic_readback="<<(surface_input?verify_surface:true)<<" checksums_match="<<(surface_input && verify_surface?int(exact):-1)<<std::endl;
    std::cout<<"live_godot_input="<<live_input<<" last_sequence="<<last_sequence<<std::endl;
    std::cout<<"godot_frame_input="<<frame_input<<" prerecorded="<<frame_input<<std::endl;
    if(stopped) dlclose(library);
    return ok && exact && released && stopped && (updates>1 || control_stdin)?0:1;
} }
