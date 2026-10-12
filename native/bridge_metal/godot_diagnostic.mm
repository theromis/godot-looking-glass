// Optional frozen-quilt diagnostic. Real SDK output is an explicit bounded call.
#include "adapter.hpp"
#include "shared_frame.hpp"
#include "surface_publisher.hpp"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <cerrno>
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
    RID direct_import;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("open_surface_publisher","name","width","height"), &LookingGlassMetalDiagnostic::open_surface_publisher);
        ClassDB::bind_method(D_METHOD("surface_ready"), &LookingGlassMetalDiagnostic::surface_ready);
        ClassDB::bind_method(D_METHOD("publish_surface","sequence","quilt","verify"), &LookingGlassMetalDiagnostic::publish_surface);
        ClassDB::bind_method(D_METHOD("read_surface_pixels"), &LookingGlassMetalDiagnostic::read_surface_pixels);
        ClassDB::bind_method(D_METHOD("close_surface_publisher"), &LookingGlassMetalDiagnostic::close_surface_publisher);
        ClassDB::bind_method(D_METHOD("open_shared_frame","name","width","height"), &LookingGlassMetalDiagnostic::open_shared_frame);
        ClassDB::bind_method(D_METHOD("write_shared_frame","sequence","pixels"), &LookingGlassMetalDiagnostic::write_shared_frame);
        ClassDB::bind_method(D_METHOD("close_shared_frame"), &LookingGlassMetalDiagnostic::close_shared_frame);
        ClassDB::bind_method(D_METHOD("open_frame_pipe", "path"), &LookingGlassMetalDiagnostic::open_frame_pipe);
        ClassDB::bind_method(D_METHOD("write_frame_pipe", "sequence", "pixels", "width", "height"), &LookingGlassMetalDiagnostic::write_frame_pipe);
        ClassDB::bind_method(D_METHOD("close_frame_pipe"), &LookingGlassMetalDiagnostic::close_frame_pipe);
        ClassDB::bind_method(D_METHOD("copy_static_quilt", "quilt", "fixture", "columns", "rows", "aspect"), &LookingGlassMetalDiagnostic::copy_static_quilt);
        ClassDB::bind_method(D_METHOD("show_static_quilt", "quilt", "runtime", "display_index", "columns", "rows", "aspect", "seconds"), &LookingGlassMetalDiagnostic::show_static_quilt);
        ClassDB::bind_method(D_METHOD("begin_sequence", "runtime", "display_index", "columns", "rows", "aspect"), &LookingGlassMetalDiagnostic::begin_sequence);
        ClassDB::bind_method(D_METHOD("capture_sequence_frame", "quilt"), &LookingGlassMetalDiagnostic::capture_sequence_frame);
        ClassDB::bind_method(D_METHOD("play_sequence", "seconds"), &LookingGlassMetalDiagnostic::play_sequence);
        ClassDB::bind_method(D_METHOD("play_sequence_at_rate", "seconds", "frames_per_second"), &LookingGlassMetalDiagnostic::play_sequence_at_rate);
        ClassDB::bind_method(D_METHOD("pump_latest_frame"), &LookingGlassMetalDiagnostic::pump_latest_frame);
        ClassDB::bind_method(D_METHOD("read_sequence_output_diagnostic"), &LookingGlassMetalDiagnostic::read_sequence_output_diagnostic);
        ClassDB::bind_method(D_METHOD("close_sequence"), &LookingGlassMetalDiagnostic::close_sequence);
        ClassDB::bind_method(D_METHOD("prepare_direct_target", "width", "height"), &LookingGlassMetalDiagnostic::prepare_direct_target);
        ClassDB::bind_method(D_METHOD("import_direct_target"), &LookingGlassMetalDiagnostic::import_direct_target);
        ClassDB::bind_method(D_METHOD("submit_direct_target", "seconds"), &LookingGlassMetalDiagnostic::submit_direct_target);
        ClassDB::bind_method(D_METHOD("release_direct_import"), &LookingGlassMetalDiagnostic::release_direct_import);
        ClassDB::bind_method(D_METHOD("read_fixture_output", "fixture"), &LookingGlassMetalDiagnostic::read_fixture_output);
        ClassDB::bind_method(D_METHOD("wait_for_native_producer"), &LookingGlassMetalDiagnostic::wait_for_native_producer);
    }
