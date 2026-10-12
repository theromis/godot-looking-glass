#[compute]
#version 450
layout(local_size_x=16,local_size_y=16,local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D color_a;
layout(set=0,binding=1) uniform sampler2D depth_a;
layout(set=0,binding=2) uniform sampler2D color_b;
layout(set=0,binding=3) uniform sampler2D depth_b;
layout(rgba16f,set=0,binding=4) uniform writeonly image2D quilt;
layout(push_constant,std430) uniform Params {
    vec4 geometry; // eye target, eye a, eye b, focus
    vec4 tile; // width height output x output y
    vec4 projection; // horizontal slope, real flag, debug holes, reserved
    vec4 clip; // near, far, inverse far, inverse near - inverse far
} p;
float read_inverse_depth(sampler2D dep, vec2 uv) {
    float d=textureLod(dep,uv,0).r;
    return p.clip.z+d*p.clip.w; // inverse far + reverse-Z * (inverse near - inverse far)
}
// z/za/zb variables hold inverse depth; larger values are nearer.
// Independent inverse warp, no scatter write races. Bounded fixed-point solve.
vec4 gather(sampler2D col,sampler2D dep,vec2 uv,float delta,out float z,out bool valid) {
    vec2 q=uv;
    z=read_inverse_depth(dep,q);
    for(int k=0;k<8;k++) {
        q=uv+vec2(delta*(min(z,1000.0)-1.0/p.geometry.w)/p.projection.x,0);
        if(any(lessThan(q,vec2(0)))||any(greaterThanEqual(q,vec2(1)))) { valid=false; return vec4(0); }
        float next_z=read_inverse_depth(dep,q);
        // An identical depth is an exact fixed point: the next UV and every
        // remaining iteration are identical. No approximate early exit.
        if(next_z==z) break;
        z=next_z;
    }
    vec2 residual=q-vec2(delta*(min(z,1000.0)-1.0/p.geometry.w)/p.projection.x,0)-uv;
    valid=abs(residual.x)*p.tile.x<1.0;
    return textureLod(col,q,0);
}
void main() {
    ivec2 xy=ivec2(gl_GlobalInvocationID.xy);
    if(any(greaterThanEqual(xy,ivec2(p.tile.xy)))) return;
    vec2 uv=(vec2(xy)+0.5)/p.tile.xy;
    vec4 result;
    if(p.projection.y>0.5) result=textureLod(color_a,uv,0);
    else {
        float za,zb; bool va,vb;
        vec4 a=gather(color_a,depth_a,uv,p.geometry.x-p.geometry.y,za,va);
        vec4 b=gather(color_b,depth_b,uv,p.geometry.x-p.geometry.z,zb,vb);
        if(va&&vb) result=za>=zb?a:b;
        else if(va) result=a;
        else if(vb) result=b;
        else result=p.projection.z>0.5?vec4(1,0,1,1):textureLod(color_a,uv,0);
    }
    // Simple preview transfer: compositor color is linear HDR, not tonemapped.
    result.rgb=pow(max(result.rgb,vec3(0)),vec3(1.0/2.2));
    result.a=1;
    imageStore(quilt,xy+ivec2(p.tile.zw),result);
}
