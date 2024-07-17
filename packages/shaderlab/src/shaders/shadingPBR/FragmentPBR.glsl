#ifndef MATERIAL_INPUT_PBR_INCLUDED
#define MATERIAL_INPUT_PBR_INCLUDED

#include "Normal.glsl"

float material_AlphaCutoff;
vec4 material_BaseColor;
float material_Metal;
float material_Roughness;
float material_IOR;
vec3 material_PBRSpecularColor;
float material_Glossiness;
vec3 material_EmissiveColor;
float material_NormalIntensity;
float material_OcclusionIntensity;
float material_OcclusionTextureCoord;

#ifdef MATERIAL_ENABLE_CLEAR_COAT
    float material_ClearCoat;
    float material_ClearCoatRoughness;

    #ifdef MATERIAL_HAS_CLEAR_COAT_TEXTURE
        sampler2D material_ClearCoatTexture;
    #endif

    #ifdef MATERIAL_HAS_CLEAR_COAT_ROUGHNESS_TEXTURE
        sampler2D material_ClearCoatRoughnessTexture;
    #endif

    #ifdef MATERIAL_HAS_CLEAR_COAT_NORMAL_TEXTURE
        sampler2D material_ClearCoatNormalTexture;
    #endif
#endif

#ifdef MATERIAL_ENABLE_ANISOTROPY
    vec3 material_AnisotropyInfo;
    #ifdef MATERIAL_HAS_ANISOTROPY_TEXTURE
        sampler2D material_AnisotropyTexture;
    #endif
#endif

// Texture
#ifdef MATERIAL_HAS_BASETEXTURE
    sampler2D material_BaseTexture;
#endif

#ifdef MATERIAL_HAS_NORMALTEXTURE
    sampler2D material_NormalTexture;
#endif

#ifdef MATERIAL_HAS_EMISSIVETEXTURE
    sampler2D material_EmissiveTexture;
#endif

#ifdef MATERIAL_HAS_ROUGHNESS_METALLIC_TEXTURE
    sampler2D material_RoughnessMetallicTexture;
#endif


#ifdef MATERIAL_HAS_SPECULAR_GLOSSINESS_TEXTURE
    sampler2D material_SpecularGlossinessTexture;
#endif

#ifdef MATERIAL_HAS_OCCLUSION_TEXTURE
    sampler2D material_OcclusionTexture;
#endif


SurfaceData getSurfaceData(Varyings v, bool isFrontFacing){
    SurfaceData surfaceData;
    // common
    vec4 baseColor = material_BaseColor;
    float metallic = material_Metal;
    float roughness = material_Roughness;
    vec3 specularColor = material_PBRSpecularColor;
    float glossiness = material_Glossiness;
    float f0 = pow2( (material_IOR - 1.0) / (material_IOR + 1.0) );
    vec3 emissiveRadiance = material_EmissiveColor;

    #ifdef MATERIAL_HAS_BASETEXTURE
        vec4 baseTextureColor = texture2D(material_BaseTexture, v.uv);
        #ifndef ENGINE_IS_COLORSPACE_GAMMA
            baseTextureColor = gammaToLinear(baseTextureColor);
        #endif
        baseColor *= baseTextureColor;
    #endif

    #ifdef RENDERER_ENABLE_VERTEXCOLOR
        baseColor *= v.vertexColor;
    #endif


    #ifdef MATERIAL_IS_ALPHA_CUTOFF
        if( baseColor.a < material_AlphaCutoff ) {
            discard;
        }
    #endif

    #ifdef MATERIAL_HAS_ROUGHNESS_METALLIC_TEXTURE
        vec4 metalRoughMapColor = texture2D( material_RoughnessMetallicTexture, v.uv );
        roughness *= metalRoughMapColor.g;
        metallic *= metalRoughMapColor.b;
    #endif

    #ifdef MATERIAL_HAS_SPECULAR_GLOSSINESS_TEXTURE
        vec4 specularGlossinessColor = texture2D(material_SpecularGlossinessTexture, v.uv );
        #ifndef ENGINE_IS_COLORSPACE_GAMMA
            specularGlossinessColor = gammaToLinear(specularGlossinessColor);
        #endif
        specularColor *= specularGlossinessColor.rgb;
        glossiness *= specularGlossinessColor.a;
        roughness =  1.0 - glossiness;
    #endif

    #ifdef MATERIAL_HAS_EMISSIVETEXTURE
        vec4 emissiveColor = texture2D(material_EmissiveTexture, v.uv);
        #ifndef ENGINE_IS_COLORSPACE_GAMMA
            emissiveColor = gammaToLinear(emissiveColor);
        #endif
        emissiveRadiance *= emissiveColor.rgb;
    #endif

    surfaceData.albedoColor = baseColor.rgb;
    surfaceData.specularColor = specularColor;
    surfaceData.emissiveColor = emissiveRadiance;
    surfaceData.metallic = metallic;
    surfaceData.roughness = roughness;
    surfaceData.f0 = f0;

    #ifdef MATERIAL_IS_TRANSPARENT
        surfaceData.opacity = baseColor.a;
    #else
        surfaceData.opacity = 1.0;
    #endif


    // geometry
    surfaceData.position = v.positionWS;
    
    #ifdef CAMERA_ORTHOGRAPHIC
        surfaceData.viewDir = -camera_Forward;
    #else
        surfaceData.viewDir = normalize(camera_Position - v.positionWS);
    #endif

    #ifdef NEED_TANGENT
        mat3 tbn = getTBN(v, isFrontFacing);
        surfaceData.tangent = tbn[0];
        surfaceData.bitangent = tbn[1];
        #ifdef MATERIAL_HAS_NORMALTEXTURE
            surfaceData.normal = getNormalByNormalTexture(tbn, material_NormalTexture, material_NormalIntensity, v.uv, isFrontFacing);
        #else
            surfaceData.normal = tbn[2];
        #endif
    #else
        surfaceData.normal = getNormal(v, isFrontFacing);
    #endif

    return surfaceData;
}

