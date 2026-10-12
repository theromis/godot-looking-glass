#[compute]
#version 450
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer Blocks { uvec4 values[]; } blocks;
layout(set=0,binding=1,std430) writeonly buffer Totals { uvec4 values[]; } totals;
layout(push_constant,std430) uniform Params { uint blocks_per_view; } params;
shared uvec4 sums[64];
void main() {
    uint view = gl_WorkGroupID.x;
    uint lane = gl_LocalInvocationID.x;
    uvec4 sum = uvec4(0);
    for (uint block=lane; block<params.blocks_per_view; block+=64)
        sum += blocks.values[view*params.blocks_per_view+block];
    sums[lane] = sum;
    barrier();
    for (uint stride=32; stride>0; stride>>=1) {
        if (lane<stride) sums[lane] += sums[lane+stride];
        barrier();
    }
    if (lane==0) totals.values[view] = sums[0];
}
