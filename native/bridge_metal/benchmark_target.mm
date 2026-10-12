// Own synthetic output-boundary microbenchmark, not a Godot scene benchmark.
#include "adapter.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>
struct Stats { double median, p10, p90; };
static Stats stats(std::vector<double> values) {
    std::sort(values.begin(),values.end());
    return {values[values.size()/2],values[values.size()/10],values[values.size()*9/10]};
}
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=5) return 2;
    unsigned long index=std::stoul(argv[2]),width=std::stoul(argv[3]),height=std::stoul(argv[4]);
    if(!width || !height || width>8192 || height>8192) return 2;
    auto device=MTLCreateSystemDefaultDevice(); auto queue=[device newCommandQueue];
    looking_glass::MetalAdapter adapter;
    if(!adapter.load(argv[1]) || !adapter.open(device,index) || !adapter.prepare_direct_rgba8(width,height)) { std::cerr<<adapter.error()<<"\n"; return 1; }
    auto target=adapter.direct_texture();
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    descriptor.storageMode=MTLStorageModePrivate;
    descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    auto intermediate=[device newTextureWithDescriptor:descriptor];
    NSError *error=nil;
    auto library=[device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nkernel void fill(texture2d<float,access::write> t [[texture(0)]], uint2 p [[thread_position_in_grid]]) { if(p.x<t.get_width() && p.y<t.get_height()) t.write(float4(0.2,0.4,0.6,1),p); }" options:nil error:&error];
    auto pipeline=library?[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"fill"] error:&error]:nil;
    if(!pipeline || !intermediate || !queue) return 1;
    std::vector<double> direct,copied;
    // Alternating order limits systematic order bias. No SDK draw is submitted:
    // the target has no Bridge consumer during repeated producer overwrites.
    for(int round=0;round<60;++round) {
        for(int position=0;position<2;++position) { @autoreleasepool {
            bool copy=((round+position)%2)!=0;
            auto command=[queue commandBuffer];
            auto compute=[command computeCommandEncoder];
            [compute setComputePipelineState:pipeline]; [compute setTexture:copy?intermediate:target atIndex:0];
            [compute dispatchThreads:MTLSizeMake(width,height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
            [compute endEncoding];
            if(copy) {
                auto blit=[command blitCommandEncoder];
                [blit copyFromTexture:intermediate sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toTexture:target destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
                [blit endEncoding];
            }
            [command commit]; [command waitUntilCompleted];
            double elapsed=(command.GPUEndTime-command.GPUStartTime)*1000;
            if(command.status!=MTLCommandBufferStatusCompleted || !std::isfinite(elapsed) || elapsed<=0) return 1;
            if(round>=10) (copy?copied:direct).push_back(elapsed);
        } }
    }
    // Diagnostic verification after timings; no timed CPU pixel readback.
    std::vector<unsigned char> pixels(width*height*4);
    [target getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
    const unsigned char expected[4]={51,102,153,255};
    for(size_t i=0;i<pixels.size();++i) if(pixels[i]!=expected[i%4]) return 1;
    auto a=stats(direct),b=stats(copied);
    bool closed=adapter.close();
    std::cout<<"RESULT {\"width\":"<<width<<",\"height\":"<<height<<",\"samples_per_mode\":50,\"warmup_pairs\":10,\"direct_gpu_ms\":{\"median\":"<<a.median<<",\"p10\":"<<a.p10<<",\"p90\":"<<a.p90<<"},\"compute_plus_blit_gpu_ms\":{\"median\":"<<b.median<<",\"p10\":"<<b.p10<<",\"p90\":"<<b.p90<<"},\"exact_final_bytes\":true,\"sdk_draw_submitted\":false,\"shutdown\":"<<(closed?"true":"false")<<"}"<<std::endl;
    return closed?0:1;
} }
