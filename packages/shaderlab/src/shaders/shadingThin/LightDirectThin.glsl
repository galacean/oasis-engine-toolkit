
// #ifndef LIGHT_DIRECT_THIN_INCLUDED
// #define LIGHT_DIRECT_THIN_INCLUDED 1

#include "BRDF.glsl"
#include "BRDFThin.glsl"
#include "Light.glsl"
#include "Shadow.glsl"


void diffuseLobe(BRDFData brdfData, vec3 irradiance, float attenuation, inout vec3 Fd){
    Fd += attenuation * irradiance * BRDF_Diffuse_Lambert( brdfData.diffuseColor );
}

void specularLobe(BRDFData brdfData, vec3 incidentDirection, vec3 irradiance, float attenuation, inout vec3 Fs){
    vec3 V = brdfData.viewDir;
    vec3 H = normalize(incidentDirection+V); 
    float VoH = dot(H, V);
    vec3 F = F_Schlick( brdfData.specularColor, VoH );

    vec3 thin = DirectBDRFIridescence(incidentDirection , brdfData.viewDir , brdfData.normal ,brdfData.specularColor , brdfData.roughness);
    vec3 F_iridescence = thin * material_Iridescence;//mix(vec3(0.0,0.0,0.0),thin,material_Iridescence);
    vec3 BRDF_Specular = BRDF_Specular_GGX( incidentDirection, brdfData, brdfData.normal, brdfData.specularColor, brdfData.roughness);
    vec3 factor = mix(BRDF_Specular, thin, material_Iridescence);


    Fs += attenuation * irradiance * factor;
}

float clearCoatLobe(vec3 incidentDirection, vec3 color, BRDFData brdfData, inout vec3 Fs){
    float attenuation = 1.0;

    #ifdef MATERIAL_ENABLE_CLEAR_COAT
        float clearCoatDotNL = saturate( dot( brdfData.clearCoatNormal, incidentDirection ) );
        vec3 clearCoatIrradiance = clearCoatDotNL * color;

        Fs += brdfData.clearCoat * clearCoatIrradiance * BRDF_Specular_GGX( incidentDirection, brdfData, brdfData.clearCoatNormal, vec3( 0.04 ), brdfData.clearCoatRoughness );
        attenuation -= brdfData.clearCoat * F_Schlick(0.04, brdfData.clearCoatDotNV);
    #endif

    return attenuation;
}


void addRadiance(vec3 incidentDirection, vec3 lightColor, BRDFData brdfData, inout vec3 color) {

    vec3 Fd = vec3(0);
    vec3 Fs = vec3(0);
    float dotNL = saturate( dot( brdfData.normal, incidentDirection ) );
    vec3 irradiance = dotNL * lightColor * PI;

    // ClearCoat Lobe
    float attenuation = clearCoatLobe(incidentDirection, lightColor, brdfData, Fs);
    // Diffuse Lobe
    diffuseLobe(brdfData, irradiance, attenuation, Fd);
    // //Iridescence Specular Lobe
    specularLobe(brdfData, incidentDirection, irradiance, attenuation, Fs);

    color += Fd + Fs;

}

#ifdef SCENE_DIRECT_LIGHT_COUNT

    void addDirectionalDirectLightRadiance(DirectLight directionalLight, BRDFData brdfData, inout vec3 color) {
        vec3 lightColor = directionalLight.color;
        vec3 direction = -directionalLight.direction;

        addRadiance( direction, lightColor, brdfData, color );

    }

#endif

#ifdef SCENE_POINT_LIGHT_COUNT

	void addPointDirectLightRadiance(PointLight pointLight, BRDFData brdfData, inout vec3 color) {

		vec3 lVector = pointLight.position - brdfData.position;
		vec3 direction = normalize( lVector );
		float lightDistance = length( lVector );

		vec3 lightColor = pointLight.color;
		lightColor *= clamp(1.0 - pow(lightDistance/pointLight.distance, 4.0), 0.0, 1.0);

        addRadiance( direction, lightColor, brdfData, color );

	}

#endif

#ifdef SCENE_SPOT_LIGHT_COUNT

	void addSpotDirectLightRadiance(SpotLight spotLight, BRDFData brdfData, inout vec3 color) {

		vec3 lVector = spotLight.position - brdfData.position;
		vec3 direction = normalize( lVector );
		float lightDistance = length( lVector );
		float angleCos = dot( direction, -spotLight.direction );

		float spotEffect = smoothstep( spotLight.penumbraCos, spotLight.angleCos, angleCos );
		float decayEffect = clamp(1.0 - pow(lightDistance/spotLight.distance, 4.0), 0.0, 1.0);

		vec3 lightColor = spotLight.color;
		lightColor *= spotEffect * decayEffect;

        addRadiance( direction, lightColor, brdfData, color );

	}


#endif

void evaluateDirectRadiance(Temp_Varyings v, BRDFData brdfData, inout vec3 color){
    float shadowAttenuation = 1.0;

    #ifdef SCENE_DIRECT_LIGHT_COUNT
        shadowAttenuation = 1.0;
        #ifdef SCENE_IS_CALCULATE_SHADOWS
            shadowAttenuation *= sampleShadowMap(v);
            // int sunIndex = int(scene_ShadowInfo.z);
        #endif

        DirectLight directionalLight;
        for ( int i = 0; i < SCENE_DIRECT_LIGHT_COUNT; i ++ ) {
            // warning: use `continue` syntax may trigger flickering bug in safri 16.1.
            if(!isRendererCulledByLight(renderer_Layer.xy, scene_DirectLightCullingMask[i])){
                directionalLight.color = scene_DirectLightColor[i];
                #ifdef SCENE_IS_CALCULATE_SHADOWS
                    if (i == 0) { // Sun light index is always 0
                        directionalLight.color *= shadowAttenuation;
                    }
                #endif
                directionalLight.direction = scene_DirectLightDirection[i];
                addDirectionalDirectLightRadiance( directionalLight, brdfData, color );
            }
        }

    #endif

    #ifdef SCENE_POINT_LIGHT_COUNT

        PointLight pointLight;

        for ( int i = 0; i < SCENE_POINT_LIGHT_COUNT; i ++ ) {
            if(!isRendererCulledByLight(renderer_Layer.xy, scene_PointLightCullingMask[i])){
                pointLight.color = scene_PointLightColor[i];
                pointLight.position = scene_PointLightPosition[i];
                pointLight.distance = scene_PointLightDistance[i];

                addPointDirectLightRadiance( pointLight, brdfData, color );
            } 
        }

    #endif

    #ifdef SCENE_SPOT_LIGHT_COUNT

        SpotLight spotLight;

        for ( int i = 0; i < SCENE_SPOT_LIGHT_COUNT; i ++ ) {
            if(!isRendererCulledByLight(renderer_Layer.xy, scene_SpotLightCullingMask[i])){
                spotLight.color = scene_SpotLightColor[i];
                spotLight.position = scene_SpotLightPosition[i];
                spotLight.direction = scene_SpotLightDirection[i];
                spotLight.distance = scene_SpotLightDistance[i];
                spotLight.angleCos = scene_SpotLightAngleCos[i];
                spotLight.penumbraCos = scene_SpotLightPenumbraCos[i];

                addSpotDirectLightRadiance( spotLight, brdfData, color );
            } 
        }

    #endif
}


// #endif