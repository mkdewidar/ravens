#version 330 core

in vec2 vertPos;
in vec2 texCoords;

out vec2 TexCoords;

void main() {
    gl_Position = vec4(vertPos.xy, 0, 1);
    TexCoords = texCoords;
}
