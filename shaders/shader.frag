#version 330 core

in vec3 vertColor;
in vec2 texCoordinates;

uniform sampler2D tex;

out vec4 fragColor;

void main() {
    fragColor = texture(tex, texCoordinates) * vec4(vertColor, 1.0);
}