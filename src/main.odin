package main

import "base:runtime"
import "core:fmt"
import "core:c"

import "vendor:glfw"
import gl "vendor:OpenGL"
import stb "vendor:stb/image"

OPENGL_MAJOR_VERSION :: 4
OPENGL_MINOR_VERSION :: 1

main :: proc() {
    glfw.SetErrorCallback(error_callback)

    if !glfw.Init() {
        panic("Failed to initialize glfw")
    }
    defer glfw.Terminate()

    // seems to be the latest OpenGL version supported on macOS
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, OPENGL_MAJOR_VERSION)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, OPENGL_MINOR_VERSION)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    window := glfw.CreateWindow(640, 480, "Ravens", nil, nil)
    if window == nil {
        description, code := glfw.GetError()
        panic(fmt.tprintfln("Failed to create glfw window, error: %v, description: %v", code, description))
    }
    defer glfw.DestroyWindow(window)

    glfw.MakeContextCurrent(window)

    // this is some odin specific stuff that loads all the OpenGL functions from the windowing system
    // into the gl module, for this particular version of OpenGL
    gl.load_up_to(OPENGL_MAJOR_VERSION, OPENGL_MINOR_VERSION, glfw.gl_set_proc_address)

    glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)

    // yet another fantastic helper function for loading, compiling, and attaching shaders to this OpenGL program
    glProgram := gl.load_shaders("shaders/shader.vert", "shaders/shader.frag") or_else panic("Failed to load and compile shaders")
    defer gl.DeleteProgram(glProgram)
    gl.UseProgram(glProgram)

    // not to be confused with "vertex buffer object", this is a container telling OpenGL how to map
    // "vertex buffer objects" onto the inputs of the vertex shader, but doesn't actually store the data itself.
    vertexArrayObject: u32
    gl.GenVertexArrays(1, &vertexArrayObject)
    defer gl.DeleteVertexArrays(1, &vertexArrayObject)
    gl.BindVertexArray(vertexArrayObject)

    textureWidth, textureHeight, textureChannelCount: c.int
    textureBytes := stb.load("assets/container-texture.jpg", &textureWidth, &textureHeight, &textureChannelCount, 0)
    if textureBytes == nil {
        panic(fmt.tprintf("Failed to load texture %s", stb.failure_reason()))
    }
    defer stb.image_free(textureBytes)
    glTexture: u32
    gl.GenTextures(1, &glTexture)
    defer gl.DeleteTextures(1, &glTexture)
    gl.BindTexture(gl.TEXTURE_2D, glTexture)
    // how opengl should handle going out of bounds on the texture's 0 - 1.0 coordinates
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    // how opengl should sample the texture
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, textureWidth, textureHeight, 0, gl.RGB, gl.UNSIGNED_BYTE, textureBytes)
    gl.GenerateMipmap(gl.TEXTURE_2D)

    // these are just the standalone vert positions, we use an element buffer object to tell OpenGL how to draw
    // triangles out of them
    squareData := [?]f32{
        // positions      // colors       // texture coords
        0.5, 0.5, 0,       1, 0, 0,       1, 1,
        0.5, -0.5, 0,      0, 1, 0,       1, 0,
        -0.5, -0.5, 0,     0, 0, 1,       0, 0,
        -0.5, 0.5, 0,      1, 1, 0,       0, 1,
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
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(squareVertIndices), &squareVertIndices, gl.STATIC_DRAW)

    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 0);
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 3 * size_of(f32));
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, 8 * size_of(f32), 6 * size_of(f32));
    gl.EnableVertexAttribArray(2)

    // uncomment for wireframe rendering
//     gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)

    for !glfw.WindowShouldClose(window) {
        if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
            glfw.SetWindowShouldClose(window, true)
        }

        gl.ClearColor(0.3, 0.4, 0.5, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.DrawElements(gl.TRIANGLES, len(squareVertIndices), gl.UNSIGNED_INT, nil)

        glfw.SwapBuffers(window)
        glfw.PollEvents()
    }
}

/*
Error callback for glfw
*/
@(private="file")
error_callback :: proc "c" (code: c.int, description: cstring) {
    // glfw will be calling us from C, so won't have the Odin context we need for
    // formatting to work, so we load it here
    context = runtime.default_context()
    fmt.printfln("GLFW Error: %v, description: %v", code, description)
}

/*
Callback that glfw uses to keep OpenGL's viewport size up to date with the window size
*/
@(private="file")
framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
    gl.Viewport(0, 0, width, height)
}
