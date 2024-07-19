#define FUNCTION_SPECULAR_LOBE specularLobe_hair

#include "BRDF.glsl"

#include "./HairFunction.glsl"

void specularLobe_hair(Varyings varyings, SurfaceData surfaceData, BRDFData brdfData, vec3 incidentDirection, vec3 attenuationIrradiance, inout vec3 specularColor){
    
    vec3 worldtangentDir = surfaceData.tangent;
    vec3 worldbitangentDir = surfaceData.bitangent;

   #ifdef MATERIAL_HAS_HAIRANISOTROPY_TEXTURE   
    float shift = texture2D(material_HairAnisotropyTexture, varyings.uv).r - 0.5;
   #else
    float shift = 1.0;
   #endif

    vec3 shiftTangent1 = shiftTangent(worldbitangentDir, surfaceData.normal, shift + material_HairFirstOffest);
    vec3 shiftTangent2 = shiftTangent(worldbitangentDir, surfaceData.normal, shift + material_HairSecondOffest);

    vec3 firstcol = material_HairFirstColor.rgb;
    vec3 firstSpecular = firstcol * anisotropySpecular(surfaceData, incidentDirection, material_HairFirstWidth*15.0, material_HairsFirststrength, shiftTangent1);
 
    vec3 secondcol = material_HairSecondColor.rgb;
    vec3 secondSpecular = secondcol * anisotropySpecular(surfaceData, incidentDirection, material_HairSecondWidth*15.0, material_HairsSecondstrength, shiftTangent2);
 
    vec3 hairSpecular = clamp(firstSpecular + secondSpecular, 0.0, 1.0);

    specularColor += attenuationIrradiance * hairSpecular;
}

#include "LightDirectPBR.glsl"