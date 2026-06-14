package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math/linalg"
import "core:strings"

import gl "vendor:OpenGL"
import "vendor:glfw"
import stb "vendor:stb/image"
import "vendor:microui"
import "vendor:cgltf"

/*
this is OpenGL's coordinate system
*/
WORLD_UP :: [?]f32{0, 1, 0}
WORLD_RIGHT :: [?]f32{1, 0, 0}
WORLD_FORWARD :: [?]f32{0, 0, -1}

// seems to be the latest OpenGL version supported on macOS
OPENGL_MAJOR_VERSION :: 4
OPENGL_MINOR_VERSION :: 1

// the viewport is kept the same size as the window using framebuffer_size_callback
WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480
WINDOW_ASPECT_RATIO :: WINDOW_WIDTH / WINDOW_HEIGHT

CAMERA_DEFAULT_POS :: [?]f32{0, 0, 5}
CAMERA_DEFAULT_FRONT :: [?]f32{0, 0, -1}

// the camera's location in the world
CameraPos: [3]f32 = CAMERA_DEFAULT_POS
// a vector pointing "forward" from the camera, make sure MouseYaw and MousePitch are
// also updated to avoid a camera jump on first movement
CameraFront: [3]f32 = CAMERA_DEFAULT_FRONT
// speed of the camera defined as a multiple of CameraFront
CAMERA_SPEED :: 0.05
MOUSE_SENSITIVITY :: 0.1
LastMouseX, LastMouseY: f64 = 0, 0
// the camera equation results in 0,0 pointing straight to the right, so this value matches
// the CAMERA_DEFAULT_FRONT direction
CameraYaw, CameraPitch: f32 = -90, 0

SettingsType :: struct {
	wireframeModeEnabled: bool,
	scenePath: string,
}
Settings := SettingsType {
	wireframeModeEnabled = false,
	scenePath = "assets/scene.gltf",
}

