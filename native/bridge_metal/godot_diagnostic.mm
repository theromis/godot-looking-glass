// Optional frozen-quilt diagnostic. Real SDK output is an explicit bounded call.
#include "adapter.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <dlfcn.h>
#include <memory>
using namespace godot;
class LookingGlassMetalDiagnostic : public RefCounted {
    GDCLASS(LookingGlassMetalDiagnostic, RefCounted)
    std::unique_ptr<looking_glass::MetalAdapter> sequence;
    int64_t sequence_columns=0, sequence_rows=0;
    double sequence_aspect=0;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("copy_static_quilt", "quilt", "fixture", "columns", "rows", "aspect"), &LookingGlassMetalDiagnostic::copy_static_quilt);
        ClassDB::bind_method(D_METHOD("show_static_quilt", "quilt", "runtime", "display_index", "columns", "rows", "aspect", "seconds"), &LookingGlassMetalDiagnostic::show_static_quilt);
        ClassDB::bind_method(D_METHOD("begin_sequence", "runtime", "display_index", "columns", "rows", "aspect"), &LookingGlassMetalDiagnostic::begin_sequence);
        ClassDB::bind_method(D_METHOD("capture_sequence_frame", "quilt"), &LookingGlassMetalDiagnostic::capture_sequence_frame);
        ClassDB::bind_method(D_METHOD("play_sequence", "seconds"), &LookingGlassMetalDiagnostic::play_sequence);
        ClassDB::bind_method(D_METHOD("close_sequence"), &LookingGlassMetalDiagnostic::close_sequence);
    }
