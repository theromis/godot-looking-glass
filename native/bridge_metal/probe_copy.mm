// Diagnostic-only CPU fixture generation/readback around the real GPU copy.
#include "adapter.hpp"
#include <iostream>
#include <vector>
int main(int argc, char **argv) { @autoreleasepool {
    if (argc!=3 && argc!=4) return 2;
    bool two_color=argc==4 && std::string(argv[3])=="--two-color";
    if (argc==4 && !two_color) return 2;
    auto device=MTLCreateSystemDefaultDevice();
    auto queue=[device newCommandQueue];
    looking_glass::MetalAdapter adapter;
    if (!adapter.load(argv[1]) || !adapter.open(device,std::stoul(argv[2]))) return 1;
    auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:704 height:684 mipmapped:NO];
    descriptor.storageMode=MTLStorageModeShared;
    descriptor.usage=MTLTextureUsageShaderRead;
    auto source=[device newTextureWithDescriptor:descriptor];
    std::vector<unsigned char> pixels(704*684*4);
    const unsigned char color[]={51,102,153,255};
    for (size_t i=0;i<pixels.size();++i) pixels[i]=color[i%4];
    [source replaceRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:704*4];
    auto producer=[queue commandBuffer]; [producer commit];
    bool ok=adapter.submit_once(source,producer,11,6,0.5625);
    if (ok) {
        std::vector<unsigned char> copied(pixels.size());
        [adapter.direct_texture() getBytes:copied.data() bytesPerRow:704*4 fromRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0];
        ok=copied==pixels;
        std::cout<<"copied_rgba8_exact="<<ok<<std::endl;
    }
    if (ok && two_color) {
        const unsigned char red[]={230,26,26,255};
        for (size_t i=0;i<pixels.size();++i) pixels[i]=red[i%4];
        [source replaceRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:704*4];
        auto next=[queue commandBuffer]; [next commit];
        ok=adapter.append_immutable(source,next,11,6,0.5625);
        if (ok) {
            std::vector<unsigned char> copied(pixels.size());
            [adapter.direct_texture() getBytes:copied.data() bytesPerRow:704*4 fromRegion:MTLRegionMake2D(0,0,704,684) mipmapLevel:0];
            ok=copied==pixels;
            std::cout<<"second_copied_rgba8_exact="<<ok<<std::endl;
        }
    }
    if (ok) ok=adapter.show_immutable(11,6,0.5625,20,1);
    bool closed=adapter.close();
    std::cout<<"copy_show="<<ok<<" clean_close="<<closed<<std::endl;
    return ok && closed?0:1;
} }
