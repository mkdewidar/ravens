package main

import "core:fmt"
import "core:math/linalg"

import gl "vendor:OpenGL"

BufferView :: struct {
	glBuffer: u32,
	glComponentType: u32,
	stride: i32,
	offset: uint,
}

PhongShader :: struct {
	glProgram: u32,
	glVAO: u32,

	// the GL ID of textures which are solid color and used as placeholders when we don't need a texture
	glWhiteTexture: u32,

	pointLightPosition: [3]f32,
	pointLightColor: [3]f32,
}

PhongShaderInput :: struct {
	elementCount: u32,
	indices: Maybe(BufferView),
	positions: Maybe(BufferView),
	colors: Maybe(BufferView),
	texcoords: Maybe(BufferView),
	normals: Maybe(BufferView),

	hasMaterial: bool,
	material: struct {
		emissiveColor: [3]f32,
		glDiffuseTexture: u32,
		specularity: f32,
		specularColor: [3]f32,
		glSpecularTexture: u32,
	}
}

// loads and compiles the shader
phong_create :: proc(this: ^PhongShader) {
	// yet another fantastic helper function for loading, compiling, and attaching shaders to this OpenGL program
	this.glProgram = gl.load_shaders("shaders/phong.vert", "shaders/phong.frag") or_else panic(
		"Failed to load and compile shaders",
	)

	gl.GenVertexArrays(1, &this.glVAO)

	gl.UseProgram(this.glProgram)

	// just a 1x1 white texture to use when there is no diffuse on the object
	gl.GenTextures(1, &this.glWhiteTexture)
	defer gl.DeleteTextures(1, &this.glWhiteTexture)
	gl.BindTexture(gl.TEXTURE_2D, this.glWhiteTexture)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.FLOAT, raw_data([]f32{1.0, 1.0, 1.0, 1.0}))

	fmt.printfln("Initial camera parameters:\n\tpos: %v\n\tfront: %v\n\t", CameraPos, CameraFront)

	fmt.printfln("Light parameters:")

	directLightDirection := linalg.normalize([?]f32{ 0, -1, 0 })
	gl.Uniform3fv(
		gl.GetUniformLocation(this.glProgram, "directLight.direction"),
		1,
		raw_data(&directLightDirection),
	)
	directLightColor := [?]f32{ 1, 1, 1 }
	gl.Uniform3fv(
		gl.GetUniformLocation(this.glProgram, "directLight.color"),
		1,
		raw_data(&directLightColor),
	)
	fmt.printfln("\tdirectLight\n\t\tdirection: %v\n\t\tcolor: %v", directLightDirection, directLightColor)

	this.pointLightPosition = [?]f32{ 0, 5, 0 }
	gl.Uniform3fv(
		gl.GetUniformLocation(this.glProgram, "pointLights[0].position"),
		1,
		raw_data(&this.pointLightPosition),
	)
	this.pointLightColor = [?]f32{ 0, 0, 1 }
	gl.Uniform3fv(
		gl.GetUniformLocation(this.glProgram, "pointLights[0].color"),
		1,
		raw_data(&this.pointLightColor),
	)
    gl.Uniform1f(gl.GetUniformLocation(this.glProgram, "pointLights[0].constantAttenuation"), 1.0)
    gl.Uniform1f(gl.GetUniformLocation(this.glProgram, "pointLights[0].linearAttenuation"), 0.07)
    gl.Uniform1f(gl.GetUniformLocation(this.glProgram, "pointLights[0].quadraticAttenuation"), 0.017)
    fmt.printfln("\tpoint light\n\t\tposition: %v\n\t\tcolor: %v", this.pointLightPosition, this.pointLightColor)
}

// to be called once in the beginning of the loop
phong_pre_draw :: proc(this: ^PhongShader, view, projection: ^matrix[4, 4]f32, viewPos: ^[3]f32) {
	gl.BindVertexArray(this.glVAO)

	gl.UseProgram(this.glProgram)

	gl.Enable(gl.DEPTH_TEST)

	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "view"),
		1,
		false,
		raw_data(view),
	)
	gl.Uniform3fv(
		gl.GetUniformLocation(this.glProgram, "viewPos"),
		1,
		raw_data(viewPos),
	)
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "projection"),
		1,
		false,
		raw_data(projection),
	)
}

