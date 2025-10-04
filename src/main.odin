package main

import "base:runtime"
import "core:fmt"

import "core:c"

import "vendor:glfw"
import gl "vendor:OpenGL"

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

    for !glfw.WindowShouldClose(window) {
        if glfw.GetKey(window, glfw.KEY_ESCAPE) == glfw.PRESS {
            glfw.SetWindowShouldClose(window, true)
        }

        gl.ClearColor(0.3, 0.4, 0.5, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT)

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
