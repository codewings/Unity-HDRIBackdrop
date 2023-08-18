Shader "Lookdev/HDRI Backdrop"
{
    Properties
    {

    }

    SubShader
    {
        // Universal Pipeline tag is required. If Universal render pipeline is not set in the graphics settings
        // this Subshader will fail. One can add a subshader below or fallback to Standard built-in to make this
        // material work with both Universal Render Pipeline and Builtin Unity Pipeline
        Tags{"RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "UniversalMaterialType" = "Lit" "IgnoreProjector" = "True"}
        
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        float3 RotateAboutAxis(float4 NormalizedRotationAxisAndAngle, float3 PositionOnAxis, float3 Position)
        {
            // Project Position onto the rotation axis and find the closest point on the axis to Position
            float3 ClosestPointOnAxis = PositionOnAxis + NormalizedRotationAxisAndAngle.xyz * dot(NormalizedRotationAxisAndAngle.xyz, Position - PositionOnAxis);
            // Construct orthogonal axes in the plane of the rotation
            float3 UAxis = Position - ClosestPointOnAxis;
            float3 VAxis = cross(NormalizedRotationAxisAndAngle.xyz, UAxis);
            float CosAngle;
            float SinAngle;
            sincos(NormalizedRotationAxisAndAngle.w, SinAngle, CosAngle);
            // Rotate using the orthogonal axes
            float3 R = UAxis * CosAngle + VAxis * SinAngle;
            // Reconstruct the rotated world space position
            float3 RotatedPosition = ClosestPointOnAxis + R;
            // Convert from position to a position offset
            return RotatedPosition - Position;
        }
        // NOTE: Do not ifdef the properties here as SRP batcher can not handle different layouts.
        CBUFFER_START(UnityPerMaterial)
        half4 _ProjectPosition;
        CBUFFER_END

        // NOTE: Do not ifdef the properties for dots instancing, but ifdef the actual usage.
        // Otherwise you might break CPU-side as property constant-buffer offsets change per variant.
        // NOTE: Dots instancing is orthogonal to the constant buffer above.
        #ifdef UNITY_DOTS_INSTANCING_ENABLED
        UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
            UNITY_DOTS_INSTANCED_PROP(float4, _ProjectPosition)
        UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)
        #define _ProjectPosition UNITY_ACCESS_DOTS_INSTANCED_PROP_FROM_MACRO(float4 , Metadata_ProjectPosition)
        #endif

        TEXTURECUBE(_EnvironmentCube); SAMPLER(sampler_EnvironmentCube);
        ENDHLSL

        // ------------------------------------------------------------------
        //  Forward pass. Shades all light in a single pass. GI + emission + Fog
        Pass
        {
            // Lightmode matches the ShaderPassName set in UniversalRenderPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Universal Render Pipeline
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForwardOnly"}

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 3.0

            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local USE_PIVOTPOSITION USE_CAMERAPOSITION

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            struct Attributes
            {
                float4 positionOS  : POSITION;
                float3 normalOS    : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 uvAndFog    : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;

            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD3;
            #endif

                float3 vertexSH    : TEXCOORD4;
                float4 positionCS  : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings LitPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.uvAndFog.w = ComputeFogFactor(vertexInput.positionCS.z);

            #if USE_CAMERAPOSITION
                float3 objPivot = _WorldSpaceCameraPos.xyz;
            #else
                float3 objPivot = _ProjectPosition.xyz;
            #endif
                output.positionWS = vertexInput.positionWS;
                output.uvAndFog.xyz = (output.positionWS - objPivot) + RotateAboutAxis(float4(0, 1, 0, _ProjectPosition.w), float3(1, 1, 1), output.positionWS - objPivot);

            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                output.shadowCoord = GetShadowCoord(vertexInput);
            #endif

                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
                output.vertexSH = SampleSHVertex(output.normalWS);

                output.positionCS = vertexInput.positionCS;
                return output;
            }

            half4 LitPassFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

            #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord = input.shadowCoord;
            #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
            #else
                float4 shadowCoord = float4(0, 0, 0, 0);
            #endif

                half3 bakedGI = saturate(SampleSHPixel(input.vertexSH, input.normalWS));

                Light mainLight = GetMainLight(shadowCoord, input.positionWS, 0);
                half lighting = mainLight.distanceAttenuation * mainLight.shadowAttenuation;

            #ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, input.positionWS, 0);

                    lighting += light.distanceAttenuation * light.shadowAttenuation;
                }
            #endif
            
                half4 color = 1;
                color.rgb = (bakedGI.rgb + lighting) * SAMPLE_TEXTURECUBE(_EnvironmentCube, sampler_EnvironmentCube, input.uvAndFog.xyz);
                color.rgb = MixFog(color.rgb, input.uvAndFog.w);
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            struct Attributes
            {
                float4 position     : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(input.position.xyz);
                return output;
            }

            half DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                return input.positionCS.z;
            }
            ENDHLSL
        }

        // This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 normalWS     : TEXCOORD2;

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);

                return output;
            }

            void DepthNormalsFragment(
                Varyings input
                , out half4 outNormalWS : SV_Target0
            #ifdef _WRITE_RENDERING_LAYERS
                , out float4 outRenderingLayers : SV_Target1
            #endif
            )
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float3 normalWS = NormalizeNormalPerPixel(input.normalWS);
                outNormalWS = half4(normalWS, 0.0);

                #ifdef _WRITE_RENDERING_LAYERS
                    uint renderingLayers = GetMeshRenderingLayer();
                    outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
                #endif
            }
            ENDHLSL
        }
    }
}