#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D depth_a;
layout(set=0,binding=1) uniform sampler2D depth_b;
layout(set=0,binding=2,std430) buffer Metrics { uvec4 blocks[]; } metrics;
layout(push_constant,std430) uniform Params {
    vec4 geometry; // target eye, source eyes a/b, focus distance
    vec4 tile; // actual output tile width/height; unused z/w
    vec4 projection; // slope, real flag, unused z/w
    vec4 clip; // near, far, unused z/w
    vec4 sampling; // sparse grid width/height, target view index, unused
} p;
shared uvec4 sums[64];
float z_at(sampler2D dep,vec2 uv) {
    float d=textureLod(dep,uv,0).r;
    return p.clip.x*p.clip.y/(p.clip.x+d*(p.clip.y-p.clip.x));
}
bool correspondence(sampler2D dep,vec2 uv,float delta,out float z) {
    vec2 q=uv;
    z=z_at(dep,q);
    for(int k=0;k<8;k++) {
        q=uv+vec2(delta*(1.0/max(z,0.001)-1.0/p.geometry.w)/p.projection.x,0);
        if(any(lessThan(q,vec2(0)))||any(greaterThanEqual(q,vec2(1)))) return false;
        float next_z=z_at(dep,q);
        if(next_z==z) break;
        z=next_z;
    }
    return abs(q.x-delta*(1.0/max(z,0.001)-1.0/p.geometry.w)/p.projection.x-uv.x)*p.tile.x<1.0;
}
void main() {
    uint local=gl_LocalInvocationIndex;
    vec2 uv=(vec2(gl_GlobalInvocationID.xy)+0.5)/p.sampling.xy;
    uvec4 value=uvec4(0);
    if(p.projection.y<0.5) {
        float za,zb;
        bool va=correspondence(depth_a,uv,p.geometry.x-p.geometry.y,za);
        bool vb=correspondence(depth_b,uv,p.geometry.x-p.geometry.z,zb);
        float baseline=abs(p.geometry.z-p.geometry.y)*p.tile.x/p.projection.x;
        vec2 neighbor=uv+vec2(1.0/p.tile.x,0);
        float jump_a=abs(1.0/max(z_at(depth_a,uv),0.001)-1.0/max(z_at(depth_a,neighbor),0.001));
        float jump_b=abs(1.0/max(z_at(depth_b,uv),0.001)-1.0/max(z_at(depth_b,neighbor),0.001));
        value=uvec4(uint(!va&&!vb),uint(va!=vb),uint(max(jump_a,jump_b)*baseline>1.0),uint(va&&vb&&abs(1.0/max(za,0.001)-1.0/max(zb,0.001))*baseline>1.0));
    }
    sums[local]=value;
    barrier();
    for(uint stride=32;stride>0;stride>>=1) {
        if(local<stride) sums[local]+=sums[local+stride];
        barrier();
    }
    if(local==0) {
        uint groups_x=uint(p.sampling.x)/8;
        uint groups_y=uint(p.sampling.y)/8;
        uint block=uint(p.sampling.z)*groups_x*groups_y+gl_WorkGroupID.y*groups_x+gl_WorkGroupID.x;
        metrics.blocks[block]=sums[0];
    }
}
