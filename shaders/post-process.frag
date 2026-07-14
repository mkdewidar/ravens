#version 330 core

in vec2 TexCoords;

out vec4 outColor;

#define NONE 0
#define GREYSCALE 1

uniform int effect = NONE;
uniform sampler2D previousPass;

void main() {
    vec4 original = texture(previousPass, TexCoords);

    switch (effect) {
        case NONE: {
            outColor = original;
            break;
        }
        case GREYSCALE: {
            float avg = ((0.2126 * original.r) + (0.7152 * original.g) + (0.0722 * original.b)) / 3;
            outColor = vec4(avg, avg, avg, 1.0);
            break;
        }
    }
}