public:
    SurfacePublisher surface_publisher;
    bool open_surface_publisher(String name,int64_t width,int64_t height) {
        auto *server=RenderingServer::get_singleton();
        if(![NSThread isMainThread] || server->get_current_rendering_driver_name()!="metal") return false;
        auto *rd=server->get_rendering_device();
        auto device=(__bridge id<MTLDevice>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_LOGICAL_DEVICE,RID(),0);
        return surface_publisher.open(name.utf8().get_data(),width,height,device);
    }
    bool surface_ready() { return surface_publisher.ready(); }
    bool publish_surface(int64_t sequence,RID quilt,bool verify) {
        if(![NSThread isMainThread] || sequence<=0 || sequence>UINT32_MAX) return false;
        auto *rd=RenderingServer::get_singleton()->get_rendering_device();
        if(!rd || !rd->texture_is_valid(quilt)) return false;
        auto queue=(__bridge id<MTLCommandQueue>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_COMMAND_QUEUE,RID(),0);
        auto source=(__bridge id<MTLTexture>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_TEXTURE,quilt,0);
        return surface_publisher.publish(sequence,source,queue,verify);
    }
    PackedByteArray read_surface_pixels() {
        PackedByteArray result;
        if(![NSThread isMainThread]) return result;
        auto pixels=surface_publisher.read_pixels();
        result.resize(pixels.size());
        if(!pixels.empty()) std::memcpy(result.ptrw(),pixels.data(),pixels.size());
        return result;
    }
    void close_surface_publisher() { surface_publisher.close(); }
    SharedFrame shared_frame;
    bool open_shared_frame(String name,int64_t width,int64_t height) {
        return [NSThread isMainThread] && shared_frame.open(name.utf8().get_data(),width,height,false);
    }
    bool write_shared_frame(int64_t sequence,PackedByteArray pixels) {
        return [NSThread isMainThread] && sequence>0 && sequence<=UINT32_MAX && shared_frame.publish(sequence,pixels.ptr(),pixels.size());
    }
    void close_shared_frame() { shared_frame.close(); }
    int frame_pipe=-1;
    ~LookingGlassMetalDiagnostic() { close_frame_pipe(); }
    bool open_frame_pipe(String path) {
        if (frame_pipe>=0 || ![NSThread isMainThread]) return false;
        struct stat info;
        if (stat(path.utf8().get_data(),&info)!=0 || !S_ISFIFO(info.st_mode)) return false;
        frame_pipe=::open(path.utf8().get_data(),O_WRONLY);
#ifdef F_SETNOSIGPIPE
        if (frame_pipe>=0 && fcntl(frame_pipe,F_SETNOSIGPIPE,1)<0) { close_frame_pipe(); return false; }
#endif
        return frame_pipe>=0;
    }
    bool write_frame_pipe(int64_t sequence, PackedByteArray pixels, int64_t width, int64_t height) {
        if (frame_pipe<0 || sequence<=0 || sequence>UINT32_MAX || !((width==704 && height==684) || (width==4092 && height==4092)) || pixels.size()!=width*height*4 || ![NSThread isMainThread]) return false;
        uint32_t header[]={0x4c475131,static_cast<uint32_t>(sequence),static_cast<uint32_t>(width),static_cast<uint32_t>(height)};
        const unsigned char *parts[]={reinterpret_cast<unsigned char *>(header),pixels.ptr()};
        const size_t lengths[]={sizeof(header),static_cast<size_t>(pixels.size())};
        for (int part=0;part<2;++part) {
            size_t offset=0;
            while (offset<lengths[part]) {
                ssize_t count=::write(frame_pipe,parts[part]+offset,lengths[part]-offset);
                if (count<0 && errno==EINTR) continue;
                if (count<=0) return false;
                offset+=count;
            }
        }
        return true;
    }
    void close_frame_pipe() { if (frame_pipe>=0) { ::close(frame_pipe); frame_pipe=-1; } }
    bool wait_for_native_producer() {
        // Diagnostic CPU wait for already committed work. Does not flush RD.
        auto *server=RenderingServer::get_singleton();
        if (server->get_current_rendering_driver_name()!="metal" || ![NSThread isMainThread]) return false;
        auto *rd=server->get_rendering_device();
        id<MTLCommandQueue> queue=(__bridge id<MTLCommandQueue>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_COMMAND_QUEUE,RID(),0);
        if (!queue) return false;
        auto fence=[queue commandBuffer]; [fence commit]; [fence waitUntilCompleted];
        return fence.status==MTLCommandBufferStatusCompleted;
    }
    PackedByteArray read_fixture_output(String path) {
        // Explicit fixture-only diagnostic readback, never a real output path.
        PackedByteArray bytes;
        String absolute=ProjectSettings::get_singleton()->globalize_path(path);
        void *library=dlopen(absolute.utf8().get_data(),RTLD_NOW|RTLD_LOCAL);
        if (!library) return bytes;
        auto size=reinterpret_cast<unsigned long(*)()>(dlsym(library,"fixture_output_size"));
        auto read=reinterpret_cast<bool(*)(void*,unsigned long)>(dlsym(library,"fixture_copy_output"));
        if (size && read) {
            unsigned long count=size();
            if (count && count<=16*1024*1024) {
                bytes.resize(count);
                if (!read(bytes.ptrw(),count)) bytes.clear();
            }
        }
        dlclose(library);
        return bytes;
    }
    Dictionary prepare_direct_target(int64_t width, int64_t height) {
        Dictionary result;
        bool ok=sequence && [NSThread isMainThread] && width>0 && height>0 && sequence->prepare_direct_rgba8(width,height);
        result["ok"]=ok;
        if (!ok) result["error"]=sequence?String(sequence->error().c_str()):String("Main-thread open session required");
        return result;
    }
    RID import_direct_target() {
        // Call on the Godot render thread, after main-thread SDK allocation.
        if (!sequence || direct_import.is_valid() || !sequence->direct_texture()) return RID();
        auto *server=RenderingServer::get_singleton();
        if (server->get_current_rendering_driver_name()!="metal") return RID();
        auto *rd=server->get_rendering_device();
        id<MTLTexture> target=sequence->direct_texture();
        auto usage=RenderingDevice::TEXTURE_USAGE_STORAGE_BIT|RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice::TEXTURE_USAGE_CAN_COPY_TO_BIT;
        direct_import=rd->texture_create_from_extension(RenderingDevice::TEXTURE_TYPE_2D,RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM,RenderingDevice::TEXTURE_SAMPLES_1,usage,(uint64_t)(__bridge void *)target,target.width,target.height,1,1,1);
        return direct_import;
    }
    Dictionary submit_direct_target(double seconds) {
        Dictionary result;
        if (!sequence || !direct_import.is_valid() || ![NSThread isMainThread]) { result["error"]="Imported frozen target and main thread required"; return result; }
        auto *rd=RenderingServer::get_singleton()->get_rendering_device();
        id<MTLCommandQueue> queue=(__bridge id<MTLCommandQueue>)(void *)(uintptr_t)rd->get_driver_resource(RenderingDevice::DRIVER_RESOURCE_COMMAND_QUEUE,RID(),0);
        auto fence=[queue commandBuffer]; [fence commit];
        bool ok=sequence->submit_direct(fence,sequence_columns,sequence_rows,sequence_aspect);
        // Zero duration is fixture-only pixel validation, not a physical show.
        if (ok && seconds>0) ok=sequence->show_immutable(sequence_columns,sequence_rows,sequence_aspect,seconds);
        result["ok"]=ok; if (!ok) result["error"]=String(sequence->error().c_str());
        return result;
    }
    void release_direct_import() {
        // Render-thread call after all rig callbacks and producer work stopped.
        if (direct_import.is_valid()) {
            RenderingServer::get_singleton()->get_rendering_device()->free_rid(direct_import);
            direct_import=RID();
        }
    }
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
    Dictionary pump_latest_frame() {
        Dictionary result;
        bool ok=sequence && sequence->pump_latest_immutable(sequence_columns,sequence_rows,sequence_aspect);
        result["ok"]=ok;
        if (!ok) result["error"]=sequence?String(sequence->error().c_str()):String("No sequence");
        return result;
    }
    PackedByteArray read_sequence_output_diagnostic() {
        PackedByteArray bytes;
        if (!sequence || ![NSThread isMainThread]) return bytes;
        id<MTLTexture> texture=sequence->direct_texture();
        if (!texture || texture.pixelFormat!=MTLPixelFormatRGBA8Unorm || texture.storageMode!=MTLStorageModeShared || texture.width*texture.height>16*1024*1024/4) return bytes;
        // Explicit diagnostic only, after capture_sequence_frame waited for copy.
        bytes.resize(texture.width*texture.height*4);
        [texture getBytes:bytes.ptrw() bytesPerRow:texture.width*4 fromRegion:MTLRegionMake2D(0,0,texture.width,texture.height) mipmapLevel:0];
        return bytes;
    }
    Dictionary play_sequence(double seconds) {
        Dictionary result;
        bool ok=sequence && sequence->show_immutable(sequence_columns,sequence_rows,sequence_aspect,seconds);
        result["ok"]=ok; if (!ok) result["error"]=sequence?String(sequence->error().c_str()):String("No sequence");
        return result;
    }
    Dictionary play_sequence_at_rate(double seconds, double frames_per_second) {
        Dictionary result;
        bool ok=sequence && sequence->show_immutable(sequence_columns,sequence_rows,sequence_aspect,seconds,frames_per_second);
        result["ok"]=ok;
        if (!ok) result["error"]=sequence?String(sequence->error().c_str()):String("No sequence");
        return result;
    }
    Dictionary close_sequence() {
        Dictionary result;
        if (direct_import.is_valid()) { result["error"]="Release imported RID on render thread before SDK close"; return result; }
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
