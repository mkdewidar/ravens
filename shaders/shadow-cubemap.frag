#version 330 core

in vec4 FragWorldPos;

uniform vec3 LightPos;
uniform float FarPlane;

void main() {
    float distanceFromLight = length(FragWorldPos.xyz - LightPos);
    // linear depth from 0 (closest to light) to 1 (furthest from light)
    gl_FragDepth = distanceFromLight / FarPlane;
}