// used to create and issue a draw call
phong_draw :: proc(this: ^PhongShader, model: ^matrix[4, 4]f32, input: ^PhongShaderInput) {
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(this.glProgram, "model"),
		1,
		false,
		raw_data(model),
	)

	if positions, isSet := input.positions.(BufferView); isSet {
		gl.EnableVertexAttribArray(0)

		gl.BindBuffer(gl.ARRAY_BUFFER, positions.glBuffer)
		gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, positions.stride, uintptr(positions.offset))
	} else {
		gl.DisableVertexAttribArray(0)
		gl.VertexAttrib3f(0, 0, 0, 0)
	}

	if colors, isSet := input.colors.(BufferView); isSet {
		gl.EnableVertexAttribArray(1)

		gl.BindBuffer(gl.ARRAY_BUFFER, colors.glBuffer)
		gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, colors.stride, uintptr(colors.offset))
	} else {
		gl.DisableVertexAttribArray(1)
		gl.VertexAttrib3f(1, 1, 1, 1)
	}

	if texcoords, isSet := input.texcoords.(BufferView); isSet {
		gl.EnableVertexAttribArray(2)

		gl.BindBuffer(gl.ARRAY_BUFFER, texcoords.glBuffer)
		gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, texcoords.stride, uintptr(texcoords.offset))
	} else {
		gl.DisableVertexAttribArray(2)
		gl.VertexAttrib2f(2, 0, 0)
	}

	if normals, isSet := input.normals.(BufferView); isSet {
		gl.EnableVertexAttribArray(3)

		gl.BindBuffer(gl.ARRAY_BUFFER, normals.glBuffer)
		gl.VertexAttribPointer(3, 3, gl.FLOAT, gl.FALSE, normals.stride, uintptr(normals.offset))
	} else {
		gl.DisableVertexAttribArray(3)
		gl.VertexAttrib3f(3, 0, 0, 0)
	}

	// defaults for material
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, this.glWhiteTexture)
	// no emissive
	gl.Uniform3fv(gl.GetUniformLocation(this.glProgram, "objectMaterial.emissiveColor"), 1, raw_data(&[?]f32{0, 0, 0}))
	// pure white for diffuse
	gl.Uniform1i(gl.GetUniformLocation(this.glProgram, "objectMaterial.diffuseTex"), 0)
	// no specularity
	gl.Uniform1f(gl.GetUniformLocation(this.glProgram, "objectMaterial.specularity"), 0)
	gl.Uniform3fv(gl.GetUniformLocation(this.glProgram, "objectMaterial.specularColor"), 1, raw_data(&[?]f32{0, 0, 0}))
	gl.Uniform1i(gl.GetUniformLocation(this.glProgram, "objectMaterial.useSpecularMap"), 0)
	// when there is one and specular is used, it'll be using unit 1
	gl.Uniform1i(gl.GetUniformLocation(this.glProgram, "objectMaterial.specularTex"), 1)

	if input.hasMaterial {
		gl.Uniform3fv(gl.GetUniformLocation(this.glProgram, "objectMaterial.emissiveColor"), 1, raw_data(&input.material.emissiveColor))

		if input.material.glDiffuseTexture != 0 {
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, input.material.glDiffuseTexture)
		}

		gl.Uniform1f(gl.GetUniformLocation(this.glProgram, "objectMaterial.specularity"), input.material.specularity * 32)
		gl.Uniform3fv(gl.GetUniformLocation(this.glProgram, "objectMaterial.specularColor"), 1, raw_data(&input.material.specularColor))

		if input.material.glSpecularTexture != 0 {
			gl.ActiveTexture(gl.TEXTURE1)
			gl.BindTexture(gl.TEXTURE_2D, input.material.glSpecularTexture)

			gl.Uniform1i(gl.GetUniformLocation(this.glProgram, "objectMaterial.useSpecularMap"), 1)
		}
	}

	if indices, isSet := input.indices.(BufferView); isSet {
		gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, indices.glBuffer)

		gl.DrawElements(gl.TRIANGLES, i32(input.elementCount), indices.glComponentType, rawptr(uintptr(indices.offset)))
	} else if input.positions != nil {
		gl.DrawArrays(gl.TRIANGLES, 0, i32(input.elementCount))
	}
}

// to be called once after all drawing is done to undo global state
phong_post_draw :: proc(this: ^PhongShader) {
	gl.Disable(gl.DEPTH_TEST)
}

phong_destroy :: proc(this: ^PhongShader) {
	gl.DeleteVertexArrays(1, &this.glVAO)
	gl.DeleteProgram(this.glProgram)
}
