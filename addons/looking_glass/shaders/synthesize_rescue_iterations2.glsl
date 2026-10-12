#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(set=0,binding=0) uniform sampler2D color_a;
layout(set=0,binding=1) uniform sampler2D depth_a;
layout(set=0,binding=2) uniform sampler2D color_b;
layout(set=0,binding=3) uniform sampler2D depth_b;
layout(rgba16f,set=0,binding=4) uniform writeonly image2D quilt;
layout(push_constant,std430) uniform Params {
    vec4 geometry; // eye target, eye a, eye b, focus
    vec4 tile; // width height output x output y
    vec4 projection; // horizontal slope, real flag, debug holes, reserved
} p;
// Independent inverse warp, no scatter write races. Bounded fixed-point solve.
vec4 gather(sampler2D col,sampler2D dep,vec2 uv,float delta,out float z,out bool valid) {
    vec2 q=uv;
    z=textureLod(dep,q,0).r;
    for(int k=0;k<2;k++) {
        q=uv+vec2(delta*(1.0/max(z,0.001)-1.0/p.geometry.w)/p.projection.x,0);
        if(any(lessThan(q,vec2(0)))||any(greaterThanEqual(q,vec2(1)))) { valid=false; return vec4(0); }
        float next_z=textureLod(dep,q,0).r;
        // An identical depth is an exact fixed point: the next UV and every
        // remaining iteration are identical. No approximate early exit.
        if(next_z==z) break;
        z=next_z;
    }
    vec2 residual=q-vec2(delta*(1.0/max(z,0.001)-1.0/p.geometry.w)/p.projection.x,0)-uv;
    valid=abs(residual.x)*p.tile.x<1.0;
    return textureLod(col,q,0);
}
// A nearby source depth is a hypothesis, not a neighboring output color.
// Reproject to this exact target pixel, then validate with depth at the landing UV.
vec4 rescue(sampler2D col,sampler2D dep,vec2 uv,float delta,out float best_z,out bool found) {
    vec4 best=vec4(0); best_z=1e30; found=false;
    const float offsets[6]=float[6](-4.0,-2.0,-1.0,1.0,2.0,4.0);
    for(int j=0;j<6;j++) {
        vec2 seed=uv+vec2(offsets[j]/p.tile.x,0);
        if(seed.x<0.0||seed.x>=1.0) continue;
        float hypothesis=textureLod(dep,seed,0).r;
        vec2 q=uv+vec2(delta*(1.0/max(hypothesis,0.001)-1.0/p.geometry.w)/p.projection.x,0);
        if(any(lessThan(q,vec2(0)))||any(greaterThanEqual(q,vec2(1)))) continue;
        float z=textureLod(dep,q,0).r;
        float residual=q.x-delta*(1.0/max(z,0.001)-1.0/p.geometry.w)/p.projection.x-uv.x;
        if(abs(residual)*p.tile.x<0.5&&z<best_z) {
            best_z=z; best=textureLod(col,q,0); found=true;
        }
    }
    return best;
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
        if(!va&&!vb) {
            a=rescue(color_a,depth_a,uv,p.geometry.x-p.geometry.y,za,va);
            b=rescue(color_b,depth_b,uv,p.geometry.x-p.geometry.z,zb,vb);
        }
        if(va&&vb) result=za<=zb?a:b;
        else if(va) result=a;
        else if(vb) result=b;
        else result=p.projection.z>0.5?vec4(1,0,1,1):textureLod(color_a,uv,0);
    }
    // Simple preview transfer: compositor color is linear HDR, not tonemapped.
    result.rgb=pow(max(result.rgb,vec3(0)),vec3(1.0/2.2));
    result.a=1;
    imageStore(quilt,xy+ivec2(p.tile.zw),result);
}
