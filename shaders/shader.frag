#version 330 core

in vec3 fragWorldPos;
in vec3 vertColor;
in vec2 texCoordinates;
// must be re-normalised here before use as fragment shader interpolation does not
// necessarily maintain the length of the vector
in vec3 normalDirection;

struct DirectionalLight {
    // should be normalised and incident (i.e pointing towards the fragment)
    vec3 direction;
    vec3 color;
};
uniform DirectionalLight directLight;

struct PointLight {
    vec3 position;
    vec3 color;
};
#define POINT_LIGHTS_COUNT 1
uniform PointLight[POINT_LIGHTS_COUNT] pointLights;

struct Material {
    vec3 emissiveColor;
    sampler2D diffuseTex;
    vec3 specularColor;
    // set to true and then set the specularTex to use a specular map instead of basic color
    bool useSpecularMap;
    sampler2D specularTex;
    float specularity;
};
uniform Material objectMaterial;

// world position of the viewer, used for specular highlights
uniform vec3 viewPos;

out vec4 fragColor;

vec4 colorUnderDirectionalLight(Material material, DirectionalLight dirLight, vec3 normal) {
    // max used to detect when light is hitting at an angle greater than 90 degrees
    // and therefore treat it as dark, note this is different from ensuring the
    // backface of objects will be lit properly
    float diffuseFactor = max(dot(normal, -dirLight.direction), 0.0);
    vec3 diffuseColor = diffuseFactor * dirLight.color * vec3(texture(material.diffuseTex, texCoordinates));

    vec3 lightReflectionDir = reflect(dirLight.direction, normal);
    float specularFactor = pow(max(dot(normalize(viewPos - fragWorldPos), lightReflectionDir), 0.0), material.specularity);
    vec3 specularColor = specularFactor * dirLight.color;
    if (material.useSpecularMap) {
        specularColor *= vec3(texture(material.specularTex, texCoordinates));
    }

    return vec4(vertColor * (material.emissiveColor + diffuseColor + specularColor), 1.0);
}

vec4 colorUnderPointLight(Material material, PointLight pLight, vec3 normal) {
    // direction from vert to the light
    vec3 lightDir = normalize(pLight.position - fragWorldPos);
    // max used to detect when light is hitting at an angle greater than 90 degrees
    // and therefore treat it as dark, note this is different from ensuring the
    // backface of objects will be lit properly
    float diffuseFactor = max(dot(normal, lightDir), 0.0);
    vec3 diffuseColor = diffuseFactor * pLight.color * vec3(texture(material.diffuseTex, texCoordinates));

    // direction is reversed so we get from light to vert, which is the direction needed for reflection to work
    vec3 lightReflectionDir = reflect(-lightDir, normal);
    float specularFactor = pow(max(dot(normalize(viewPos - fragWorldPos), lightReflectionDir), 0.0), material.specularity);
    vec3 specularColor = specularFactor * pLight.color;
    if (material.useSpecularMap) {
        specularColor *= vec3(texture(material.specularTex, texCoordinates));
    }

    return vec4(vertColor * (material.emissiveColor + diffuseColor + specularColor), 1.0);
}

void main() {
    vec3 normal = normalize(normalDirection);

    fragColor = colorUnderDirectionalLight(objectMaterial, directLight, normal);

    for (int i = 0; i < POINT_LIGHTS_COUNT; i++) {
        fragColor += colorUnderPointLight(objectMaterial, pointLights[i], normal);
    }
}