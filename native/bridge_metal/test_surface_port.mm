#include "surface_port.hpp"
#include <unistd.h>
int main() { @autoreleasepool {
    std::string name="/lgp"+std::to_string(getpid());
    { SurfacePortReceiver first; if(!first.open(name)) return 1; first.close(); }
    bool reopened=false;
    for(int attempt=0;attempt<5 && !reopened;++attempt) {
        usleep(50000);
        SurfacePortReceiver next;
        reopened=next.open(name);
    }
    std::cout<<(reopened?"PASS":"FAIL")<<" surface Mach endpoint: close and same-name registration reuse"<<std::endl;
    return reopened?0:1;
} }
