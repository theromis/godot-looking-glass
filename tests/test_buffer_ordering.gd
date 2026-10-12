# Standalone RenderingDevice dependency test, compiled from source at runtime.
extends SceneTree
const SHADER = """#version 450
layout(local_size_x=1,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,std140) uniform Input { ivec4 value; } input_data;
layout(set=0,binding=1,std430) buffer Output { int values[]; } output_data;
layout(push_constant,std430) uniform Params { ivec4 index; } p;
void main() { output_data.values[p.index.x]=input_data.value.x; }
"""
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var rd := RenderingServer.create_local_rendering_device()
    if rd==null:
        print("FAIL no RenderingDevice")
        quit(1)
        return
    var source := RDShaderSource.new()
    source.source_compute=SHADER
    var spirv := rd.shader_compile_spirv_from_source(source)
    if not spirv.compile_error_compute.is_empty():
        print("FAIL shader compilation: ",spirv.compile_error_compute)
        quit(1)
        return
    var shader := rd.shader_create_from_spirv(spirv)
    var pipeline := rd.compute_pipeline_create(shader)
    var input := rd.uniform_buffer_create(16,PackedInt32Array([0,0,0,0]).to_byte_array())
    var zeros := PackedByteArray()
    zeros.resize(256)
    var output := rd.storage_buffer_create(256,zeros)
    var uniforms: Array[RDUniform] = []
    for binding in range(2):
        var u := RDUniform.new()
        u.binding=binding
        u.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER if binding==0 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u.add_id(input if binding==0 else output)
        uniforms.append(u)
    var set_rid := rd.uniform_set_create(uniforms,shader,0)
    for i in range(64):
        rd.buffer_update(input,0,16,PackedInt32Array([i+1,0,0,0]).to_byte_array())
        var list := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(list,pipeline)
        rd.compute_list_bind_uniform_set(list,set_rid,0)
        rd.compute_list_set_push_constant(list,PackedInt32Array([i,0,0,0]).to_byte_array(),16)
        rd.compute_list_dispatch(list,1,1,1)
        rd.compute_list_end()
    rd.submit()
    rd.sync()
    var data := rd.buffer_get_data(output).to_int32_array()
    var failed: Array[int] = []
    if data.size()!=64:
        failed.append(-1)
    else:
        for i in range(64):
            if data[i]!=i+1: failed.append(i)
    print("BUFFER values=",data," failed_indices=",failed)
    for rid in [set_rid,output,input,pipeline,shader]: rd.free_rid(rid)
    rd.free()
    print("PASS buffer ordering: 64 interleaved uniform updates and dependent reads" if failed.is_empty() else "FAIL buffer ordering")
    quit(0 if failed.is_empty() else 1)
