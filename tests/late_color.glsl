#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform image2D color_image;
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(xy,imageSize(color_image)))) return;
    vec4 c=imageLoad(color_image,xy);
    imageStore(color_image,xy,vec4(vec3(1)-clamp(c.rgb,vec3(0),vec3(1)),c.a));
}
