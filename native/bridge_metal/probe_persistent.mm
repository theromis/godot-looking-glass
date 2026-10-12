// Explicit bounded experiment. Current GL-context completion is not a public
// SDK consumer-completion contract; do not reuse this as production streaming.
#include <bridge.h>
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
    if((argc!=4 && argc!=5) || std::string(argv[3])!="--experimental-reuse") return 2;
    bool pipe_input=argc==5 && std::string(argv[4])=="--live-stdin";
    bool live_input=pipe_input || (argc==5 && std::string(argv[4]).rfind("--live-directory=",0)==0);
    std::vector<unsigned char> pipe_bytes;
    if(pipe_input) fcntl(STDIN_FILENO,F_SETFL,fcntl(STDIN_FILENO,F_GETFL)|O_NONBLOCK);
    std::string live_path=live_input && !pipe_input?std::string(argv[4]).substr(17)+"/latest.bin":"";
    bool frame_input=argc==5 && !live_input;
    unsigned last_sequence=0;
    std::vector<std::vector<unsigned char>> frames;
    if(frame_input) {
        for(int i=0;i<2;++i) {
            std::string path=std::string(argv[4])+"/frame-"+std::to_string(i)+".rgba";
            std::ifstream file(path,std::ios::binary|std::ios::ate);
            if(!file || file.tellg()!=704*684*4) return 2;
            file.seekg(0);
            frames.emplace_back(704*684*4);
            if(!file.read(reinterpret_cast<char *>(frames.back().data()),frames.back().size())) return 2;
        }
    }
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); if(!library) return 2;
    LOAD(initialize_bridge); LOAD(uninitialize_bridge); LOAD(instance_window_metal);
    LOAD(create_metal_texture_with_iosurface); LOAD(release_metal_texture);
    LOAD(draw_interop_quilt_texture_metal); LOAD(show_window);
    if(!initialize_bridge_fn("Bounded persistent Metal input experiment")) return 1;
    auto device=MTLCreateSystemDefaultDevice(); auto queue=[device newCommandQueue];
    WINDOW_HANDLE window=0;
    bool ok=instance_window_metal_fn((__bridge void *)device,&window,std::stoul(argv[2]));
    if(ok) ok=show_window_fn(window,true);
    void *native=nullptr;
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:704 height:684 mipmapped:NO];
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
    CGLContextObj observed=nullptr;
    unsigned updates=0,finishes=0;
    bool stable_context=true,exact=true;
    NSDate *started=[NSDate date];
    int previous=-1;
    while(ok && -[started timeIntervalSinceNow]<20.0) {
        int frame=int(-[started timeIntervalSinceNow]*2.0);
        if(frame!=previous) {
            std::vector<unsigned char> incoming;
            unsigned sequence=0;
            if(live_input) {
                if(pipe_input) {
                    const size_t packet_size=16+704*684*4;
                    unsigned char chunk[65536];
                    for(unsigned batch=0;batch<64;++batch) {
                        ssize_t count=read(STDIN_FILENO,chunk,sizeof(chunk));
                        if(count<0 && errno!=EAGAIN && errno!=EWOULDBLOCK) { ok=false; break; }
                        if(count<=0) break;
                        pipe_bytes.insert(pipe_bytes.end(),chunk,chunk+count);
                        while(pipe_bytes.size()>=packet_size) {
                            unsigned header[4]; std::memcpy(header,pipe_bytes.data(),16);
                            if(header[0]!=0x4c475131 || header[2]!=704 || header[3]!=684 || header[1]<=last_sequence) { ok=false; break; }
                            sequence=header[1];
                            incoming.assign(pipe_bytes.begin()+16,pipe_bytes.begin()+packet_size);
                            pipe_bytes.erase(pipe_bytes.begin(),pipe_bytes.begin()+packet_size);
                        }
                        if(!ok) break;
                    }
                } else {
                std::ifstream file(live_path,std::ios::binary|std::ios::ate);
                if(file && file.tellg()==16+704*684*4) {
                    file.seekg(0); unsigned header[4]={};
                    file.read(reinterpret_cast<char *>(header),16);
                    if(header[0]==0x4c475131 && header[2]==704 && header[3]==684 && header[1]>last_sequence) {
                        incoming.resize(704*684*4);
                        if(file.read(reinterpret_cast<char *>(incoming.data()),incoming.size())) sequence=header[1];
                    }
                }
                }
                if(!ok) break;
                if(!sequence) {
                    if(pipe_input && !pipe_bytes.empty()) { usleep(100); continue; }
                    if(pump) pump();
                    if(updates) draw_interop_quilt_texture_metal_fn(window,native,11,6,0.5625,1);
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
                    continue;
                }
            }
            // Wait observed-context work only. The SDK may use other contexts or
            // schedule future work; no general consumer safety is asserted.
            if(updates) {
                CGLContextObj current=CGLGetCurrentContext();
                if(!current || current!=observed) { ok=false; stable_context=false; break; }
                for(int i=0;i<16 && glGetError()!=GL_NO_ERROR;++i) {}
                glFinish(); ++finishes;
                if(glGetError()!=GL_NO_ERROR) { ok=false; break; }
            }
            const float blue[]={0.2f,0.4f,0.6f,1};
            const float red[]={230.0f/255,26.0f/255,26.0f/255,1};
            auto command=[queue commandBuffer];
            if(frame_input || live_input) {
                if(live_input) uploads[0]=[device newBufferWithBytes:incoming.data() length:incoming.size() options:MTLResourceStorageModeShared];
                auto blit=[command blitCommandEncoder];
                [blit copyFromBuffer:uploads[live_input?0:frame%2] sourceOffset:0 sourceBytesPerRow:704*4 sourceBytesPerImage:704*684*4 sourceSize:MTLSizeMake(704,684,1) toTexture:texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
                [blit endEncoding];
            } else {
            auto compute=[command computeCommandEncoder];
            [compute setComputePipelineState:pipeline]; [compute setTexture:texture atIndex:0];
            [compute setBytes:(frame%2?red:blue) length:sizeof(blue) atIndex:0];
            [compute dispatchThreads:MTLSizeMake(704,684,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
            [compute endEncoding];
            }
            [command commit]; [command waitUntilCompleted];
            ok=command.status==MTLCommandBufferStatusCompleted;
            // Explicit diagnostic readback proves both written patterns.
            std::vector<unsigned char> pixels(704*684*4);
            [texture getBytes:pixels.data() bytesPerRow:704*4 fromRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0];
            const unsigned char b[]={51,102,153,255},r[]={230,26,26,255};
            for(size_t i=0;i<pixels.size();++i) if(pixels[i]!=(live_input?incoming[i]:(frame_input?frames[frame%2][i]:(frame%2?r[i%4]:b[i%4])))) exact=false;
            ok=ok && exact;
            if(ok) ok=draw_interop_quilt_texture_metal_fn(window,native,11,6,0.5625,1);
            CGLContextObj current=CGLGetCurrentContext();
            if(!observed) observed=current;
            stable_context=stable_context && current && current==observed;
            ++updates; previous=frame;
            if(live_input) { last_sequence=sequence; std::cout<<"live_sequence="<<sequence<<std::endl; }
        }
        if(pump) pump();
        if(ok && updates) ok=draw_interop_quilt_texture_metal_fn(window,native,11,6,0.5625,1);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    if(CGLGetCurrentContext()) glFinish();
    bool released=!native || release_metal_texture_fn(window,native);
    bool stopped=uninitialize_bridge_fn();
    std::cout<<"persistent_updates="<<updates<<" exact_gpu_pixels="<<exact<<" observed_context_stable="<<stable_context<<" observed_gl_finishes="<<finishes<<" sdk_calls_ok="<<ok<<" release="<<released<<" shutdown="<<stopped<<std::endl;
    std::cout<<"consumer_completion_contract_verified=false experimental_reuse=true"<<std::endl;
    std::cout<<"live_godot_input="<<live_input<<" last_sequence="<<last_sequence<<std::endl;
    std::cout<<"godot_frame_input="<<frame_input<<" prerecorded="<<frame_input<<std::endl;
    if(stopped) dlclose(library);
    return ok && exact && released && stopped && updates>1?0:1;
} }
