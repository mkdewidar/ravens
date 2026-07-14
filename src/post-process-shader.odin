package main

import gl "vendor:OpenGL"

PostProcessShader :: struct {
	glProgram: u32,
	glVAO: u32,

	glArrayBuffer: u32,
}

PostProcessEffect :: enum {
	None = 0,
	Greyscale = 1,
}

// loads and compiles the shader
post_process_create :: proc(this: ^PostProcessShader) {
	this.glProgram = gl.load_shaders("shaders/post-process.vert", "shaders/post-process.frag") or_else panic("Failed to load and compile post-process shaders")

	gl.GenVertexArrays(1, &this.glVAO)
	gl.BindVertexArray(this.glVAO)

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)

	gl.GenBuffers(1, &this.glArrayBuffer)
}

// to be called once in the beginning of the loop
post_process_pre_draw :: proc(this: ^PostProcessShader, effect: PostProcessEffect) {
	gl.BindVertexArray(this.glVAO)

	gl.Disable(gl.DEPTH_TEST)

	gl.UseProgram(this.glProgram)
	gl.BindBuffer(gl.ARRAY_BUFFER, this.glArrayBuffer)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 0)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 4 * size_of(f32), 2 * size_of(f32))

	gl.Uniform1i(gl.GetUniformLocation(this.glProgram, "effect"), i32(effect))
}

// used to create and issue a draw call
post_process_draw :: proc(this: ^PostProcessShader, inputTexture: u32, outputRect: struct {x, y, w, h: f32}) {
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, inputTexture)

	quadData := [?]f32 {
		// verts, should be in NDC                                 // tex coords
		outputRect.x, outputRect.y + outputRect.h,                 0, 1,
		outputRect.x, outputRect.y,                                0, 0,
		outputRect.x + outputRect.w, outputRect.y,                 1, 0,

		outputRect.x + outputRect.w, outputRect.y + outputRect.h,  1, 1,
		outputRect.x, outputRect.y + outputRect.h,                 0, 1,
		outputRect.x + outputRect.w, outputRect.y,                 1, 0,
	}
	gl.BufferData(gl.ARRAY_BUFFER, size_of(quadData), &quadData, gl.STATIC_DRAW)

	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

// to be called once after all drawing is done to undo global state
post_process_post_draw :: proc(this: ^PostProcessShader) {
}

post_process_destroy :: proc(this: ^PostProcessShader) {
	gl.DeleteBuffers(1, &this.glArrayBuffer)
	gl.DeleteVertexArrays(1, &this.glVAO)
	gl.DeleteProgram(this.glProgram)
}
