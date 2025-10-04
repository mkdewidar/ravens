package main

import "base:runtime"
import "core:fmt"

import "vendor:glfw"

main :: proc() {
    glfw.SetErrorCallback(error_callback)

    if !glfw.Init() {
        panic("Failed to initialize glfw")
    }
    defer glfw.Terminate()

    // seems to be the latest OpenGL version supported on macOS
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

    window := glfw.CreateWindow(640, 480, "Ravens", nil, nil)
    if window == nil {
        description, code := glfw.GetError()
        panic(fmt.tprintfln("Failed to create glfw window, error: %v, description: %v", code, description))
    }
    defer glfw.DestroyWindow(window)

    for !glfw.WindowShouldClose(window) {
        glfw.SwapBuffers(window)
        glfw.PollEvents()
    }
}

/*
Error callback for glfw
*/
@(private="file")
error_callback :: proc "c" (code: i32, description: cstring) {
    // glfw will be calling us from C, so won't have the Odin context we need for
    // formatting to work, so we load it here
    context = runtime.default_context()
    fmt.printfln("GLFW Error: %v, description: %v", code, description)
}