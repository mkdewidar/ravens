#version 330 core

layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 color;

out vec3 vertColor;

// model matrix converts coordinates from object local to world coordinates
uniform mat4 model;
// view matrix converts coordinates from world to camera-relative coordinates
uniform mat4 view;
// perspective matrix applies perspective projection to the camera-relative coordinates, leaving them
// in NDC/clip space coordinates that OpenGL uses
uniform mat4 projection;

void main() {
    gl_Position = projection * view * model * vec4(pos, 1.0);
    vertColor = color;
}