#version 330 core

in vec2 vert;
in vec4 color;
in vec2 tex;

// converts the UI elements from the screen based coordinate system to clip space as expected by OpenGL
// usually that's basically just a case of applying orthographic projection
uniform mat4 projection;

out vec4 vertColor;
out vec2 atlasCoords;

void main() {
    gl_Position = projection * vec4(vert.x, vert.y, 1.0, 1.0);
    vertColor = color;
    atlasCoords = tex;
}