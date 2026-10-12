#include "surface_mailbox.hpp"
#include <sys/wait.h>
#include <iostream>
int main() {
    std::string name="/lgs"+std::to_string(getpid());
    SurfaceMailbox owner,writer;
    if(!owner.open(name,704,684,true) || !writer.open(name,704,684,false)) return 1;
    if(!writer.ready() || !writer.publish(1,101,11) || writer.ready() || writer.publish(2,102,22) || owner.acknowledge(99)) return 2;
    pid_t child=fork();
    if(child<0) return 3;
    if(child==0) {
        unsigned previous=0;
        auto until=std::chrono::steady_clock::now()+std::chrono::seconds(5);
        while(previous<32 && std::chrono::steady_clock::now()<until) {
            unsigned surface=0,checksum=0,sequence=0;
            if(!owner.latest(previous,surface,checksum,sequence)) _exit(4);
            if(sequence) {
                if(surface!=100+sequence || checksum!=sequence*11 || !owner.acknowledge(sequence)) _exit(5);
                previous=sequence;
            }
            usleep(100);
        }
        _exit(previous==32?0:6);
    }
    bool ok=true;
    for(unsigned sequence=2;sequence<=32;++sequence) {
        auto until=std::chrono::steady_clock::now()+std::chrono::seconds(2);
        while(!writer.ready() && std::chrono::steady_clock::now()<until) usleep(100);
        if(!writer.publish(sequence,100+sequence,sequence*11)) { ok=false; break; }
    }
    int status=0;waitpid(child,&status,0);
    ok=ok && WIFEXITED(status) && WEXITSTATUS(status)==0 && writer.ready() && !writer.publish(32,132,352);
    writer.close();owner.close();
    std::cout<<(ok?"PASS":"FAIL")<<" surface mailbox: cross-process 32 acknowledgments, outstanding-frame guard, wrong-ack and stale-sequence rejection"<<std::endl;
    return ok?0:1;
}
