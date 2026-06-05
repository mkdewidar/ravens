#version 330 core

layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 color;
layout(location = 2) in vec2 tex;
layout(location = 3) in vec3 normal;

// passed to the fragment shader, and as a result is interpolated for each fragment,
// essentially giving us a fragment position in world space
out vec3 vertWorldPos;
out vec3 vertColor;
out vec2 texCoordinates;
// should already be normalised
out vec3 normalDirection;

// model matrix converts coordinates from object local to world coordinates
uniform mat4 model;
// view matrix converts coordinates from world to camera-relative coordinates
uniform mat4 view;
// perspective matrix applies perspective projection to the camera-relative coordinates, leaving them
// in NDC/clip space coordinates that OpenGL uses
uniform mat4 projection;

void main() {
    vertWorldPos = (model * vec4(pos, 1.0)).xyz;
    gl_Position = projection * view * model * vec4(pos, 1.0);
    vertColor = color;
    texCoordinates = tex;
    // transform the normals using the "normal matrix" which is a special version of the model
    // matrix that is used on the verticies themselves but one that ignores translation and
    // correctly handles scaling (since those should behave differently when we're talking about normals)
    normalDirection = mat3(transpose(inverse(model))) * normal;
}