main :: proc() {
	glfw.SetErrorCallback(error_callback)

	if !glfw.Init() {
		panic("Failed to initialize glfw")
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, OPENGL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, OPENGL_MINOR_VERSION)
	// primarily for macOS
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Ravens", nil, nil)
	if window == nil {
		description, code := glfw.GetError()
		panic(
			fmt.tprintfln(
				"Failed to create glfw window, error: %v, description: %v",
				code,
				description,
			),
		)
	}
	defer glfw.DestroyWindow(window)

	mui := new(microui.Context)
	defer free(mui)
	microui.init(mui)
	mui.text_width = microui.default_atlas_text_width
	mui.text_height = microui.default_atlas_text_height

	glfw.MakeContextCurrent(window)
	glfw.SetCursorPosCallback(window, mouse_pos_callback)

	// this is some odin specific stuff that loads all the OpenGL functions from the windowing system
	// into the gl module, for this particular version of OpenGL
	gl.load_up_to(OPENGL_MAJOR_VERSION, OPENGL_MINOR_VERSION, glfw.gl_set_proc_address)

	glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)

	// yet another fantastic helper function for loading, compiling, and attaching shaders to this OpenGL program
	glProgram :=
		gl.load_shaders("shaders/shader.vert", "shaders/shader.frag") or_else panic(
			"Failed to load and compile shaders",
		)
	defer gl.DeleteProgram(glProgram)
	gl.UseProgram(glProgram)

	glUnlitProgram :=
		gl.load_shaders("shaders/unlit.vert", "shaders/unlit.frag") or_else panic(
			"Failed to load and compile unlit shaders",
		)
	defer gl.DeleteProgram(glUnlitProgram)

	glUIProgram :=
		gl.load_shaders("shaders/ui.vert", "shaders/ui.frag") or_else panic(
			"Failed to load and compile UI shaders",
		)
	defer gl.DeleteProgram(glUIProgram)

	// not to be confused with "vertex buffer object", this is a container telling OpenGL how to map
	// "vertex buffer objects" onto the inputs of the vertex shader, but doesn't actually store the data itself.
	vertexArrayObject: u32
	gl.GenVertexArrays(1, &vertexArrayObject)
	defer gl.DeleteVertexArrays(1, &vertexArrayObject)
	gl.BindVertexArray(vertexArrayObject)

    containerTexture := LoadTextureIntoUnit("assets/container-texture.jpg", 0)
    defer gl.DeleteTextures(1, &containerTexture)
    container2Diffuse := LoadTextureIntoUnit("assets/container2-diffuse.png", 1)
    defer gl.DeleteTextures(1, &container2Diffuse)
    container2Specular := LoadTextureIntoUnit("assets/container2-specular.png", 2)
    defer gl.DeleteTextures(1, &container2Specular)

	uiAtlasTexture: u32
	gl.GenTextures(1, &uiAtlasTexture)
	defer gl.DeleteTextures(1, &uiAtlasTexture)
	gl.ActiveTexture(gl.TEXTURE3)
	gl.BindTexture(gl.TEXTURE_2D, uiAtlasTexture)
	// temporarily allow us to specify a texture that is 1 byte per element
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RED, microui.DEFAULT_ATLAS_WIDTH, microui.DEFAULT_ATLAS_HEIGHT, 0, gl.RED, gl.UNSIGNED_BYTE, &microui.default_atlas_alpha)
	// back to the default it would be at
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 4)

	// these are just the standalone vert positions, we use an element buffer object to tell OpenGL how to draw
	// triangles out of them
	squareData := [?]f32{
		// positions      // colors       // texture coords    // normal direction
		0.5, 0.5, 0,       1, 0, 0,       1, 1,                0, 0, 1,
		0.5, -0.5, 0,      0, 1, 0,       1, 0,                0, 0, 1,
		-0.5, -0.5, 0,     0, 0, 1,       0, 0,                0, 0, 1,
		-0.5, 0.5, 0,      1, 1, 0,       0, 1,                0, 0, 1,
	}
	// these index into the verts mentioned above, telling OpenGL how to make triangles out of those vertices
	squareVertIndices := [?]u32{
		0, 1, 3,
		1, 2, 3
	}
	// not to be confused with "vertex array object", this object contains the actual vertices, but doesn't
	// describe how they are mapped to the input variables in the vertex shader.
	vertexBufferObject: u32
	gl.GenBuffers(1, &vertexBufferObject)
	defer gl.DeleteBuffers(1, &vertexBufferObject)
	gl.BindBuffer(gl.ARRAY_BUFFER, vertexBufferObject)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(squareData), &squareData, gl.STATIC_DRAW)
	elementBufferObject: u32
	gl.GenBuffers(1, &elementBufferObject)
	defer gl.DeleteBuffers(1, &elementBufferObject)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, elementBufferObject)
	gl.BufferData(
		gl.ELEMENT_ARRAY_BUFFER,
		size_of(squareVertIndices),
		&squareVertIndices,
		gl.STATIC_DRAW,
	)

	cubeData := [?]f32{
		// positions        // colors   // texture coords    // normal direction
		-0.5, -0.5, -0.5,   1, 1, 1,   0, 0,                 0, 0, -1,
		0.5, -0.5, -0.5,    1, 1, 1,   1, 0,                 0, 0, -1,
		0.5,  0.5, -0.5,    1, 1, 1,   1, 1,                 0, 0, -1,
		0.5,  0.5, -0.5,    1, 1, 1,   1, 1,                 0, 0, -1,
		-0.5,  0.5, -0.5,   1, 1, 1,   0, 1,                 0, 0, -1,
		-0.5, -0.5, -0.5,   1, 1, 1,   0, 0,                 0, 0, -1,

		-0.5, -0.5,  0.5,   1, 1, 1,   0, 0,                 0, 0, 1,
		0.5, -0.5,  0.5,    1, 1, 1,   1, 0,                 0, 0, 1,
		0.5,  0.5,  0.5,    1, 1, 1,   1, 1,                 0, 0, 1,
		0.5,  0.5,  0.5,    1, 1, 1,   1, 1,                 0, 0, 1,
		-0.5,  0.5,  0.5,   1, 1, 1,   0, 1,                 0, 0, 1,
		-0.5, -0.5,  0.5,   1, 1, 1,   0, 0,                 0, 0, 1,

		-0.5,  0.5,  0.5,   1, 1, 1,   1, 0,                 -1, 0, 0,
		-0.5,  0.5, -0.5,   1, 1, 1,   1, 1,                 -1, 0, 0,
		-0.5, -0.5, -0.5,   1, 1, 1,   0, 1,                 -1, 0, 0,
		-0.5, -0.5, -0.5,   1, 1, 1,   0, 1,                 -1, 0, 0,
		-0.5, -0.5,  0.5,   1, 1, 1,   0, 0,                 -1, 0, 0,
		-0.5,  0.5,  0.5,   1, 1, 1,   1, 0,                 -1, 0, 0,

		0.5,  0.5,  0.5,    1, 1, 1,   1, 0,                 1, 0, 0,
		0.5,  0.5, -0.5,    1, 1, 1,   1, 1,                 1, 0, 0,
		0.5, -0.5, -0.5,    1, 1, 1,   0, 1,                 1, 0, 0,
		0.5, -0.5, -0.5,    1, 1, 1,   0, 1,                 1, 0, 0,
		0.5, -0.5,  0.5,    1, 1, 1,   0, 0,                 1, 0, 0,
		0.5,  0.5,  0.5,    1, 1, 1,   1, 0,                 1, 0, 0,

		-0.5, -0.5, -0.5,   1, 1, 1,   0, 1,                 0, -1, 0,
		0.5, -0.5, -0.5,    1, 1, 1,   1, 1,                 0, -1, 0,
		0.5, -0.5,  0.5,    1, 1, 1,   1, 0,                 0, -1, 0,
		0.5, -0.5,  0.5,    1, 1, 1,   1, 0,                 0, -1, 0,
		-0.5, -0.5,  0.5,   1, 1, 1,   0, 0,                 0, -1, 0,
		-0.5, -0.5, -0.5,   1, 1, 1,   0, 1,                 0, -1, 0,

		-0.5,  0.5, -0.5,   1, 1, 1,   0, 1,                 0, 1, 0,
		0.5,  0.5, -0.5,    1, 1, 1,   1, 1,                 0, 1, 0,
		0.5,  0.5,  0.5,    1, 1, 1,   1, 0,                 0, 1, 0,
		0.5,  0.5,  0.5,    1, 1, 1,   1, 0,                 0, 1, 0,
		-0.5,  0.5,  0.5,   1, 1, 1,   0, 0,                 0, 1, 0,
		-0.5,  0.5, -0.5,   1, 1, 1,   0, 1,                 0, 1, 0,
	}
	cubeVertexBufferObject: u32
	gl.GenBuffers(1, &cubeVertexBufferObject)
	defer gl.DeleteBuffers(1, &cubeVertexBufferObject)
	gl.BindBuffer(gl.ARRAY_BUFFER, cubeVertexBufferObject)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(cubeData), &cubeData, gl.STATIC_DRAW)

	// a map of gltf buffer pointers to gl buffer IDs
	glBuffers := make(map[^cgltf.buffer]u32)
	defer delete(glBuffers)
	sceneData := LoadScene(Settings.scenePath)
	defer cgltf.free(sceneData)
	if sceneData.scene != nil {
		for buffer, i in sceneData.buffers {
			bufferId: u32
			gl.GenBuffers(1, &bufferId)
			gl.BindBuffer(gl.ARRAY_BUFFER, bufferId)
			gl.BufferData(gl.ARRAY_BUFFER, int(buffer.size), buffer.data, gl.STATIC_DRAW)

			glBuffers[&sceneData.buffers[i]] = bufferId
		}
	}
	defer {
		for _, &glBuffer in glBuffers {
			gl.DeleteBuffers(1, &glBuffer)
		}
	}
	sceneVAO: u32
	gl.GenVertexArrays(1, &sceneVAO)
	defer gl.DeleteVertexArrays(1, &sceneVAO)

	projectionMatrix := linalg.matrix4_perspective_f32(
		linalg.to_radians(f32(45)),
		WINDOW_ASPECT_RATIO,
		0.1,
		100,
	)
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(glProgram, "projection"),
		1,
		false,
		raw_data(&projectionMatrix),
	)

	fmt.printfln("Initial camera parameters:\n\tpos: %v\n\tfront: %v\n\t", CameraPos, CameraFront)

	fmt.printfln("Light parameters:")

	directLightDirection := linalg.normalize([?]f32{ 0, -1, 0 })
	gl.Uniform3fv(
		gl.GetUniformLocation(glProgram, "directLight.direction"),
		1,
		raw_data(&directLightDirection),
	)
	directLightColor := [?]f32{ 1, 1, 1 }
	gl.Uniform3fv(
		gl.GetUniformLocation(glProgram, "directLight.color"),
		1,
		raw_data(&directLightColor),
	)
	fmt.printfln("\tdirectLight\n\t\tdirection: %v\n\t\tcolor: %v", directLightDirection, directLightColor)

	pointLightPosition := [?]f32{ 0, 5, 0 }
	gl.Uniform3fv(
		gl.GetUniformLocation(glProgram, "pointLights[0].position"),
		1,
		raw_data(&pointLightPosition),
	)
	pointLightColor := [?]f32{ 0, 0, 1 }
	gl.Uniform3fv(
		gl.GetUniformLocation(glProgram, "pointLights[0].color"),
		1,
		raw_data(&pointLightColor),
	)
    gl.Uniform1f(gl.GetUniformLocation(glProgram, "pointLights[0].constantAttenuation"), 1.0)
    gl.Uniform1f(gl.GetUniformLocation(glProgram, "pointLights[0].linearAttenuation"), 0.07)
    gl.Uniform1f(gl.GetUniformLocation(glProgram, "pointLights[0].quadraticAttenuation"), 0.017)
    fmt.printfln("\tpoint light\n\t\tposition: %v\n\t\tcolor: %v", pointLightPosition, pointLightColor)

	gl.UseProgram(glUnlitProgram)
	gl.UniformMatrix4fv(
		gl.GetUniformLocation(glUnlitProgram, "projection"),
		1,
		false,
		raw_data(&projectionMatrix),
	)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	for !glfw.WindowShouldClose(window) {

		if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
			glfw.SetWindowShouldClose(window, true)
		}
		if glfw.GetKey(window, glfw.KEY_R) == glfw.PRESS {
			CameraPos = CAMERA_DEFAULT_POS
			CameraFront = CAMERA_DEFAULT_FRONT

			LastMouseX = 0
			LastMouseY = 0

			CameraYaw, CameraPitch = -90, 0
		}
		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS {
			CameraPos += (CAMERA_SPEED * CameraFront)
		}
		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS {
			// cross product gives us the third axis (horizontal), and we normalise to ensure
			// the speed is always a multiple of the same length vector
			CameraPos -=
				linalg.normalize(linalg.vector_cross3(CameraFront, WORLD_UP)) * CAMERA_SPEED
		}
		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS {
			CameraPos -= (CAMERA_SPEED * CameraFront)
		}
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS {
			// cross product gives us the third axis (horizontal), and we normalise to ensure
			// the speed is always a multiple of the same length vector
			CameraPos +=
				linalg.normalize(linalg.vector_cross3(CameraFront, WORLD_UP)) * CAMERA_SPEED
		}
		if glfw.GetKey(window, glfw.KEY_E) == glfw.PRESS {
			CameraPos += linalg.normalize(WORLD_UP) * CAMERA_SPEED
		}
		if glfw.GetKey(window, glfw.KEY_Q) == glfw.PRESS {
			CameraPos -= linalg.normalize(WORLD_UP) * CAMERA_SPEED
		}
		if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS {
			// only when the button is clicked the first time
			if (glfw.GetInputMode(window, glfw.CURSOR) != glfw.CURSOR_DISABLED) {

				glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)

				LastMouseX, LastMouseY = glfw.GetCursorPos(window)
			}
		}
		if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_RIGHT) == glfw.RELEASE {
			// just to prevent churn of constantly setting the input mode
			if (glfw.GetInputMode(window, glfw.CURSOR) != glfw.CURSOR_NORMAL) {
				glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_NORMAL)
			}
		}

		cursorX, cursorY := glfw.GetCursorPos(window)
		microui.input_mouse_move(mui, i32(cursorX), i32(cursorY))
		if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS {
			if microui.Mouse.LEFT not_in mui.mouse_down_bits {
				microui.input_mouse_down(mui, i32(cursorX), i32(cursorY), microui.Mouse.LEFT)
			}
		}
		if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.RELEASE {
			// the mouse button defaults to being released, so only process a release if it following a press
			if microui.Mouse.LEFT in mui.mouse_down_bits {
				microui.input_mouse_up(mui, i32(cursorX), i32(cursorY), microui.Mouse.LEFT)
			}
		}

		microui.begin(mui)
		if microui.begin_window(mui, "Settings", microui.Rect { 5, 5, 200, 100 }) {
			microui.checkbox(mui, "Wireframe Mode", &Settings.wireframeModeEnabled)

			microui.end_window(mui)
		}
		microui.end(mui)

		gl.ClearColor(0.3, 0.4, 0.5, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		gl.PolygonMode(gl.FRONT_AND_BACK, Settings.wireframeModeEnabled ? gl.LINE : gl.FILL)

		viewMatrix := linalg.matrix4_look_at(
			CameraPos,
			CameraPos + CameraFront,
			WORLD_UP
		)

		// gltf scene rendering
		gl.UseProgram(glUnlitProgram)
		gl.BindVertexArray(sceneVAO)
		gl.EnableVertexAttribArray(0)

		gl.VertexAttrib3f(1, 0.5, 0.5, 0.5)

		gl.UniformMatrix4fv(
			gl.GetUniformLocation(glUnlitProgram, "view"),
			1,
			false,
			raw_data(&viewMatrix),
		)

		modelMatrix := linalg.matrix4_translate_f32({0, 0, 5}) * 1
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(glUnlitProgram, "model"),
			1,
			false,
			raw_data(&modelMatrix),
		)

		for node in sceneData.scene.nodes {
			if node.mesh == nil {
				// for now we only iterate and draw root level meshes
			}

			positionsAccessor := node.mesh.primitives[0].attributes[0].data
			positionsGLBuffer := glBuffers[positionsAccessor.buffer_view.buffer]
			gl.BindBuffer(gl.ARRAY_BUFFER, positionsGLBuffer)
			gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 0, uintptr(positionsAccessor.buffer_view.offset))

			elementsAccessor := node.mesh.primitives[0].indices
			elementsGLBuffer := glBuffers[node.mesh.primitives[0].indices.buffer_view.buffer]
			gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, elementsGLBuffer)

			gl.DrawElements(gl.TRIANGLES, i32(elementsAccessor.count), gl.UNSIGNED_SHORT, nil)
		}

		// back to the VAO we use for the rest of the program
		gl.BindVertexArray(vertexArrayObject)

		// enable the scene program and enable the vertex shaders on it
		gl.UseProgram(glProgram)
		gl.EnableVertexAttribArray(0)
		gl.EnableVertexAttribArray(1)
		gl.EnableVertexAttribArray(2)
		gl.EnableVertexAttribArray(3)
		gl.Enable(gl.DEPTH_TEST)

		gl.UniformMatrix4fv(
			gl.GetUniformLocation(glProgram, "view"),
			1,
			false,
			raw_data(&viewMatrix),
		)

		gl.Uniform3fv(
			gl.GetUniformLocation(glProgram, "viewPos"),
			1,
			raw_data(&CameraPos),
		)

		gl.Uniform3fv(gl.GetUniformLocation(glProgram, "objectMaterial.emissiveColor"), 1, raw_data(&[?]f32{0, 0, 0}))
		gl.Uniform3fv(gl.GetUniformLocation(glProgram, "objectMaterial.specularColor"), 1, raw_data(&[?]f32{0, 0, 0}))
        // by default we use the first container texture and no specular
        gl.Uniform1f(gl.GetUniformLocation(glProgram, "objectMaterial.specularity"), 0)
        gl.Uniform1i(gl.GetUniformLocation(glProgram, "objectMaterial.useSpecularMap"), 0)
        gl.Uniform1i(gl.GetUniformLocation(glProgram, "objectMaterial.diffuseTex"), 0)

		// using time as a source for the angle allows it to simulate a frame rate independent rotation
		// in contrast with just adding a fixed value each frame which would change how quick it rotates depending on frame rate
		// doing the operations in this order results in a neat rotate around a point effect

		// now we draw the square
		gl.BindBuffer(gl.ARRAY_BUFFER, vertexBufferObject)
		modelMatrix =
			// rotates around the z at a rate of 50 degrees per second
			linalg.matrix4_rotate_f32(linalg.to_radians(f32(glfw.GetTime()) * 50), {0, 0, 1}) *
			// move it up so its above the cube
			linalg.matrix4_translate_f32({0, 1.5, 0}) *
			// put the square flat on its side
			linalg.matrix4_rotate_f32(linalg.to_radians(f32(90)), {1, 0, 0})
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(glProgram, "model"),
			1,
			false,
			raw_data(&modelMatrix),
		)
		gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 0)
		gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 3 * size_of(f32))
		gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 6 * size_of(f32))
		gl.VertexAttribPointer(3, 3, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 8 * size_of(f32))
		gl.DrawElements(gl.TRIANGLES, len(squareVertIndices), gl.UNSIGNED_INT, nil)

		// now we draw the central spinning cube
		gl.BindBuffer(gl.ARRAY_BUFFER, cubeVertexBufferObject)
		modelMatrix =
			linalg.matrix4_rotate_f32(linalg.to_radians(f32(-55)), {1, 0, 0}) *
			linalg.matrix4_rotate_f32(linalg.to_radians(f32(glfw.GetTime()) * 50), {0.5, 1, 0}) *
			1
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(glProgram, "model"),
			1,
			false,
			raw_data(&modelMatrix),
		)
        gl.Uniform1f(gl.GetUniformLocation(glProgram, "objectMaterial.specularity"), 16)
		// we must redo this so it points to the new buffer
		gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 0)
		gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 3 * size_of(f32))
		gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 6 * size_of(f32))
		gl.VertexAttribPointer(3, 3, gl.FLOAT, gl.FALSE, 11 * size_of(f32), 8 * size_of(f32))
		gl.DrawArrays(gl.TRIANGLES, 0, 36)

		// now we draw some random cubes around the scene
		for i in 0..<10 {
			modelMatrix =
				linalg.matrix4_translate_f32({f32(3 * (i % 5)) - 5, f32(3 * (i / 5)) + 2.5, 0}) *
				linalg.matrix4_rotate_f32(linalg.to_radians(f32(i * 20)), {1, 0.3, 0.5}) *
				1
			gl.UniformMatrix4fv(
				gl.GetUniformLocation(glProgram, "model"),
				1,
				false,
				raw_data(&modelMatrix),
			)
            gl.Uniform1f(gl.GetUniformLocation(glProgram, "objectMaterial.specularity"), 32)
            gl.Uniform1i(gl.GetUniformLocation(glProgram, "objectMaterial.useSpecularMap"), 1)
            gl.Uniform1i(gl.GetUniformLocation(glProgram, "objectMaterial.diffuseTex"), 1)
            gl.Uniform1i(gl.GetUniformLocation(glProgram, "objectMaterial.specularTex"), 2)
			gl.DrawArrays(gl.TRIANGLES, 0, 36)
		}

		// now we draw the point light as a small cube
		modelMatrix =
			linalg.matrix4_translate_f32(pointLightPosition) *
			linalg.matrix4_scale_f32({0.1, 0.1, 0.1}) *
			1
		gl.UniformMatrix4fv(
			gl.GetUniformLocation(glProgram, "model"),
			1,
			false,
			raw_data(&modelMatrix),
		)
		gl.Uniform3fv(gl.GetUniformLocation(glProgram, "objectMaterial.emissiveColor"), 1, raw_data(&pointLightColor))
		gl.DrawArrays(gl.TRIANGLES, 0, 36)

		// just to make sure next program only has the relevant attributes open which makes debugging slightly easier
		gl.DisableVertexAttribArray(0)
		gl.DisableVertexAttribArray(1)
		gl.DisableVertexAttribArray(2)
		gl.DisableVertexAttribArray(3)

		// UI rendering
		gl.UseProgram(glUIProgram)
		{
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

			gl.EnableVertexAttribArray(0)
			defer gl.DisableVertexAttribArray(0)
			gl.EnableVertexAttribArray(1)
			defer gl.DisableVertexAttribArray(1)
			gl.EnableVertexAttribArray(2)
			defer gl.DisableVertexAttribArray(2)

			gl.Disable(gl.DEPTH_TEST)

			windowWidth, windowHeight := glfw.GetFramebufferSize(window)
			uiProjectionMatrix := linalg.matrix_ortho3d_f32(0, f32(windowWidth), f32(windowHeight), 0, -1, 1)
			gl.Uniform1i(gl.GetUniformLocation(glUIProgram, "atlas"), 3)
			gl.UniformMatrix4fv(
				gl.GetUniformLocation(glUIProgram, "projection"),
				1,
				false,
				raw_data(&uiProjectionMatrix)
			)
			muiCommand : ^microui.Command
			for commandType in microui.next_command_iterator(mui, &muiCommand) {
				#partial switch command in commandType {
				case ^microui.Command_Rect:
					UIDrawTexturedQuad(
						command.rect,
						microui.default_atlas[microui.DEFAULT_ATLAS_WHITE],
						command.color
					)
				case ^microui.Command_Text:
					characterRect := microui.Rect{ command.pos.x, command.pos.y, 0, 0 }

					for charRune in command.str {
						atlasRect := microui.default_atlas[microui.DEFAULT_ATLAS_FONT + min(int(charRune), 127)]
						characterRect.w = atlasRect.w
						characterRect.h = atlasRect.h

						UIDrawTexturedQuad(
							characterRect,
							atlasRect,
							command.color
						)

						characterRect.x += characterRect.w
					}
				case ^microui.Command_Icon:
					UIDrawTexturedQuad(
						command.rect,
						microui.default_atlas[command.id],
						command.color
					)
				}
			}
		}

		glfw.SwapBuffers(window)
		glfw.PollEvents()
	}
}

