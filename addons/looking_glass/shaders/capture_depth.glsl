#[compute]
#version 450
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D source_depth;
layout(r32f,set=0,binding=1) uniform writeonly image2D depth_out;
layout(push_constant,std430) uniform Params { vec4 clip; } p;
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(xy,imageSize(depth_out)))) return;
    float d=texelFetch(source_depth,xy,0).r;
    float z=p.clip.x*p.clip.y/(p.clip.x+d*(p.clip.y-p.clip.x));
    imageStore(depth_out,xy,vec4(z));
}
