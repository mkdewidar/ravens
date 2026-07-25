package main

import "core:fmt"
import "core:strings"

import "vendor:cgltf"
import gl "vendor:OpenGL"

scene_load :: proc(path: string, glBuffers: ^map[^cgltf.buffer]u32, glTextures: ^map[^cgltf.texture]u32) -> ^cgltf.data {
	scenePathCString := strings.clone_to_cstring(Settings.scenePath)
	defer delete(scenePathCString)

	sceneData, sceneParseResult := cgltf.parse_file(cgltf.options{}, scenePathCString)
	if sceneParseResult != .success {
		fmt.eprintfln("Failed to load scene file, returning empty scene")
		return new(cgltf.data)
	}

	sceneParseResult = cgltf.load_buffers(cgltf.options{}, sceneData, scenePathCString)
	if sceneParseResult != .success {
		fmt.eprintfln("Failed to load scene buffers, returning empty scene")
		cgltf.free(sceneData)
		return new(cgltf.data)
	}

	if sceneData.scene != nil {
		for buffer, i in sceneData.buffers {
			bufferId: u32
			gl.GenBuffers(1, &bufferId)
			gl.BindBuffer(gl.ARRAY_BUFFER, bufferId)
			gl.BufferData(gl.ARRAY_BUFFER, int(buffer.size), buffer.data, gl.STATIC_DRAW)

			glBuffers[&sceneData.buffers[i]] = bufferId
		}

		for &texture, i in sceneData.textures {
			glTextures[&sceneData.textures[i]] = load_texture(Settings.scenePath, &texture)
		}
	}

	return sceneData
}

scene_destroy :: proc(sceneData: ^cgltf.data, glBuffers: ^map[^cgltf.buffer]u32, glTextures: ^map[^cgltf.texture]u32) {
	cgltf.free(sceneData)

	for _, &glBuffer in glBuffers {
		gl.DeleteBuffers(1, &glBuffer)
	}

	for _, &glTexture in glTextures {
		gl.DeleteTextures(1, &glTexture)
	}
}
