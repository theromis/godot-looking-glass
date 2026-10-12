#include "adapter.hpp"
#include <dlfcn.h>
#include <cstdlib>
#include <iostream>
#include <vector>
#define CHECK(x) do { if (!(x)) { std::cerr << "FAIL " << #x << " line " << __LINE__ << "\n"; return 1; } } while(false)
int main(int argc,char **argv) { @autoreleasepool {
    using looking_glass::MetalAdapter;
    if (argc==3 && std::string(argv[1])=="--probe-sdk") {
        MetalAdapter probe;
        CHECK(probe.load(argv[2]));
        std::cout << "PASS installed SDK symbols and version " << probe.version() << "; no session, window or hardware output attempted\n";
        CHECK(probe.close()); return 0;
    }
    CHECK(argc==2);
    void *fixture=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL); CHECK(fixture);
    auto reset=reinterpret_cast<void(*)()>(dlsym(fixture,"fixture_reset"));
    auto count=reinterpret_cast<unsigned int(*)(unsigned int)>(dlsym(fixture,"fixture_count"));
    auto pattern_ok=reinterpret_cast<bool(*)()>(dlsym(fixture,"fixture_pattern_ok"));
    CHECK(reset && count && pattern_ok);
    id<MTLDevice> device=MTLCreateSystemDefaultDevice(); CHECK(device);
    id<MTLCommandQueue> queue=[device newCommandQueue]; CHECK(queue);
    auto desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:8 height:4 mipmapped:NO];
    desc.storageMode=MTLStorageModePrivate; desc.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> source=[device newTextureWithDescriptor:desc]; CHECK(source);
    id<MTLBuffer> upload=[device newBufferWithLength:1024 options:MTLResourceStorageModeShared]; CHECK(upload);
    auto bytes=static_cast<uint16_t *>(upload.contents);
    for (size_t y=0;y<4;++y) for (size_t x=0;x<32;++x) {
        size_t i=y*32+x; bytes[y*128+x]=i%4==3?0x3c00:(i%3==0?0x3800:0x3c00);
    }
    id<MTLCommandBuffer> producer=[queue commandBuffer];
    id<MTLBlitCommandEncoder> encoder=[producer blitCommandEncoder];
    [encoder copyFromBuffer:upload sourceOffset:0 sourceBytesPerRow:256 sourceBytesPerImage:1024 sourceSize:MTLSizeMake(8,4,1) toTexture:source destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [encoder endEncoding]; [producer commit];
    reset();
    { MetalAdapter adapter,other;
      CHECK(!adapter.load("missing-fixture-library.dylib"));
      CHECK(adapter.load(argv[1])); CHECK(adapter.version()=="2.6.3");
      CHECK(!adapter.open(device,static_cast<unsigned long>(FIRST_LOOKING_GLASS_DEVICE)));
      CHECK(adapter.open(device,7));
      CHECK(other.load(argv[1])); CHECK(!other.open(device,7));
      CHECK(!adapter.submit_once(source,[queue commandBuffer],2,2,1));
      CHECK(!adapter.submit_once(source,producer,0,2,1));
      CHECK(adapter.submit_once(source,producer,2,2,1)); CHECK(pattern_ok());
      CHECK(!adapter.submit_once(source,producer,2,2,1));
      CHECK(adapter.close()); CHECK(adapter.close());
      for (unsigned i=0;i<6;++i) CHECK(count(i)==1);
    }
    for (const char *failure:{"version","initialize","window","create","draw"}) {
        reset(); setenv("LG_FIXTURE_FAIL",failure,1);
        MetalAdapter adapter;
        if (std::string(failure)=="version") CHECK(!adapter.load(argv[1]));
        else {
            CHECK(adapter.load(argv[1]));
            if (std::string(failure)=="initialize" || std::string(failure)=="window") CHECK(!adapter.open(device,7));
            else { CHECK(adapter.open(device,7)); CHECK(!adapter.submit_once(source,producer,2,2,1)); }
        }
        CHECK(adapter.close());
        CHECK(count(5)==(std::string(failure)=="version" || std::string(failure)=="initialize"?0:1));
        CHECK(count(4)==(std::string(failure)=="draw"?1:0));
        unsetenv("LG_FIXTURE_FAIL");
    }
    for (const char *failure:{"release","shutdown"}) {
        reset();
        MetalAdapter adapter,other;
        CHECK(adapter.load(argv[1])); CHECK(adapter.open(device,7));
        CHECK(adapter.submit_once(source,producer,2,2,1));
        setenv("LG_FIXTURE_FAIL",failure,1);
        CHECK(!adapter.close());
        CHECK(other.load(argv[1])); CHECK(!other.open(device,7));
        unsetenv("LG_FIXTURE_FAIL");
        CHECK(adapter.close()); CHECK(adapter.close());
        CHECK(count(4)==(std::string(failure)=="release"?2:1));
        CHECK(count(5)==(std::string(failure)=="shutdown"?2:1));
    }
    reset();
    setenv("LG_FIXTURE_ACCEPT_QUILT","1",1);
    auto rgba_desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:8 height:4 mipmapped:NO];
    rgba_desc.storageMode=MTLStorageModePrivate;
    rgba_desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
    auto rgba=[device newTextureWithDescriptor:rgba_desc]; CHECK(rgba);
    auto read=reinterpret_cast<bool(*)(void*,unsigned long)>(dlsym(fixture,"fixture_copy_output")); CHECK(read);
    {
        MetalAdapter sequence;
        CHECK(sequence.load(argv[1])); CHECK(sequence.open(device,7));
        for (int frame=0;frame<16;++frame) {
            auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture=rgba;
            pass.colorAttachments[0].loadAction=MTLLoadActionClear;
            pass.colorAttachments[0].storeAction=MTLStoreActionStore;
            pass.colorAttachments[0].clearColor=MTLClearColorMake(frame/15.0,0,1,1);
            auto command=[queue commandBuffer];
            auto render=[command renderCommandEncoderWithDescriptor:pass]; [render endEncoding]; [command commit];
            CHECK(sequence.append_immutable(rgba,command,2,2,1));
            unsigned char copied[128]; CHECK(read(copied,sizeof(copied)));
            for (int i=0;i<128;++i) CHECK(copied[i]==(i%4==0?frame*17:(i%4==1?0:255)));
        }
        CHECK(!sequence.append_immutable(rgba,producer,2,2,1));
        setenv("LG_FIXTURE_FAIL","release",1); CHECK(!sequence.close());
        unsetenv("LG_FIXTURE_FAIL"); CHECK(sequence.close()); CHECK(sequence.close());
        CHECK(count(2)==16 && count(3)==16 && count(4)==17 && count(5)==1);
    }
    unsetenv("LG_FIXTURE_ACCEPT_QUILT");
    std::cout << "PASS immutable RGBA8 sequence: 16 distinct GPU copies exact, frame-budget rejection, failed-release retry, no output overwrite\n";
    dlclose(fixture);
    std::cout << "PASS real Metal GPU copy into fixture IOSurface, exact RGBA16Float pixels, producer fence, SDK errors, exclusive session, one-shot guard, failed-teardown retry and idempotent teardown\n";
    return 0;
} }
