#version 330 core

layout(location = 0) in vec3 Pos;

uniform mat4 Model;

void main() {
    gl_Position = Model * vec4(Pos, 1.0);
}
