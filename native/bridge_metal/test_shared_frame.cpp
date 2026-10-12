#include "shared_frame.hpp"
#include <sys/wait.h>
#include <iostream>
int main() {
    std::string name="/lgt"+std::to_string(getpid());
    SharedFrame owner;
    if(!owner.open(name,704,684,true)) return 1;
    pid_t child=fork();
    if(child<0) return 1;
    if(child==0) {
        SharedFrame writer;
        if(!writer.open(name,704,684,false)) _exit(2);
        std::vector<unsigned char> pixels(704*684*4);
        if(writer.publish(1,pixels.data(),1)) _exit(3);
        for(unsigned sequence=1;sequence<=32;++sequence) {
            std::memset(pixels.data(),sequence,pixels.size());
            if(!writer.publish(sequence,pixels.data(),pixels.size())) _exit(4);
            usleep(2000);
        }
        _exit(0);
    }
    unsigned previous=0,count=0;
    std::vector<unsigned char> pixels;
    bool ok=true;
    auto until=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    while(previous<32 && std::chrono::steady_clock::now()<until) {
        unsigned sequence=0;
        if(!owner.latest(previous,pixels,sequence)) { ok=false; break; }
        if(sequence) {
            for(auto value:pixels) if(value!=sequence) { ok=false; break; }
            previous=sequence; ++count;
        }
        usleep(1000);
    }
    int status=0; waitpid(child,&status,0);
    ok=ok && previous==32 && count>1 && WIFEXITED(status) && WEXITSTATUS(status)==0;
    owner.close();
    SharedFrame missing;
    ok=ok && !missing.open(name,704,684,false);
    std::cout<<(ok?"PASS":"FAIL")<<" shared-frame cross-process coherence, payload guard, final sequence, cleanup; snapshots="<<count<<std::endl;
    return ok?0:1;
}
