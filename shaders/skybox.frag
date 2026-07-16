#version 330 core

in vec3 TexCoords;

out vec4 outColor;

uniform samplerCube cubemap;

void main() {
    outColor = texture(cubemap, TexCoords);
}
