package main

import "core:os"
import "core:fmt"
import "core:math/linalg"
import "vendor:microui"

import gl "vendor:OpenGL"

ShadowCubeMapShader :: struct {
	glProgram: u32,
	glVAO: u32,
}

// loads and compiles the shader
shadow_cubemap_create :: proc(this: ^ShadowCubeMapShader) {
	vsData, vsDataErr := os.read_entire_file("shaders/shadow-cubemap.vert", context.allocator)
	if vsDataErr != nil {
		panic("Failed to load and compile shadow cube mapping shaders")
	}
	defer delete(vsData)
	vertexShaderId := gl.compile_shader_from_source(string(vsData), gl.Shader_Type.VERTEX_SHADER) or_else panic("Failed to load and compile shadow cube mapping shaders")
	defer gl.DeleteShader(vertexShaderId)

	geomData, geomDataErr := os.read_entire_file("shaders/shadow-cubemap.geom", context.allocator)
	if geomDataErr != nil {
		panic("Failed to load and compile shadow cube mapping shaders")
	}
	defer delete(geomData)
	geometryShaderId := gl.compile_shader_from_source(string(geomData), gl.Shader_Type.GEOMETRY_SHADER) or_else panic("Failed to load and compile shadow cube mapping shaders")
	defer gl.DeleteShader(geometryShaderId)

	fsData, fsDataErr := os.read_entire_file("shaders/shadow-cubemap.frag", context.allocator)
	if fsDataErr != nil {
		panic("Failed to load and compile shadow cube mapping shaders")
	}
	defer delete(fsData)
	fragmentShaderId := gl.compile_shader_from_source(string(fsData), gl.Shader_Type.FRAGMENT_SHADER) or_else panic("Failed to load and compile shadow cube mapping shaders")
	defer gl.DeleteShader(fragmentShaderId)

	this.glProgram = gl.create_and_link_program([]u32{vertexShaderId, geometryShaderId, fragmentShaderId}, false) or_else panic("Failed to load and compile shadow cube mapping shaders")

	gl.GenVertexArrays(1, &this.glVAO)
	gl.BindVertexArray(this.glVAO)
}

// to be called once in the beginning of the loop
shadow_cubemap_pre_draw :: proc(this: ^ShadowCubeMapShader, pointLight: ^PointLight) {
	gl.BindVertexArray(this.glVAO)

	gl.UseProgram(this.glProgram)

	gl.EnableVertexAttribArray(0)

	gl.Enable(gl.DEPTH_TEST)

	gl.Uniform3fv(gl.GetUniformLocation(this.glProgram, "LightPos"), 1, raw_data(&pointLight.position));
	gl.Uniform1f(gl.GetUniformLocation(this.glProgram, "FarPlane"), pointLight.shadowFarPlane);

	projectionMatrix := linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(90)),
		1,
		1,
		pointLight.shadowFarPlane,
	)

	// these orientations are this specific because they must match how OpenGL spec says cubemaps are unwrapped
	viewMatrices := [?]matrix[4, 4]f32 {
		// left
		projectionMatrix * linalg.matrix4_look_at(pointLight.position, pointLight.position + [?]f32{1, 0, 0}, -WORLD_UP),
		// right
		projectionMatrix * linalg.matrix4_look_at(pointLight.position, pointLight.position + [?]f32{-1, 0, 0}, -WORLD_UP),
		// top
		projectionMatrix * linalg.matrix4_look_at(pointLight.position, pointLight.position + [?]f32{0, 1, 0}, -WORLD_FORWARD),
		// bottom
		projectionMatrix * linalg.matrix4_look_at(pointLight.position, pointLight.position + [?]f32{0, -1, 0}, WORLD_FORWARD),
		// front
		projectionMatrix * linalg.matrix4_look_at(pointLight.position, pointLight.position + [?]f32{0, 0, 1}, -WORLD_UP),
		// back
		projectionMatrix * linalg.matrix4_look_at(pointLight.position, pointLight.position + [?]f32{0, 0, -1}, -WORLD_UP),
	}

	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "ViewMatrices"),
		len(viewMatrices),
		false,
		transmute([^]f32)raw_data(&viewMatrices)
	)
}

// used to create and issue a draw call
shadow_cubemap_draw :: proc(this: ^ShadowCubeMapShader, model: ^matrix[4, 4]f32, input: ^ShadowMapInput) {
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "Model"),
		1,
		false,
		raw_data(model),
	)

	if indices, ok := input.indices.(BufferView); ok {
		gl.BindBuffer(gl.ARRAY_BUFFER, input.positions.glBuffer)
		gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, input.positions.stride, uintptr(input.positions.offset))

		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, indices.glBuffer)
		gl.DrawElements(gl.TRIANGLES, i32(input.elementCount), indices.glComponentType, rawptr(uintptr(indices.offset)))
	} else {
		gl.BindBuffer(gl.ARRAY_BUFFER, input.positions.glBuffer)
		gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, input.positions.stride, uintptr(input.positions.offset))

		gl.DrawArrays(gl.TRIANGLES, 0, i32(input.elementCount))
	}
}

// to be called once after all drawing is done to undo global state
shadow_cubemap_post_draw :: proc(this: ^ShadowCubeMapShader) {
}

shadow_cubemap_destroy :: proc(this: ^ShadowCubeMapShader) {
	gl.DeleteVertexArrays(1, &this.glVAO)
	gl.DeleteProgram(this.glProgram)
}
