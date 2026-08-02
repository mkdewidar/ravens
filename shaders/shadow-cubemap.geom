#version 330 core

layout(triangles) in;
// each triangle provided is 3 vertices, we replicate it for all 6 sides of the cube
// therefore outputting 18 vertices
layout(triangle_strip, max_vertices=18) out;

uniform mat4 ViewMatrices[6];

out vec4 FragWorldPos;

void main() {
    for (int face = 0; face < 6; ++face) {
        gl_Layer = face;

        for (int i = 0; i < 3; ++i) {
            FragWorldPos = gl_in[i].gl_Position;
            gl_Position = ViewMatrices[face] * FragWorldPos;
            EmitVertex();
        }
        EndPrimitive();
    }
}
