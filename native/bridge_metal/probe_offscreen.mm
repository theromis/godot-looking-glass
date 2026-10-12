// Diagnostic only: no quilt submission and no physical display window.
#include <bridge.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <iostream>
#include <vector>

int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::cerr << "Cannot load SDK\n"; return 2; }
    auto initialize = reinterpret_cast<decltype(&initialize_bridge)>(dlsym(library, "initialize_bridge"));
    auto shutdown = reinterpret_cast<decltype(&uninitialize_bridge)>(dlsym(library, "uninitialize_bridge"));
    auto displays = reinterpret_cast<decltype(&get_displays)>(dlsym(library, "get_displays"));
    auto offscreen = reinterpret_cast<decltype(&instance_offscreen_window_metal)>(dlsym(library, "instance_offscreen_window_metal"));
    if (!initialize || !shutdown || !displays || !offscreen) return 2;
    bool initialized = initialize("Godot Looking Glass offscreen diagnostic");
    std::cout << "initialize=" << initialized << std::endl;
    if (!initialized) return 1;
    int count = 0;
    bool listed = displays(&count, nullptr);
    std::cout << "display_query=" << listed << " count=" << count << std::endl;
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    WINDOW_HANDLE window = 0;
    bool created = device && offscreen((__bridge void *)device, &window, FIRST_LOOKING_GLASS_DEVICE);
    std::cout << "offscreen_first_device=" << created << " window=" << window << std::endl;
    // Teardown owns any SDK-created window; no invented device index or calibration.
    bool stopped = shutdown();
    std::cout << "shutdown=" << stopped << std::endl;
    if (stopped) dlclose(library);
    return stopped && listed ? 0 : 1;
} }
