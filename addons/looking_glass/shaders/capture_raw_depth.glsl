#[compute]
#version 450
layout(local_size_x=8, local_size_y=8, local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D source_color;
layout(set=0,binding=1) uniform sampler2D source_depth;
layout(rgba16f,set=0,binding=2) uniform writeonly image2D color_out;
layout(r32f,set=0,binding=3) uniform writeonly image2D depth_out;
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(xy,imageSize(color_out)))) return;
    float d=texelFetch(source_depth,xy,0).r;
    // Godot 4.3+ RD reverse-Z, zero-to-one depth; perspective only.
    float z=d;
    imageStore(color_out,xy,texelFetch(source_color,xy,0));
    imageStore(depth_out,xy,vec4(z));
}
