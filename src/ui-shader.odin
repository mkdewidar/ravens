package main

import "core:fmt"
import "core:math/linalg"
import "vendor:microui"

import gl "vendor:OpenGL"

UIShader :: struct {
	glProgram: u32,
	glVAO: u32,

	glAtlasTexture: u32
}

// loads and compiles the shader
ui_create :: proc(this: ^UIShader) {
	this.glProgram = gl.load_shaders("shaders/ui.vert", "shaders/ui.frag") or_else panic("Failed to load and compile UI shaders")

	gl.GenVertexArrays(1, &this.glVAO)
	gl.BindVertexArray(this.glVAO)

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.EnableVertexAttribArray(2)

	gl.GenTextures(1, &this.glAtlasTexture)
	gl.BindTexture(gl.TEXTURE_2D, this.glAtlasTexture)
	// temporarily allow us to specify a texture that is 1 byte per element
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RED, microui.DEFAULT_ATLAS_WIDTH, microui.DEFAULT_ATLAS_HEIGHT, 0, gl.RED, gl.UNSIGNED_BYTE, &microui.default_atlas_alpha)
	// back to the default it would be at
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 4)
}

// to be called once in the beginning of the loop
ui_pre_draw :: proc(this: ^UIShader, width, height: f32) {
	gl.BindVertexArray(this.glVAO)

	gl.UseProgram(this.glProgram)

	gl.Disable(gl.DEPTH_TEST)

	// for the UI, we use a coordinate system where origin is top left, x grows to the right and y grows up
	uiProjectionMatrix := linalg.matrix_ortho3d_f32(0, width, height, 0, -1, 1)

	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, this.glAtlasTexture)

	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "projection"),
		1,
		false,
		raw_data(&uiProjectionMatrix)
	)
}

// used to create and issue a draw call

ui_draw :: proc(this: ^UIShader, rect, textureRect: microui.Rect, color: microui.Color) {
	quadBuffer: u32
	gl.GenBuffers(1, &quadBuffer)
	defer gl.DeleteBuffers(1, &quadBuffer)

	gl.BindBuffer(gl.ARRAY_BUFFER, quadBuffer)

	x, y, width, height := f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)
	texX, texY, texWidth, texHeight := f32(textureRect.x) / microui.DEFAULT_ATLAS_WIDTH, f32(textureRect.y) / microui.DEFAULT_ATLAS_HEIGHT, f32(textureRect.w) / microui.DEFAULT_ATLAS_WIDTH, f32(textureRect.h) / microui.DEFAULT_ATLAS_HEIGHT
	r, g, b, a := f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255

	// in counter clockwise order
	quadData := [?]f32 {
		// verts                 // color       // tex coords
		x, y + height,           r, g, b, a,    texX, texY + texHeight,
		x + width, y,            r, g, b, a,    texX + texWidth, texY,
		x, y,                    r, g, b, a,    texX, texY,

		x + width, y + height,   r, g, b, a,    texX + texWidth, texY + texHeight,
		x + width, y,            r, g, b, a,    texX + texWidth, texY,
		x, y + height,           r, g, b, a,    texX, texY + texHeight,
	}
	gl.BufferData(gl.ARRAY_BUFFER, size_of(quadData), &quadData, gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0)
	gl.VertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 2 * size_of(f32))
	gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 6 * size_of(f32))

	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

// to be called once after all drawing is done to undo global state
ui_post_draw :: proc(this: ^UIShader) {
}

ui_destroy :: proc(this: ^UIShader) {
	gl.DeleteTextures(1, &this.glAtlasTexture)
	gl.DeleteVertexArrays(1, &this.glVAO)
	gl.DeleteProgram(this.glProgram)
}
