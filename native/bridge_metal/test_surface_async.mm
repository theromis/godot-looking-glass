#import <Foundation/Foundation.h>
#include "surface_publisher.hpp"
#include <unistd.h>
#include <iostream>
int main() { @autoreleasepool {
    std::string name="/lga"+std::to_string(getpid());
    auto device=MTLCreateSystemDefaultDevice(); auto queue=[device newCommandQueue];
    SurfaceMailbox worker;
    SurfacePortReceiver receiver;
    SurfacePublisher publisher;
    bool ok=device && queue && worker.open(name,704,684,true) && receiver.open(name) && publisher.open(name,704,684,device);
    if(!ok) return 1;
    IOSurfaceRef imported=nullptr;
    ok=receiver.receive(imported) && imported!=nullptr;
    if(imported) CFRelease(imported);
    std::vector<unsigned char> expected(704*684*4);
    for(size_t i=0;i<expected.size();++i) expected[i]=static_cast<unsigned char>((i*37+i/2816)%256);
    for(uint32_t sequence=1;ok && sequence<=3;++sequence) {
        auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:704 height:684 mipmapped:NO];
        descriptor.storageMode=MTLStorageModeShared;
        auto source=[device newTextureWithDescriptor:descriptor];
        [source replaceRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0 withBytes:expected.data() bytesPerRow:704*4];
        ok=publisher.begin_publish(sequence,source,queue) && !publisher.ready() && !publisher.begin_publish(sequence+1,source,queue);
        ok=ok && publisher.read_pixels().empty(); // Reject readback before polling completion.
        source=nil; // Publisher/command must retain GPU resources.
        int status=0;
        for(int attempt=0;ok && status==0 && attempt<2000;++attempt) { status=publisher.poll_publish(); if(status==0) usleep(1000); }
        uint32_t surface=0,checksum=0,received=0;
        ok=ok && status==1 && !publisher.ready() && worker.latest(sequence-1,surface,checksum,received) && received==sequence && publisher.read_pixels()==expected && worker.acknowledge(sequence) && publisher.ready();
    }
    // Close with a copy in flight: wait before destroying the shared destination.
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:704 height:684 mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared;
    auto source=[device newTextureWithDescriptor:descriptor];
    ok=ok && publisher.begin_publish(4,source,queue);
    publisher.close();
    ok=ok && publisher.poll_publish()==-1 && !publisher.ready();
    receiver.close(); worker.close();
    std::cout<<(ok?"PASS async surface copy, bytes, backpressure and close":"FAIL async surface copy")<<std::endl;
    return ok?0:1;
} }