/*
Error callback for glfw
*/
@(private = "file")
error_callback :: proc "c" (code: c.int, description: cstring) {
	// glfw will be calling us from C, so won't have the Odin context we need for
	// formatting to work, so we load it here
	context = runtime.default_context()
	fmt.printfln("GLFW Error: %v, description: %v", code, description)
}

/*
Callback that glfw uses to keep OpenGL's viewport size up to date with the window size
*/
@(private = "file")
framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	gl.Viewport(0, 0, width, height)
}

@(private = "file")
mouse_pos_callback :: proc "c" (window: glfw.WindowHandle, x, y: c.double) {
	context = runtime.default_context()

	if glfw.GetInputMode(window, glfw.CURSOR) == glfw.CURSOR_NORMAL {
		return
	}

	changeInX := f32(x - LastMouseX)
	changeInY := f32(LastMouseY - y)

	LastMouseX = x
	LastMouseY = y

	CameraYaw += changeInX * MOUSE_SENSITIVITY
	CameraPitch += changeInY * MOUSE_SENSITIVITY
	// prevent up/down camera from wrapping around
	if CameraPitch > 89 {
		CameraPitch = 89
	}
	if CameraPitch < -89 {
		CameraPitch = -89
	}

	CameraFront = linalg.vector_normalize(
		[?]f32 {
			linalg.cos(linalg.to_radians(CameraYaw)) * linalg.cos(linalg.to_radians(CameraPitch)),
			linalg.sin(linalg.to_radians(CameraPitch)),
			linalg.sin(linalg.to_radians(CameraYaw)) * linalg.cos(linalg.to_radians(CameraPitch)),
		},
	)
}