public:
    Dictionary begin_sequence(String path, int64_t index, int64_t columns, int64_t rows, double aspect) {
        Dictionary result;
        auto *server=RenderingServer::get_singleton();
        if (sequence || ![NSThread isMainThread] || server->get_current_rendering_driver_name()!="metal" || index<0 || columns<=0 || rows<=0 || aspect<=0) {
            result["error"]="Invalid sequence configuration/thread/driver or existing sequence"; return result;
        }
        auto *rd=server->get_rendering_device();
        if (!rd) { result["error"]="RenderingDevice unavailable"; return result; }
        id<MTLDevice> device=(__bridge id<MTLDevice>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_LOGICAL_DEVICE,RID(),0);
        sequence=std::make_unique<looking_glass::MetalAdapter>();
        String absolute=ProjectSettings::get_singleton()->globalize_path(path);
        bool ok=sequence->load(absolute.utf8().get_data()) && sequence->open(device,index);
        if (!ok) { result["error"]=String(sequence->error().c_str()); sequence.reset(); }
        sequence_columns=columns; sequence_rows=rows; sequence_aspect=aspect;
        result["ok"]=ok; return result;
    }
    Dictionary capture_sequence_frame(RID quilt) {
        Dictionary result;
        auto *rd=RenderingServer::get_singleton()->get_rendering_device();
        if (!sequence || ![NSThread isMainThread] || !rd || !rd->texture_is_valid(quilt)) { result["error"]="Open sequence and frozen valid quilt required"; return result; }
        id<MTLCommandQueue> queue=(__bridge id<MTLCommandQueue>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_COMMAND_QUEUE,RID(),0);
        id<MTLTexture> source=(__bridge id<MTLTexture>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE,quilt,0);
        if (!queue || !source) { result["error"]="Native source handles missing"; return result; }
        auto fence=[queue commandBuffer]; [fence commit];
        bool ok=sequence->append_immutable(source,fence,sequence_columns,sequence_rows,sequence_aspect);
        result["ok"]=ok; if (!ok) result["error"]=String(sequence->error().c_str());
        return result;
    }
    Dictionary play_sequence(double seconds) {
        Dictionary result;
        bool ok=sequence && sequence->show_immutable(sequence_columns,sequence_rows,sequence_aspect,seconds);
        result["ok"]=ok; if (!ok) result["error"]=sequence?String(sequence->error().c_str()):String("No sequence");
        return result;
    }
    Dictionary close_sequence() {
        Dictionary result;
        if (![NSThread isMainThread]) { result["error"]="Main thread required"; return result; }
        bool ok=!sequence || sequence->close();
        if (!ok) result["error"]=String(sequence->error().c_str());
        else sequence.reset();
        result["ok"]=ok; return result;
    }
    Dictionary show_static_quilt(RID quilt, String path, int64_t index, int64_t columns, int64_t rows, double aspect, double seconds) {
        Dictionary result;
        auto *server=RenderingServer::get_singleton();
        if (server->get_current_rendering_driver_name()!="metal" || ![NSThread isMainThread]) {
            result["error"]="Native Metal and main thread required"; return result;
        }
        auto *rd=server->get_rendering_device();
        if (!rd || !rd->texture_is_valid(quilt) || index<0 || columns<=0 || rows<=0 || seconds<=0 || seconds>30) {
            result["error"]="Invalid frozen quilt or output configuration"; return result;
        }
        // Caller disables the render loop, freezes the rig and flushes prior frames.
        // Reading these stable native handles does not flush pending RD lists.
        id<MTLDevice> device=(__bridge id<MTLDevice>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_LOGICAL_DEVICE,RID(),0);
        id<MTLCommandQueue> queue=(__bridge id<MTLCommandQueue>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_COMMAND_QUEUE,RID(),0);
        id<MTLTexture> source=(__bridge id<MTLTexture>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE,quilt,0);
        if (!device || !queue || !source || source.pixelFormat!=MTLPixelFormatRGBA8Unorm) {
            result["error"]="RGBA8 native Metal quilt required"; return result;
        }
        auto fence=[queue commandBuffer]; [fence commit];
        looking_glass::MetalAdapter adapter;
        String absolute=ProjectSettings::get_singleton()->globalize_path(path);
        bool ok=adapter.load(absolute.utf8().get_data()) && adapter.open(device,index) && adapter.submit_once(source,fence,columns,rows,aspect) && adapter.show_immutable(columns,rows,aspect,seconds);
        result["sdk_version"]=String(adapter.version().c_str());
        if (!ok) result["error"]=String(adapter.error().c_str());
        if (!adapter.close()) { ok=false; result["error"]=String(adapter.error().c_str()); }
        result["ok"]=ok;
        return result;
    }
    Dictionary copy_static_quilt(RID quilt, String path, int64_t columns, int64_t rows, double aspect) {
        Dictionary result;
        auto *server=RenderingServer::get_singleton();
        String driver=server->get_current_rendering_driver_name();
        result["driver"]=driver;
        if (driver!="metal") { result["error"]="Native Metal required; Vulkan handles are not Metal pointers"; return result; }
        auto *rd=server->get_rendering_device();
        if (!rd || !rd->texture_is_valid(quilt)) { result["error"]="Invalid RenderingDevice quilt texture"; return result; }
        String absolute=ProjectSettings::get_singleton()->globalize_path(path);
        void *fixture=dlopen(absolute.utf8().get_data(),RTLD_NOW|RTLD_LOCAL);
        if (!fixture) { result["error"]="Cannot load test fixture"; return result; }
        auto size=reinterpret_cast<unsigned long(*)()>(dlsym(fixture,"fixture_output_size"));
        auto read=reinterpret_cast<bool(*)(void*,unsigned long)>(dlsym(fixture,"fixture_copy_output"));
        if (!size || !read) { dlclose(fixture); result["error"]="Only the SDK test fixture is accepted"; return result; }
        id<MTLDevice> device=(__bridge id<MTLDevice>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_LOGICAL_DEVICE,RID(),0);
        id<MTLCommandQueue> queue=(__bridge id<MTLCommandQueue>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_COMMAND_QUEUE,RID(),0);
        id<MTLTexture> source=(__bridge id<MTLTexture>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE,quilt,0);
        if (!device || !queue || !source || source.device!=device || queue.device!=device) { dlclose(fixture); result["error"]="Missing or inconsistent native Metal handles"; return result; }
        if (source.width*source.height>16*1024*1024/8) { dlclose(fixture); result["error"]="Test quilt exceeds bounded readback size"; return result; }
        // Caller must freeze the quilt and finish its producing Godot frame first.
        // Same-queue sentinel fences prior committed work, not unsubmitted RD lists.
        id<MTLCommandBuffer> fence=[queue commandBuffer];
        [fence commit];
        looking_glass::MetalAdapter adapter;
        bool ok=adapter.load(absolute.utf8().get_data()) && adapter.open(device,7) && adapter.submit_once(source,fence,columns,rows,aspect);
        if (ok) {
            unsigned long bytes=size();
            if (!bytes || bytes>16*1024*1024) { ok=false; result["error"]="Invalid test readback size"; }
            else {
                PackedByteArray output;
                output.resize(bytes);
                ok=read(output.ptrw(),bytes);
                if (ok) result["fixture_bytes"]=output;
                else result["error"]="Fixture readback failed";
            }
            result["width"]=static_cast<int64_t>(source.width);
            result["height"]=static_cast<int64_t>(source.height);
            result["sdk_version"]=String(adapter.version().c_str());
        } else result["error"]=String(adapter.error().c_str());
        if (!adapter.close()) { ok=false; result["error"]=String(adapter.error().c_str()); }
        dlclose(fixture);
        result["ok"]=ok;
        return result;
    }
};
static void initialize(ModuleInitializationLevel level) {
    if (level==MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<LookingGlassMetalDiagnostic>();
}
static void terminate(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT looking_glass_diagnostic_init(GDExtensionInterfaceGetProcAddress proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    GDExtensionBinding::InitObject object(proc,library,init);
    object.register_initializer(initialize);
    object.register_terminator(terminate);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return object.init();
}