float getAARoughnessFactor(vec3 normal) {
    // Kaplanyan 2016, "Stable specular highlights"
    // Tokuyoshi 2017, "Error Reduction and Simplification for Shading Anti-Aliasing"
    // Tokuyoshi and Kaplanyan 2019, "Improved Geometric Specular Antialiasing"
    #ifdef HAS_DERIVATIVES
        vec3 dxy = max( abs(dFdx(normal)), abs(dFdy(normal)) );
        return max( max(dxy.x, dxy.y), dxy.z );
    #else
        return 0.0;
    #endif
}

#ifdef MATERIAL_ENABLE_ANISOTROPY
    // Aniso Bent Normals
    // Mc Alley https://www.gdcvault.com/play/1022235/Rendering-the-World-of-Far 
    vec3 getAnisotropicBentNormal(BRDFData brdfData) {
        vec3  anisotropyDirection = (brdfData.anisotropy >= 0.0) ? brdfData.anisotropicB : brdfData.anisotropicT;
        vec3  anisotropicTangent  = cross(anisotropyDirection, brdfData.viewDir);
        vec3  anisotropicNormal   = cross(anisotropicTangent, anisotropyDirection);
        // reduce stretching for (roughness < 0.2), refer to https://advances.realtimerendering.com/s2018/Siggraph%202018%20HDRP%20talk_with%20notes.pdf 80
        vec3  bentNormal          = normalize( mix(brdfData.normal, anisotropicNormal, abs(brdfData.anisotropy) * saturate( 5.0 * brdfData.roughness)) );

        return bentNormal;
    }
#endif



void initGeometryData(SurfaceData surfaceData, inout BRDFData brdfData){
    brdfData.position = surfaceData.position;
    brdfData.normal = surfaceData.normal;
    #ifdef NEED_TANGENT
        brdfData.tangent = surfaceData.tangent;
        brdfData.bitangent = surfaceData.bitangent;
    #endif
    brdfData.viewDir = surfaceData.viewDir;

    brdfData.dotNV = saturate( dot(brdfData.normal, brdfData.viewDir) );
}

void initCommonBRDFData(SurfaceData surfaceData, inout BRDFData brdfData){
    vec3 albedoColor = surfaceData.albedoColor;
    vec3 specularColor = surfaceData.specularColor;
    float metallic = surfaceData.metallic;
    float roughness = surfaceData.roughness;
    float f0 = surfaceData.f0;

    #ifdef IS_METALLIC_WORKFLOW
        brdfData.diffuseColor = albedoColor * ( 1.0 - metallic );
        brdfData.specularColor = mix( vec3(f0), albedoColor, metallic );
    #else
        float specularStrength = max( max( specularColor.r, specularColor.g ), specularColor.b );
        brdfData.diffuseColor = albedoColor * ( 1.0 - specularStrength );
        brdfData.specularColor = specularColor;
    #endif

    brdfData.roughness = max(MIN_PERCEPTUAL_ROUGHNESS, min(roughness + getAARoughnessFactor(brdfData.normal), 1.0));
}

