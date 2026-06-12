#version 330 core

in vec4 vertColor;
in vec2 atlasCoords;

uniform sampler2D atlas;

out vec4 fragColor;

void main() {
    fragColor = vec4(vertColor.rgb, vertColor.a * texture(atlas, atlasCoords).r);
}
