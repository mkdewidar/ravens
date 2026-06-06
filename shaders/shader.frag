#version 330 core

in vec3 fragWorldPos;
in vec3 vertColor;
in vec2 texCoordinates;
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

    // set to 0 to have no attenuation
    float constantAttenuation;
    float linearAttenuation;
    float quadraticAttenuation;
};
#define POINT_LIGHTS_COUNT 1
uniform PointLight[POINT_LIGHTS_COUNT] pointLights;

struct Material {
    vec3 emissiveColor;
    sampler2D diffuseTex;
    // can be set to 0 to disable specular entirely for this material
    float specularity;
    vec3 specularColor;
    // set to true and then set the specularTex to use a specular map instead of basic color
    bool useSpecularMap;
    sampler2D specularTex;
};
uniform Material objectMaterial;

// world position of the viewer, used for specular highlights
uniform vec3 viewPos;

out vec4 fragColor;

/*
* normal: the normalised normal vector for this fragment
* lightDirection: the incident (i.e pointing towards the fragment) direction vector for the light source
*/
vec3 diffuseColor(vec3 normal, vec3 lightDirection, vec3 lightColor, Material material, vec2 textureCoordinates) {
    // max used to detect when light is hitting at an angle greater than 90 degrees
    // and therefore treat it as dark, note this is different from ensuring the
    // backface of objects will be lit properly
    float diffuseFactor = max(dot(normal, lightDirection), 0.0);
    return diffuseFactor * lightColor * vec3(texture(material.diffuseTex, texCoordinates));
}

/*
* normal: the normalised normal vector for this fragment
* lightDirection: the incident (i.e pointing towards the fragment) direction vector for the light source
* currentWorldPos: the world position of this fragment
* viewpoint: the world position of the viewer
*/
vec3 specularColor(vec3 normal, vec3 lightDirection, vec3 lightColor, vec3 currentWorldPos, vec3 viewerPos, Material material, vec2 textureCoordinates) {
    vec3 specularColor = vec3(0, 0, 0);

    if (material.specularity > 0) {
        vec3 lightReflectionDir = reflect(lightDirection, normal);
        float specularFactor = pow(max(dot(normalize(viewerPos - currentWorldPos), lightReflectionDir), 0.0), material.specularity);

        specularColor = specularFactor * lightColor;

        if (material.useSpecularMap) {
            specularColor *= vec3(texture(material.specularTex, texCoordinates));
        }
    }

    return specularColor;
}

vec4 colorUnderDirectionalLight(Material material, DirectionalLight dirLight, vec3 normal) {
    vec3 diffuseColor = diffuseColor(normal, -dirLight.direction, dirLight.color, material, texCoordinates);
    vec3 specularColor = specularColor(normal, dirLight.direction, dirLight.color, viewPos, fragWorldPos, material, texCoordinates);

    return vec4(vertColor * (material.emissiveColor + diffuseColor + specularColor), 1.0);
}

vec4 colorUnderPointLight(Material material, PointLight pLight, vec3 normal) {
    vec3 fragmentToLight = pLight.position - fragWorldPos;
    // direction from vert to the light
    vec3 lightDir = normalize(fragmentToLight);

    vec3 diffuseColor = diffuseColor(normal, lightDir, pLight.color, material, texCoordinates);
    vec3 specularColor = specularColor(normal, -lightDir, pLight.color, viewPos, fragWorldPos, material, texCoordinates);

    float attenuation = 1;
    if (pLight.constantAttenuation != 0) {
        attenuation = 1 /
            (pLight.constantAttenuation +
            (pLight.linearAttenuation * length(fragmentToLight)) +
            (pLight.quadraticAttenuation * pow(length(fragmentToLight), 2)));
    }

    return vec4(vertColor * attenuation * (material.emissiveColor + diffuseColor + specularColor), 1.0);
}

void main() {
    // must be re-normalised here before use as fragment shader interpolation does not
    // necessarily maintain the length of the vector
    vec3 normal = normalize(normalDirection);

    fragColor = colorUnderDirectionalLight(objectMaterial, directLight, normal);

    for (int i = 0; i < POINT_LIGHTS_COUNT; i++) {
        fragColor += colorUnderPointLight(objectMaterial, pointLights[i], normal);
    }
}