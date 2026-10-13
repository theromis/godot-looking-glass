#import <Foundation/Foundation.h>
#include "surface_publisher.hpp"
#include <iostream>
#include <unistd.h>
// GPU writes directly into the transported surface; no producer blit encoder.
int main() { @autoreleasepool {
    auto device=MTLCreateSystemDefaultDevice(); auto queue=[device newCommandQueue];
    std::string name="/lgd"+std::to_string(getpid());
    SurfaceMailbox worker; SurfacePortReceiver receiver; SurfacePublisher publisher;
    bool ok=device && queue && worker.open(name,704,684,true) && receiver.open(name) && publisher.open(name,704,684,device);
    IOSurfaceRef surface=nullptr;
    ok=ok && receiver.receive(surface) && surface;
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:704 height:684 mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared; descriptor.usage=MTLTextureUsageShaderRead;
    auto imported=surface?[device newTextureWithDescriptor:descriptor iosurface:surface plane:0]:nil;
    NSError *error=nil;
    auto library=[device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\nkernel void fill(texture2d<float,access::write> dst [[texture(0)]], constant uint &phase [[buffer(0)]], uint2 p [[thread_position_in_grid]]) { if(p.x>=dst.get_width() || p.y>=dst.get_height()) return; dst.write(float4(float((p.x+phase)%256)/255.0, float((p.y+phase*3)%256)/255.0, float(phase)/255.0, 1.0),p); }" options:nil error:&error];
    auto pipeline=library?[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"fill"] error:&error]:nil;
    ok=ok && imported && pipeline;
    for(uint32_t phase=1;ok && phase<=3;++phase) {
        ok=publisher.ready();
        auto command=[queue commandBuffer]; auto compute=[command computeCommandEncoder];
        [compute setComputePipelineState:pipeline]; [compute setTexture:publisher.direct_texture() atIndex:0];
        [compute setBytes:&phase length:sizeof(phase) atIndex:0];
        [compute dispatchThreadgroups:MTLSizeMake(88,86,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
        [compute endEncoding]; [command commit];
        ok=ok && publisher.publish_rendered(phase,queue,true) && !publisher.ready() && !publisher.publish_rendered(phase+1,queue,false);
        uint32_t id=0,checksum=0,sequence=0;
        ok=ok && worker.latest(phase-1,id,checksum,sequence) && sequence==phase && id==IOSurfaceGetID(surface);
        std::vector<unsigned char> actual(704*684*4),expected(actual.size());
        [imported getBytes:actual.data() bytesPerRow:704*4 fromRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0];
        for(unsigned y=0;y<684;++y) for(unsigned x=0;x<704;++x) {
            size_t offset=(y*704+x)*4;
            expected[offset]=(x+phase)%256; expected[offset+1]=(y+phase*3)%256;
            expected[offset+2]=phase; expected[offset+3]=255;
        }
        ok=ok && actual==expected && checksum==surface_checksum(expected) && worker.acknowledge(phase) && publisher.ready();
    }
    imported=nil;
    if(surface) CFRelease(surface);
    publisher.close(); receiver.close(); worker.close();
    std::cout<<(ok?"PASS direct surface GPU writes, imported bytes and ACK backpressure":"FAIL direct surface")<<std::endl;
    if(error) std::cerr<<error.localizedDescription.UTF8String<<std::endl;
    return ok?0:1;
} }
