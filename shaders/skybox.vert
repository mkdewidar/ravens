#version 330 core

in vec3 vertPos;

uniform mat4 view;
uniform mat4 projection;

out vec3 TexCoords;

void main() {
    gl_Position = projection * mat4(mat3(view)) * vec4(vertPos, 1);
    TexCoords = vertPos;
}
