#pragma once
// GPU surface descriptor/ack mailbox; no pixel payload or SDK consumer fence.
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <semaphore.h>
#include <unistd.h>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <string>
#include <vector>
#include <cstdint>
#include <cstdio>
class SurfaceMailbox {
    int fd_=-1;
    void *mapping_=MAP_FAILED;
    sem_t *mutex_=SEM_FAILED;
    size_t bytes_=0, size_=0;
    unsigned width_=0,height_=0;
    std::string name_, sem_name_;
    bool own_memory_=false,own_semaphore_=false;
    bool lock() {
        auto until=std::chrono::steady_clock::now()+std::chrono::seconds(2);
        while(sem_trywait(mutex_)!=0) {
            if(errno!=EAGAIN && errno!=EINTR) return false;
            if(std::chrono::steady_clock::now()>=until) return false;
            usleep(250);
        }
        return true;
    }
public:
    SurfaceMailbox()=default;
    SurfaceMailbox(const SurfaceMailbox &)=delete;
    SurfaceMailbox &operator=(const SurfaceMailbox &)=delete;
    ~SurfaceMailbox() { close(); }
    bool open(const std::string &name,unsigned width,unsigned height,bool create) {
        if(fd_>=0 || name.size()<2 || name.size()>20 || name[0]!='/' || name.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",1)!=std::string::npos) return false;
        if(!((width==704 && height==684) || (width==4092 && height==4092))) return false;
        name_=name; sem_name_=name+"_s"; width_=width; height_=height;
        bytes_=0; size_=32;
        fd_=shm_open(name.c_str(),O_RDWR|(create?O_CREAT|O_EXCL:0),0600);
        if(fd_<0) { perror("SurfaceMailbox shm_open"); return false; }
        own_memory_=create;
        if(create && ftruncate(fd_,size_)!=0) { perror("SurfaceMailbox ftruncate"); close(); return false; }
        struct stat info={};
        const size_t page=static_cast<size_t>(sysconf(_SC_PAGESIZE));
        const size_t rounded=(size_+page-1)/page*page;
        if(fstat(fd_,&info)!=0 || info.st_size<static_cast<off_t>(size_) || info.st_size>static_cast<off_t>(rounded)) { fprintf(stderr,"SurfaceMailbox size mismatch actual=%lld expected=%zu errno=%d\n",static_cast<long long>(info.st_size),size_,errno); close(); return false; }
        mapping_=mmap(nullptr,size_,PROT_READ|PROT_WRITE,MAP_SHARED,fd_,0);
        if(mapping_==MAP_FAILED) { perror("SurfaceMailbox mmap"); close(); return false; }
        if(create) { uint32_t header[]={0x4c475332,0,width,height,0,0,0,0}; std::memcpy(mapping_,header,32); }
        mutex_=create?sem_open(sem_name_.c_str(),O_CREAT|O_EXCL,0600,1):sem_open(sem_name_.c_str(),0);
        if(mutex_==SEM_FAILED) { perror("SurfaceMailbox sem_open"); close(); return false; }
        own_semaphore_=create;
        return true;
    }
    bool ready() {
        if(mapping_==MAP_FAILED || mutex_==SEM_FAILED || !lock()) return false;
        auto *h=static_cast<uint32_t *>(mapping_);
        bool ok=h[0]==0x4c475332 && h[1]==h[5];
        return sem_post(mutex_)==0 && ok;
    }
    bool publish(uint32_t sequence,uint32_t surface,uint32_t checksum) {
        if(mapping_==MAP_FAILED || mutex_==SEM_FAILED || !sequence || !surface || !lock()) return false;
        auto *h=static_cast<uint32_t *>(mapping_);
        bool ok=h[0]==0x4c475332 && h[1]==h[5] && sequence>h[1];
        if(ok) { h[4]=surface; h[6]=checksum; h[1]=sequence; }
        return sem_post(mutex_)==0 && ok;
    }
    bool latest(uint32_t previous,uint32_t &surface,uint32_t &checksum,uint32_t &sequence) {
        sequence=0;
        if(mapping_==MAP_FAILED || mutex_==SEM_FAILED || !lock()) return false;
        auto *h=static_cast<uint32_t *>(mapping_);
        bool ok=h[0]==0x4c475332 && h[2]==width_ && h[3]==height_;
        if(ok && h[1]>previous) { sequence=h[1]; surface=h[4]; checksum=h[6]; }
        return sem_post(mutex_)==0 && ok;
    }
    bool acknowledge(uint32_t sequence) {
        if(mapping_==MAP_FAILED || mutex_==SEM_FAILED || !lock()) return false;
        auto *h=static_cast<uint32_t *>(mapping_);
        bool ok=h[0]==0x4c475332 && sequence==h[1];
        if(ok) h[5]=sequence;
        return sem_post(mutex_)==0 && ok;
    }
    void close() {
        if(mapping_!=MAP_FAILED) { munmap(mapping_,size_); mapping_=MAP_FAILED; }
        if(fd_>=0) { ::close(fd_); fd_=-1; }
        if(mutex_!=SEM_FAILED) { sem_close(mutex_); mutex_=SEM_FAILED; }
        if(own_semaphore_) { sem_unlink(sem_name_.c_str()); own_semaphore_=false; }
        if(own_memory_) { shm_unlink(name_.c_str()); own_memory_=false; }
    }
};