void initClearCoatBRDFData(Varyings v, inout BRDFData brdfData, bool isFrontFacing){
    #ifdef MATERIAL_ENABLE_CLEAR_COAT
        #ifdef MATERIAL_HAS_CLEAR_COAT_NORMAL_TEXTURE
            brdfData.clearCoatNormal = getNormalByNormalTexture(mat3(brdfData.tangent, brdfData.bitangent, brdfData.normal), material_ClearCoatNormalTexture, material_NormalIntensity, v.uv, isFrontFacing);
        #else
            brdfData.clearCoatNormal = getNormal(v, isFrontFacing);
        #endif
        brdfData.clearCoatDotNV = saturate( dot(brdfData.clearCoatNormal, brdfData.viewDir) );

        brdfData.clearCoat = material_ClearCoat;
        brdfData.clearCoatRoughness = material_ClearCoatRoughness;

        #ifdef MATERIAL_HAS_CLEAR_COAT_TEXTURE
            brdfData.clearCoat *= (texture2D( material_ClearCoatTexture, v.uv )).r;
        #endif

        #ifdef MATERIAL_HAS_CLEAR_COAT_ROUGHNESS_TEXTURE
            brdfData.clearCoatRoughness *= (texture2D( material_ClearCoatRoughnessTexture, v.uv )).g;
        #endif

        brdfData.clearCoat = saturate( brdfData.clearCoat );
       
        brdfData.clearCoatRoughness = max(MIN_PERCEPTUAL_ROUGHNESS, min(brdfData.clearCoatRoughness + getAARoughnessFactor(brdfData.clearCoatNormal), 1.0));

    #endif

}

void initAnisotropyBRDFData(Varyings v, inout BRDFData brdfData){
    #ifdef MATERIAL_ENABLE_ANISOTROPY
        float anisotropy = material_AnisotropyInfo.z;
        vec3 anisotropicDirection = vec3(material_AnisotropyInfo.xy, 0.0);
        #ifdef MATERIAL_HAS_ANISOTROPY_TEXTURE
            vec3 anisotropyTextureInfo = (texture2D( material_AnisotropyTexture, v.uv )).rgb;
            anisotropy *= anisotropyTextureInfo.b;
            anisotropicDirection.xy *= anisotropyTextureInfo.rg * 2.0 - 1.0;
        #endif

        brdfData.anisotropy = anisotropy;
        brdfData.anisotropicT = normalize(mat3(brdfData.tangent, brdfData.bitangent, brdfData.normal) * anisotropicDirection);
        brdfData.anisotropicB = normalize(cross(brdfData.normal, brdfData.anisotropicT));
        brdfData.anisotropicN = getAnisotropicBentNormal(brdfData);

    #endif

}

void initAO(Varyings v, inout BRDFData brdfData){
    float diffuseAO = 1.0;
    float specularAO = 1.0;

    #ifdef MATERIAL_HAS_OCCLUSION_TEXTURE
        vec2 aoUV = v.uv;
        #ifdef RENDERER_HAS_UV1
            if(material_OcclusionTextureCoord == 1.0){
                aoUV = v.uv1;
            }
        #endif
        diffuseAO = ((texture2D(material_OcclusionTexture, aoUV)).r - 1.0) * material_OcclusionIntensity + 1.0;
    #endif

    #if defined(MATERIAL_HAS_OCCLUSION_TEXTURE) && defined(SCENE_USE_SPECULAR_ENV) 
        specularAO = saturate( pow( brdfData.dotNV + diffuseAO, exp2( - 16.0 * brdfData.roughness - 1.0 ) ) - 1.0 + diffuseAO );
    #endif

    brdfData.diffuseAO = diffuseAO;
    brdfData.specularAO = specularAO;
}

void initBRDFData(Varyings v, SurfaceData surfaceData, out BRDFData brdfData, bool isFrontFacing){
    initGeometryData(surfaceData, brdfData);
    initCommonBRDFData(surfaceData, brdfData);
    initClearCoatBRDFData(v, brdfData, isFrontFacing);
    initAnisotropyBRDFData(v, brdfData);
    initAO(v, brdfData);
}



#endif