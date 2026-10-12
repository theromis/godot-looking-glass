#pragma once
#import <Metal/Metal.h>
#include <bridge.h>
#include <string>
namespace looking_glass {
// One-shot diagnostic boundary. Caller supplies an actual Metal producer fence.
// Not a Vulkan importer or a complete Godot GDExtension.
class MetalAdapter {
public:
    ~MetalAdapter();
    MetalAdapter() = default;
    MetalAdapter(const MetalAdapter &) = delete;
    MetalAdapter &operator=(const MetalAdapter &) = delete;
    bool load(const std::string &path);
    bool open(id<MTLDevice> device, unsigned long calibrated_display_index);
    bool submit_once(id<MTLTexture> source, id<MTLCommandBuffer> producer,
        unsigned long columns, unsigned long rows, float aspect, float zoom = 1.0f);
    bool close();
    bool show_immutable(unsigned long columns, unsigned long rows, float aspect, double seconds);
    bool append_immutable(id<MTLTexture> source, id<MTLCommandBuffer> producer,
        unsigned long columns, unsigned long rows, float aspect);
    const std::string &error() const { return error_; }
    const std::string &version() const { return version_; }
private:
    void *library_ = nullptr;
    decltype(&initialize_bridge) initialize_ = nullptr;
    decltype(&uninitialize_bridge) shutdown_ = nullptr;
    decltype(&get_bridge_version) version_fn_ = nullptr;
    decltype(&instance_window_metal) window_fn_ = nullptr;
    decltype(&create_metal_texture_with_iosurface) create_ = nullptr;
    decltype(&release_metal_texture) release_ = nullptr;
    decltype(&draw_interop_quilt_texture_metal) draw_ = nullptr;
    WINDOW_HANDLE window_ = 0;
    id<MTLDevice> device_ = nil;
    id<MTLCommandQueue> queue_ = nil;
    id<MTLTexture> output_ = nil;
    NSMutableArray<id<MTLTexture>> *previous_outputs_ = nil;
    NSUInteger previous_released_ = 0;
    uint64_t sequence_bytes_ = 0;
    bool initialized_ = false;
    bool owns_session_ = false;
    bool submitted_ = false;
    bool sdk_owns_output_ = false;
    std::string error_, version_;
    bool fail(const std::string &message);
};
}
