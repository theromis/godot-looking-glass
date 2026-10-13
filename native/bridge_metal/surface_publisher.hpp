#pragma once
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#include "surface_mailbox.hpp"
#include "surface_port.hpp"
inline uint32_t surface_checksum(const std::vector<unsigned char> &pixels) {
    uint32_t hash=2166136261u;
    for(auto value:pixels) hash=(hash^value)*16777619u;
    return hash;
}
class SurfacePublisher {
    SurfaceMailbox mailbox_;
    IOSurfaceRef surface_=nullptr;
    id<MTLTexture> texture_=nil;
    unsigned width_=0,height_=0;
    id<MTLCommandBuffer> pending_=nil;
    id<MTLTexture> pending_source_=nil;
    uint32_t pending_sequence_=0;
public:
    ~SurfacePublisher() { close(); }
    bool open(const std::string &name,unsigned width,unsigned height,id<MTLDevice> device) {
        if(surface_ || !device || !mailbox_.open(name,width,height,false)) return false;
        width_=width; height_=height;
        size_t pitch=(width*4+255)&~size_t(255);
        NSDictionary *properties=@{(id)kIOSurfaceWidth:@(width),(id)kIOSurfaceHeight:@(height),(id)kIOSurfaceBytesPerElement:@4,(id)kIOSurfaceBytesPerRow:@(pitch),(id)kIOSurfaceAllocSize:@(pitch*height),(id)kIOSurfacePixelFormat:@(0x52474241)};
        surface_=IOSurfaceCreate((__bridge CFDictionaryRef)properties);
        if(!surface_) return false;
        auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
        descriptor.storageMode=MTLStorageModeShared; descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
        texture_=[device newTextureWithDescriptor:descriptor iosurface:surface_ plane:0];
        return texture_!=nil && send_surface_port(name,surface_);
    }
    bool ready() { return texture_ && !pending_ && mailbox_.ready(); }
    bool publish(uint32_t sequence,id<MTLTexture> source,id<MTLCommandQueue> queue,bool verify) {
        if(!ready() || !source || source.device!=texture_.device || queue.device!=source.device || source.width!=width_ || source.height!=height_ || source.pixelFormat!=MTLPixelFormatRGBA8Unorm || source.textureType!=MTLTextureType2D || source.sampleCount!=1 || source.arrayLength!=1) return false;
        auto command=[queue commandBuffer]; auto blit=[command blitCommandEncoder];
        [blit copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width_,height_,1) toTexture:texture_ destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding]; [command commit]; [command waitUntilCompleted];
        if(command.status!=MTLCommandBufferStatusCompleted) return false;
        uint32_t checksum=0;
        if(verify) {
            std::vector<unsigned char> pixels(static_cast<size_t>(width_)*height_*4);
            [texture_ getBytes:pixels.data() bytesPerRow:width_*4 fromRegion:MTLRegionMake2D(0,0,width_,height_) mipmapLevel:0];
            checksum=surface_checksum(pixels);
        }
        return mailbox_.publish(sequence,IOSurfaceGetID(surface_),checksum);
    }
    // Experimental direct producer target. The caller must not write again until
    // ready() after worker ACK, and must release imports before close().
    id<MTLTexture> direct_texture() const { return texture_; }
    bool publish_rendered(uint32_t sequence,id<MTLCommandQueue> queue,bool verify) {
        if(!sequence || !ready() || !queue || queue.device!=texture_.device) return false;
        // Fence previously committed producer work on the same queue; no blit.
        auto fence=[queue commandBuffer];
        if(!fence) return false;
        [fence commit]; [fence waitUntilCompleted];
        if(fence.status!=MTLCommandBufferStatusCompleted) return false;
        uint32_t checksum=verify?surface_checksum(read_pixels()):0;
        return mailbox_.publish(sequence,IOSurfaceGetID(surface_),checksum);
    }
    // Main-thread polling: do not publish a sequence before GPU completion.
    bool begin_publish(uint32_t sequence,id<MTLTexture> source,id<MTLCommandQueue> queue) {
        if(!sequence || !ready() || !source || !queue || source.device!=texture_.device || queue.device!=source.device || source.width!=width_ || source.height!=height_ || source.pixelFormat!=MTLPixelFormatRGBA8Unorm || source.textureType!=MTLTextureType2D || source.sampleCount!=1 || source.arrayLength!=1) return false;
        auto command=[queue commandBuffer]; auto blit=[command blitCommandEncoder];
        if(!command || !blit) return false;
        [blit copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width_,height_,1) toTexture:texture_ destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding];
        pending_source_=source;
        pending_sequence_=sequence;
        pending_=command;
        [command commit];
        return true;
    }
    // 0 pending, 1 completed and published, -1 failed. No callback touches Godot.
    int poll_publish() {
        if(!pending_) return -1;
        if(pending_.status<MTLCommandBufferStatusCompleted) return 0;
        bool ok=pending_.status==MTLCommandBufferStatusCompleted && mailbox_.publish(pending_sequence_,IOSurfaceGetID(surface_),0);
        pending_=nil; pending_source_=nil; pending_sequence_=0;
        return ok?1:-1;
    }
    // Diagnostic snapshot only, after publish has waited for the source GPU copy.
    std::vector<unsigned char> read_pixels() {
        if(!texture_ || pending_) return {};
        std::vector<unsigned char> pixels(static_cast<size_t>(width_)*height_*4);
        [texture_ getBytes:pixels.data() bytesPerRow:width_*4 fromRegion:MTLRegionMake2D(0,0,width_,height_) mipmapLevel:0];
        return pixels;
    }
    void close() {
        // Forced shutdown must not destroy resources still used by the GPU.
        if(pending_) [pending_ waitUntilCompleted];
        pending_=nil; pending_source_=nil; pending_sequence_=0;
        texture_=nil;
        if(surface_) { CFRelease(surface_); surface_=nullptr; }
        mailbox_.close();
    }
};
