
# Ravens

A playground for rendering, physics, or whatever real time/simulation things I feel like trying out, written in [Odin programming language](https://odin-lang.org/), and generally trying to use as much of its vendor or built in libraries as possible.

So far, it includes:
- An OpenGL Phong based renderer (about a quarter of the way through https://learnopengl.com)
- Partial GLTF file parsing (enough that I can represent most of my test scene in gltf)
- UI using microUI (no real controls yet, but opens the door for it)

## Thoughts

Rendering:
- finish off the rest of https://learnopengl.com
- resizing the window stretches/changes the image, I guess it should just change the camera? 

UI:
- I'm currently rendering strings one character at a time which is quite inefficient and seems unnecessary.
I'd like to transition to pushing sentences or batching by number of characters (e.g 1024 characters at a time).
- Want to add controls for things like background color, what type of rendering to use, etc.
- Once I have more controls, would be good to invest in some sort of persistence for the controls (ini file or something).

gltf support:
- currently only supports one scene with root nodes, should support a proper scene graph.
- uses `KHR_materials_pbrSpecularGlossiness` as inputs to Phong shader simply because its what cgltf supported and that made it easier, should probably be using `KHR_materials_specular` and `KHR_materials_unlit`.
- should support defining lights
- should move all the transformations I currently do into animations defined in gltf
