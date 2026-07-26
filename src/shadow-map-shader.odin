package main

import "core:fmt"
import "core:math/linalg"
import "vendor:microui"

import gl "vendor:OpenGL"

ShadowMapShader :: struct {
	glProgram: u32,
	glVAO: u32,
}

ShadowMapInput :: struct {
	elementCount: u32,
	indices: Maybe(BufferView),
	positions: BufferView,
}

// loads and compiles the shader
shadow_map_create :: proc(this: ^ShadowMapShader) {
	this.glProgram = gl.load_shaders("shaders/shadow-map.vert", "shaders/shadow-map.frag") or_else panic("Failed to load and compile shadow mapping shaders")

	gl.GenVertexArrays(1, &this.glVAO)
	gl.BindVertexArray(this.glVAO)
}

// to be called once in the beginning of the loop
shadow_map_pre_draw :: proc(this: ^ShadowMapShader, directionalLight: ^DirectionalLight) {
	gl.BindVertexArray(this.glVAO)

	gl.UseProgram(this.glProgram)

	gl.EnableVertexAttribArray(0)

	gl.Enable(gl.DEPTH_TEST)

	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "viewProjection"),
		1,
		false,
		raw_data(&directionalLight.viewProjection)
	)
}

// used to create and issue a draw call
shadow_map_draw :: proc(this: ^ShadowMapShader, model: ^matrix[4, 4]f32, input: ^ShadowMapInput) {
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "model"),
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
shadow_map_post_draw :: proc(this: ^ShadowMapShader) {
}

shadow_map_destroy :: proc(this: ^ShadowMapShader) {
	gl.DeleteVertexArrays(1, &this.glVAO)
	gl.DeleteProgram(this.glProgram)
}
