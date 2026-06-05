#version 330 core

in vec3 vertWorldPos;
in vec3 vertColor;
in vec2 texCoordinates;
in vec3 normalDirection;

const vec3 LIGHT_COLOR = vec3(1, 1, 1);
const int SPECULAR_POW = 32;
const vec3 AMBIENT_COLOR = 0.1 * LIGHT_COLOR;

// world position of light source for the scene
uniform vec3 lightPos;
// world position of the viewer, used for specular highlights
uniform vec3 viewPos;

uniform sampler2D tex;

out vec4 fragColor;

void main() {
    vec3 lightDir = normalize(lightPos - vertWorldPos);
    // max used to detect when light is hitting at an angle greater than 90 degrees
    // and therefore treat it as dark, note this is different from ensuring the
    // backface of objects will be lit properly
    vec3 diffuseColor = max(dot(normalDirection, lightDir), 0.0) * LIGHT_COLOR;

    vec3 lightReflectionDir = reflect(-lightDir, normalDirection);
    // the specular equation
    vec3 specularColor = pow(max(dot(normalize(viewPos - vertWorldPos), lightReflectionDir), 0.0), SPECULAR_POW) * LIGHT_COLOR;

    vec3 finalColor = vertColor * (diffuseColor + specularColor);
    fragColor = texture(tex, texCoordinates) * vec4(finalColor, 1.0);
}