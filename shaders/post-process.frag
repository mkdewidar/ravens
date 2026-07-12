#version 330 core

in vec2 TexCoords;

out vec4 outColor;

uniform sampler2D previousPass;

void main() {
    vec4 original = texture(previousPass, TexCoords);
    float avg = ((0.2126 * original.r) + (0.7152 * original.g) + (0.0722 * original.b)) / 3;
    outColor = vec4(avg, avg, avg, 1.0);
}