LoadTextureIntoUnit :: proc(filename: string, unit: u32) -> u32 {
    textureWidth, textureHeight, textureChannelCount: c.int
    filenameCString := strings.clone_to_cstring(filename)
    defer delete(filenameCString)
    textureBytes := stb.load(
        filenameCString,
        &textureWidth,
        &textureHeight,
        &textureChannelCount,
        3, // to match the hard coded RGB format we'll use below
    )
    if textureBytes == nil {
        panic(fmt.tprintf("Failed to load texture %s", stb.failure_reason()))
    }
    defer stb.image_free(textureBytes)

    glTexture: u32
    gl.GenTextures(1, &glTexture)

    gl.ActiveTexture(gl.TEXTURE0 + unit)
    gl.BindTexture(gl.TEXTURE_2D, glTexture)

    // how opengl should handle going out of bounds on the texture's 0 - 1.0 coordinates
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    // how opengl should sample the texture
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGB,
        textureWidth,
        textureHeight,
        0,
        gl.RGB,
        gl.UNSIGNED_BYTE,
        textureBytes,
    )
    gl.GenerateMipmap(gl.TEXTURE_2D)

    return glTexture
}

UIDrawTexturedQuad :: proc(rect, textureRect: microui.Rect, color: microui.Color) {
	quadBuffer: u32
	gl.GenBuffers(1, &quadBuffer)
	defer gl.DeleteBuffers(1, &quadBuffer)

	gl.BindBuffer(gl.ARRAY_BUFFER, quadBuffer)

	x, y, width, height := f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)
	texX, texY, texWidth, texHeight := f32(textureRect.x) / microui.DEFAULT_ATLAS_WIDTH, f32(textureRect.y) / microui.DEFAULT_ATLAS_HEIGHT, f32(textureRect.w) / microui.DEFAULT_ATLAS_WIDTH, f32(textureRect.h) / microui.DEFAULT_ATLAS_HEIGHT
	r, g, b, a := f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255

	quadData := [?]f32 {
		// verts                 // color       // tex coords
		x, y,                    r, g, b, a,    texX, texY,
		x + width, y,            r, g, b, a,    texX + texWidth, texY,
		x, y + height,           r, g, b, a,    texX, texY + texHeight,

		x + width, y,            r, g, b, a,    texX + texWidth, texY,
		x + width, y + height,   r, g, b, a,    texX + texWidth, texY + texHeight,
		x, y + height,           r, g, b, a,    texX, texY + texHeight,
	}
	gl.BufferData(gl.ARRAY_BUFFER, size_of(quadData), &quadData, gl.STATIC_DRAW)

	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0)
	gl.VertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 2 * size_of(f32))
	gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 6 * size_of(f32))

	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

LoadScene :: proc(path: string) -> ^cgltf.data {
	scenePathCString := strings.clone_to_cstring(Settings.scenePath)
	defer delete(scenePathCString)

	sceneData, sceneParseResult := cgltf.parse_file(cgltf.options{}, scenePathCString)
	if sceneParseResult != .success {
		fmt.eprintfln("Failed to load scene file, returning empty scene")
		return new(cgltf.data)
	}

	sceneParseResult = cgltf.load_buffers(cgltf.options{}, sceneData, nil)
	if sceneParseResult != .success {
		fmt.eprintfln("Failed to load scene buffers, returning empty scene")
		cgltf.free(sceneData)
		return new(cgltf.data)
	}

	return sceneData
}