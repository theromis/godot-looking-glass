#pragma once
#import <IOSurface/IOSurface.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <string>
#include <cstring>
#include <iostream>
struct SurfacePortMessage {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t port;
    uint32_t magic;
};
inline std::string surface_service(const std::string &name) { return "org.lookingglass."+name.substr(1); }
inline bool send_surface_port(const std::string &name,IOSurfaceRef surface) {
    mach_port_t target=MACH_PORT_NULL;
    std::string service=surface_service(name);
    kern_return_t result=bootstrap_look_up(bootstrap_port,service.c_str(),&target);
    if(result!=KERN_SUCCESS) { std::cerr<<"SURFACE port lookup_failed code="<<result<<std::endl; return false; }
    mach_port_t port=IOSurfaceCreateMachPort(surface);
    if(port==MACH_PORT_NULL) { mach_port_deallocate(mach_task_self(),target); return false; }
    SurfacePortMessage message={};
    message.header.msgh_bits=MACH_MSGH_BITS_COMPLEX|MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,0);
    message.header.msgh_size=sizeof(message); message.header.msgh_remote_port=target;
    message.header.msgh_id=0x4c475350;
    message.body.msgh_descriptor_count=1;
    message.port.name=port; message.port.disposition=MACH_MSG_TYPE_COPY_SEND; message.port.type=MACH_MSG_PORT_DESCRIPTOR;
    message.magic=0x4c475350;
    result=mach_msg(&message.header,MACH_SEND_MSG|MACH_SEND_TIMEOUT,sizeof(message),0,MACH_PORT_NULL,1000,MACH_PORT_NULL);
    mach_port_deallocate(mach_task_self(),port); mach_port_deallocate(mach_task_self(),target);
    if(result!=KERN_SUCCESS) std::cerr<<"SURFACE port send_failed code="<<result<<std::endl;
    return result==KERN_SUCCESS;
}
class SurfacePortReceiver {
    mach_port_t port_=MACH_PORT_NULL;
    std::string service_;
    bool registered_=false;
public:
    SurfacePortReceiver()=default;
    SurfacePortReceiver(const SurfacePortReceiver &)=delete;
    SurfacePortReceiver &operator=(const SurfacePortReceiver &)=delete;
    ~SurfacePortReceiver() { close(); }
    bool open(const std::string &name) {
        service_=surface_service(name);
        kern_return_t result=mach_port_allocate(mach_task_self(),MACH_PORT_RIGHT_RECEIVE,&port_);
        if(result==KERN_SUCCESS) result=mach_port_insert_right(mach_task_self(),port_,port_,MACH_MSG_TYPE_MAKE_SEND);
        if(result==KERN_SUCCESS) { name_t service_name={}; std::strncpy(service_name,service_.c_str(),sizeof(service_name)-1); result=bootstrap_register(bootstrap_port,service_name,port_); }
        registered_=result==KERN_SUCCESS;
        if(!registered_) std::cerr<<"SURFACE port register_failed code="<<result<<std::endl;
        return registered_;
    }
    bool receive(IOSurfaceRef &surface) {
        surface=nullptr;
        struct { SurfacePortMessage message; mach_msg_max_trailer_t trailer; } incoming={};
        kern_return_t result=mach_msg(&incoming.message.header,MACH_RCV_MSG|MACH_RCV_TIMEOUT,0,sizeof(incoming),port_,0,MACH_PORT_NULL);
        if(result==MACH_RCV_TIMED_OUT) return true;
        if(result!=KERN_SUCCESS) return false;
        auto &message=incoming.message;
        bool valid=(message.header.msgh_bits&MACH_MSGH_BITS_COMPLEX) && message.header.msgh_id==0x4c475350 && message.header.msgh_size==sizeof(SurfacePortMessage) && message.magic==0x4c475350 && message.body.msgh_descriptor_count==1 && message.port.type==MACH_MSG_PORT_DESCRIPTOR;
        if(!valid) { mach_msg_destroy(&message.header); return false; }
        surface=IOSurfaceLookupFromMachPort(message.port.name);
        mach_port_deallocate(mach_task_self(),message.port.name);
        return surface!=nullptr;
    }
    void close() {
        // Destroy owned receive/send rights. launchd observes the dead port;
        // bootstrap_register(..., MACH_PORT_NULL) cannot replace a live service.
        if(port_!=MACH_PORT_NULL) { mach_port_mod_refs(mach_task_self(),port_,MACH_PORT_RIGHT_RECEIVE,-1); mach_port_deallocate(mach_task_self(),port_); port_=MACH_PORT_NULL; }
        registered_=false;
    }
};
