package main

import gl "vendor:OpenGL"

SkyboxShader :: struct {
	glProgram: u32,
	glVAO: u32,

	glArrayBuffer: u32,
}

// loads and compiles the shader
skybox_create :: proc(this: ^SkyboxShader) {
	this.glProgram = gl.load_shaders("shaders/skybox.vert", "shaders/skybox.frag") or_else panic("Failed to load and compile skybox shaders")

	gl.GenVertexArrays(1, &this.glVAO)
	gl.BindVertexArray(this.glVAO)

	gl.EnableVertexAttribArray(0)

	gl.GenBuffers(1, &this.glArrayBuffer)

	gl.BindBuffer(gl.ARRAY_BUFFER, this.glArrayBuffer)
	quadData := [?]f32 {
		// verts, in global coordinates
		-1,  1, -1,
		-1, -1, -1,
		1, -1, -1,
		1, -1, -1,
		1,  1, -1,
		-1,  1, -1,

		-1, -1,  1,
		-1, -1, -1,
		-1,  1, -1,
		-1,  1, -1,
		-1,  1,  1,
		-1, -1,  1,

		1, -1, -1,
		1, -1,  1,
		1,  1,  1,
		1,  1,  1,
		1,  1, -1,
		1, -1, -1,

		-1, -1,  1,
		-1,  1,  1,
		1,  1,  1,
		1,  1,  1,
		1, -1,  1,
		-1, -1,  1,

		-1,  1, -1,
		1,  1, -1,
		1,  1,  1,
		1,  1,  1,
		-1,  1,  1,
		-1,  1, -1,

		-1, -1, -1,
		-1, -1,  1,
		1, -1, -1,
		1, -1, -1,
		-1, -1,  1,
		1, -1,  1
	}
	gl.BufferData(gl.ARRAY_BUFFER, size_of(quadData), &quadData, gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), 0)
}

// to be called once in the beginning of the loop
skybox_pre_draw :: proc(this: ^SkyboxShader, view, projection: ^matrix[4, 4]f32) {
	gl.BindVertexArray(this.glVAO)

	gl.UseProgram(this.glProgram)

	gl.Enable(gl.DEPTH_TEST)
	gl.DepthFunc(gl.LEQUAL)

	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "projection"),
		1,
		false,
		raw_data(projection),
	)
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "view"),
		1,
		false,
		raw_data(view),
	)
}

// used to create and issue a draw call
skybox_draw :: proc(this: ^SkyboxShader, glCubemap: u32) {
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, glCubemap)

	gl.DrawArrays(gl.TRIANGLES, 0, 36)
}

// to be called once after all drawing is done to undo global state
skybox_post_draw :: proc(this: ^SkyboxShader) {
	gl.Disable(gl.DEPTH_TEST)
	gl.DepthFunc(gl.LESS)
}

skybox_destroy :: proc(this: ^SkyboxShader) {
	gl.DeleteBuffers(1, &this.glArrayBuffer)
	gl.DeleteVertexArrays(1, &this.glVAO)
	gl.DeleteProgram(this.glProgram)
}
