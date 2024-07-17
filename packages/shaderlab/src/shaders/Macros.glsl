#ifndef MACROS_INCLUDED
#define MACROS_INCLUDED

#if defined(SCENE_SHADOW_TYPE) && defined(RENDERER_IS_RECEIVE_SHADOWS)
    #define NEED_CALCULATE_SHADOWS
#endif


#if defined(RENDERER_HAS_TANGENT) || defined(MATERIAL_ENABLE_ANISOTROPY) || defined(MATERIAL_HAS_CLEAR_COAT_NORMAL_TEXTURE)
    #define NEED_TANGENT
#endif


#endif
