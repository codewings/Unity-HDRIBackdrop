Shader "Lookdev/HDRI Backdrop"
{
    Properties
    {
        [HideInInspector]
        _EnvironmentCube("Env Cube", CUBE) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        LOD 100

        Pass
        {
            Tags { "LightMode"="ForwardBase" }

            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma shader_feature USE_PIVOTPOSITION USE_CAMERAPOSITION

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "Lighting.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos    : SV_POSITION;
                float3 uv     : TEXCOORD0;
                fixed3 vlight : TEXCOORD1;

                UNITY_FOG_COORDS(2)
                UNITY_SHADOW_COORDS(3)
            };

            samplerCUBE _EnvironmentCube;
            float4      _ProjectPosition;
            float       _SkylightIntensity;

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

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
            #if USE_CAMERAPOSITION
                float3 objPivot = _WorldSpaceCameraPos.xyz;
            #else
                float3 objPivot = _ProjectPosition;
            #endif
                o.uv = (worldPos - objPivot) + RotateAboutAxis(float4(0, 1, 0, _ProjectPosition.w), float3(1, 1, 1), worldPos - objPivot);

                o.vlight = _SkylightIntensity * saturate(ShadeSH9(float4(UnityObjectToWorldNormal(v.normal), 1.0)));

                TRANSFER_SHADOW(o);

            #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                o.fogCoord.x = o.pos.z;
            #endif
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                half3 atten = LIGHT_ATTENUATION(i);
                half3 color = (i.vlight + atten) * texCUBE(_EnvironmentCube, i.uv).rgb;

            #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                UNITY_CALC_FOG_FACTOR(i.fogCoord.x);
                color = lerp(unity_FogColor.rgb, color, pow(saturate(unityFogFactor), 1 + unity_FogColor.a));
            #endif
                return half4(color, 1);
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
