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
import slice "core:slice"
import filepath "core:path/filepath"

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

RENDER_WIDTH :: WINDOW_WIDTH
RENDER_HEIGHT :: WINDOW_HEIGHT

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
	postProcessEffect: PostProcessEffect,
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

	glFirstPassFramebuffer, glFirstPassColorBuffer, glFirstPassDepthBuffer: u32
	gl.GenFramebuffers(1, &glFirstPassFramebuffer)
	defer gl.DeleteFramebuffers(1, &glFirstPassFramebuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, glFirstPassFramebuffer)

	gl.GenTextures(1, &glFirstPassColorBuffer)
	defer gl.DeleteTextures(1, &glFirstPassColorBuffer)
	gl.BindTexture(gl.TEXTURE_2D, glFirstPassColorBuffer)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, RENDER_WIDTH, RENDER_HEIGHT, 0, gl.RGB, gl.UNSIGNED_BYTE, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, glFirstPassColorBuffer, 0)

	gl.GenRenderbuffers(1, &glFirstPassDepthBuffer)
	defer gl.DeleteRenderbuffers(1, &glFirstPassDepthBuffer)
	gl.BindRenderbuffer(gl.RENDERBUFFER, glFirstPassDepthBuffer)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, RENDER_WIDTH, RENDER_HEIGHT)
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, glFirstPassDepthBuffer)

	// a map of gltf buffer pointers to gl buffer IDs
	glBuffers := make(map[^cgltf.buffer]u32)
	defer delete(glBuffers)
	// a map of gltf texture pointers to gl texture IDs
	glTextures := make(map[^cgltf.texture]u32)
	defer delete(glTextures)
	sceneData := scene_load(Settings.scenePath, &glBuffers, &glTextures)
	defer scene_destroy(sceneData, &glBuffers, &glTextures)

	glSkyboxCubemap := load_cubemap(Settings.scenePath, "skybox/right.jpg", "skybox/left.jpg", "skybox/top.jpg", "skybox/bottom.jpg", "skybox/front.jpg", "skybox/back.jpg")
	defer gl.DeleteTextures(1, &glSkyboxCubemap)

	skyboxShader := SkyboxShader{}
	skybox_create(&skyboxShader)
	defer skybox_destroy(&skyboxShader)

	phongShader := PhongShader{}
	phong_create(&phongShader)
	defer phong_destroy(&phongShader)

	postProcessShader := PostProcessShader{}
	post_process_create(&postProcessShader)
	defer post_process_destroy(&postProcessShader)

	uiShader := UIShader{}
	ui_create(&uiShader)
	defer ui_destroy(&uiShader)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.Enable(gl.CULL_FACE)
	gl.FrontFace(gl.CCW)
	gl.CullFace(gl.BACK)

	for !glfw.WindowShouldClose(window) {
		free_all(context.temp_allocator)

		process_input(window, mui)

		projectionMatrix := linalg.matrix4_perspective_f32(
			linalg.to_radians(f32(45)),
			WINDOW_ASPECT_RATIO,
			0.1,
			100,
		)
		viewMatrix := linalg.matrix4_look_at(
			CameraPos,
			CameraPos + CameraFront,
			WORLD_UP
		)
		modelMatrix: matrix[4, 4]f32

		if (Settings.postProcessEffect != .None) {
			gl.BindFramebuffer(gl.FRAMEBUFFER, glFirstPassFramebuffer)
		} else {
			gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		}
		gl.ClearColor(0.3, 0.4, 0.5, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		skybox_pre_draw(&skyboxShader, &viewMatrix, &projectionMatrix)
		skybox_draw(&skyboxShader, glSkyboxCubemap)
		skybox_post_draw(&skyboxShader)

		gl.PolygonMode(gl.FRONT_AND_BACK, Settings.wireframeModeEnabled ? gl.LINE : gl.FILL)
		phong_pre_draw(&phongShader, &viewMatrix, &projectionMatrix, &CameraPos)
		for node in sceneData.scene.nodes {
			if node.mesh == nil {
				// for now ignoring nested nodes, root ones only
				continue
			}

			if node.has_matrix {
			// the order of elements in gltf is the same as the order that Odin stores matrices
				modelMatrix = transmute(matrix[4, 4]f32)node.matrix_
			} else {
				modelMatrix = linalg.matrix4_from_trs(
					node.has_translation ? node.translation : 0,
					node.has_rotation ? transmute(quaternion128)node.rotation : linalg.QUATERNIONF32_IDENTITY,
					node.has_scale ? node.scale : 1,
				)
			}

			// objects that I want to handle specially, in the end this should all be in the scene description and data driven
			// using time as a source for the angle allows it to simulate a frame rate independent rotation
			// in contrast with just adding a fixed value each frame which would change how quick it rotates depending on frame rate
			// doing the operations in this order results in a neat rotate around a point effect
			switch node.name {
			case "square":
				modelMatrix =
					// rotates around the z at a rate of 50 degrees per second
					linalg.matrix4_rotate_f32(linalg.to_radians(f32(glfw.GetTime()) * 50), {0, 0, 1}) *
					// move it up so its above the cube
					linalg.matrix4_translate_f32({0, 1.5, 0}) *
					// put the square flat on its side
					linalg.matrix4_rotate_f32(linalg.to_radians(f32(90)), {1, 0, 0}) *
					1
			case "cube":
				modelMatrix =
					linalg.matrix4_rotate_f32(linalg.to_radians(f32(-55)), {1, 0, 0}) *
					linalg.matrix4_rotate_f32(linalg.to_radians(f32(glfw.GetTime()) * 50), {0.5, 1, 0}) *
					1
			case "emissive cube":
				// for this cube we override the position and color to match the point light
				modelMatrix =
					linalg.matrix4_translate_f32(phongShader.pointLightPosition) *
					linalg.matrix4_scale_f32({0.1, 0.1, 0.1}) *
					1
				node.mesh.primitives[0].material.emissive_factor = phongShader.pointLightColor
			}

			input := PhongShaderInput{}
			fill_draw_input(&glBuffers, &glTextures, &input, &node.mesh.primitives[0])
			phong_draw(&phongShader, &modelMatrix, &input)
		}
		phong_post_draw(&phongShader)
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

		if (Settings.postProcessEffect != .None) {
			// post processing
			gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
			gl.ClearColor(0.3, 0.4, 0.5, 1.0)
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

			post_process_pre_draw(&postProcessShader, Settings.postProcessEffect)
			post_process_draw(&postProcessShader, glFirstPassColorBuffer, {-1, -1, 2, 2})
			post_process_post_draw(&postProcessShader)
		}

		// UI rendering
		{
			windowWidth, windowHeight := glfw.GetWindowSize(window)
			ui_pre_draw(&uiShader, f32(windowWidth), f32(windowHeight))

			muiCommand : ^microui.Command
			for commandType in microui.next_command_iterator(mui, &muiCommand) {
				#partial switch command in commandType {
				case ^microui.Command_Rect:
					ui_draw(
						&uiShader,
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

						ui_draw(
							&uiShader,
							characterRect,
							atlasRect,
							command.color
						)

						characterRect.x += characterRect.w
					}
				case ^microui.Command_Icon:
					ui_draw(
						&uiShader,
						command.rect,
						microui.default_atlas[command.id],
						command.color
					)
				}
			}

			ui_post_draw(&uiShader)
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

process_input :: proc(window: glfw.WindowHandle, mui: ^microui.Context) {
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

		rowLayout := [?]i32{0, 0}
		microui.layout_row(mui, rowLayout[:])
		microui.label(mui, "Post-processing: ")
		if .SUBMIT in microui.button(mui, fmt.tprintf("%v", Settings.postProcessEffect)) {
			microui.open_popup(mui, "post-processing-dropdown")
		}
		if microui.begin_popup(mui, "post-processing-dropdown") {
			for e in PostProcessEffect {
				if .SUBMIT in microui.button(mui, fmt.tprintf("%v", e)) {
					Settings.postProcessEffect = e
				}
			}

			microui.end_popup(mui)
		}

		microui.end_window(mui)
	}
	microui.end(mui)
}

load_texture :: proc(gltfPath: string, texture: ^cgltf.texture) -> u32 {
    textureWidth, textureHeight, textureChannelCount: c.int

	texturePath := filepath.join({ filepath.dir(gltfPath), string(texture.image_.uri) }) or_else
		panic(fmt.tprintfln("Failed to load texture %v", texture.image_.uri))
	defer delete(texturePath)

    textureCString := strings.clone_to_cstring(texturePath)
    defer delete(textureCString)
    textureBytes := stb.load(
        textureCString,
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

load_cubemap :: proc(gltfPath, right, left, top, bottom, front, back: string) -> u32 {
    glCubemap: u32
    gl.GenTextures(1, &glCubemap)

    gl.BindTexture(gl.TEXTURE_CUBE_MAP, glCubemap)

    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    textureWidth, textureHeight, textureChannelCount : c.int

    cubemapFaceNames := []string{right, left, top, bottom, front, back}
    for faceName, i in cubemapFaceNames {
    	texturePath := filepath.join({ filepath.dir(gltfPath), faceName }) or_else
     		panic(fmt.tprintfln("Failed to construct texture path %v", faceName))
    	defer delete(texturePath)

     	textureCString := strings.clone_to_cstring(texturePath)
      	defer delete(textureCString)
       	textureBytes := stb.load(
           textureCString,
           &textureWidth,
           &textureHeight,
           &textureChannelCount,
           3, // to match the hard coded RGB format we'll use below
       )
       if textureBytes == nil {
           panic(fmt.tprintf("Failed to load texture %s", stb.failure_reason()))
       }
       defer stb.image_free(textureBytes)

       gl.TexImage2D(
           gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(i),
           0,
           gl.RGB,
           textureWidth,
           textureHeight,
           0,
           gl.RGB,
           gl.UNSIGNED_BYTE,
           textureBytes,
       )
    }

    return glCubemap
}

scene_load :: proc(path: string, glBuffers: ^map[^cgltf.buffer]u32, glTextures: ^map[^cgltf.texture]u32) -> ^cgltf.data {
	scenePathCString := strings.clone_to_cstring(Settings.scenePath)
	defer delete(scenePathCString)

	sceneData, sceneParseResult := cgltf.parse_file(cgltf.options{}, scenePathCString)
	if sceneParseResult != .success {
		fmt.eprintfln("Failed to load scene file, returning empty scene")
		return new(cgltf.data)
	}

	sceneParseResult = cgltf.load_buffers(cgltf.options{}, sceneData, scenePathCString)
	if sceneParseResult != .success {
		fmt.eprintfln("Failed to load scene buffers, returning empty scene")
		cgltf.free(sceneData)
		return new(cgltf.data)
	}

	if sceneData.scene != nil {
		for buffer, i in sceneData.buffers {
			bufferId: u32
			gl.GenBuffers(1, &bufferId)
			gl.BindBuffer(gl.ARRAY_BUFFER, bufferId)
			gl.BufferData(gl.ARRAY_BUFFER, int(buffer.size), buffer.data, gl.STATIC_DRAW)

			glBuffers[&sceneData.buffers[i]] = bufferId
		}

		for &texture, i in sceneData.textures {
			glTextures[&sceneData.textures[i]] = load_texture(Settings.scenePath, &texture)
		}
	}

	return sceneData
}

scene_destroy :: proc(sceneData: ^cgltf.data, glBuffers: ^map[^cgltf.buffer]u32, glTextures: ^map[^cgltf.texture]u32) {
	cgltf.free(sceneData)

	for _, &glBuffer in glBuffers {
		gl.DeleteBuffers(1, &glBuffer)
	}

	for _, &glTexture in glTextures {
		gl.DeleteTextures(1, &glTexture)
	}
}

fill_draw_input :: proc(glBuffers: ^map[^cgltf.buffer]u32, glTextures: ^map[^cgltf.texture]u32, input: ^PhongShaderInput, primitive: ^cgltf.primitive) {
	for attribute in primitive.attributes {
		#partial switch attribute.type {
		case .position: {
			if primitive.indices != nil {
				input.elementCount = u32(primitive.indices.count)

				input.indices = BufferView {
					glBuffer = glBuffers[primitive.indices.buffer_view.buffer],
					// right now the only component types I'm supporting, will change this to proper mapping later
					glComponentType = primitive.indices.component_type == .r_16u ? gl.UNSIGNED_SHORT : gl.UNSIGNED_INT,
					stride = i32(primitive.indices.stride),
					offset = primitive.indices.offset + primitive.indices.buffer_view.offset,
				}
			} else {
				input.elementCount = u32(attribute.data.count)
			}

			input.positions = BufferView {
				glBuffer = glBuffers[attribute.data.buffer_view.buffer],
				glComponentType = gl.FLOAT,
				stride = i32(attribute.data.stride),
				offset = attribute.data.offset + attribute.data.buffer_view.offset,
			}
		}
		case .color: {
			input.colors = BufferView {
				glBuffer = glBuffers[attribute.data.buffer_view.buffer],
				glComponentType = gl.FLOAT,
				stride = i32(attribute.data.stride),
				offset = attribute.data.offset + attribute.data.buffer_view.offset,
			}
		}
		case .texcoord: {
			input.texcoords = BufferView {
				glBuffer = glBuffers[attribute.data.buffer_view.buffer],
				glComponentType = gl.FLOAT,
				stride = i32(attribute.data.stride),
				offset = attribute.data.offset + attribute.data.buffer_view.offset,
			}
		}
		case .normal: {
			input.normals = BufferView {
				glBuffer = glBuffers[attribute.data.buffer_view.buffer],
				glComponentType = gl.FLOAT,
				stride = i32(attribute.data.stride),
				offset = attribute.data.offset + attribute.data.buffer_view.offset,
			}
		}
		}
	}

	if material := primitive.material; material != nil {
		input.hasMaterial = true
		input.material.emissiveColor = material.emissive_factor

		if material.has_pbr_specular_glossiness {
			if diffuseTexture := material.pbr_specular_glossiness.diffuse_texture.texture; diffuseTexture != nil {
				input.material.glDiffuseTexture = glTextures[diffuseTexture]
			}

			// because I'm hacking my way into using this field even though I'm not implementing physically based rendering that gltf defines
			input.material.specularity = material.pbr_specular_glossiness.glossiness_factor * 32
			input.material.specularColor = material.pbr_specular_glossiness.specular_factor

			if specularTexture := material.pbr_specular_glossiness.specular_glossiness_texture.texture; specularTexture != nil {
				input.material.glSpecularTexture = glTextures[specularTexture]
			}
		}
	}
}
