using UnityEngine;

[ExecuteInEditMode]
public class HDRIBackdrop : MonoBehaviour
{
    [Header("HDRI Projection")]
    [Range(0.0f, 360.0f)]
    public float   HDRIAngle           = 0;
    public Vector3 ProjectCenter       = Vector3.zero;
    public float   EnvDomeScale        = 25.0f;
    public bool    CameraProjection    = false;
    public Cubemap EnvironmentCube     = null;

    [Header("Sky Light & Environment")]
    public bool    SyncEnvironment     = true;
    public string  CubemapParamName    = "_Tex";
    public string  RotationParamName   = "_Rotation";

    private Material BackdropMaterial
    {
        get
        {
            return (Application.isPlaying) ? mCachedRenderer.material : mCachedRenderer.sharedMaterial;
        }
    }

    public void UpdateEnvironment()
    {
        mCachedReflectionProbe.RenderProbe();

        DynamicGI.UpdateEnvironment();
    }

    void Start()
    {
        mCachedRenderer = GetComponent<Renderer>();

        if (mCachedRenderer == null)
        {
            enabled = false;
        }

    #if UNITY_EDITOR
        // unpack after created from prefab
        if (UnityEditor.PrefabUtility.IsPartOfAnyPrefab(gameObject))
        {
            UnityEditor.PrefabUtility.UnpackPrefabInstance(gameObject, UnityEditor.PrefabUnpackMode.Completely, UnityEditor.InteractionMode.AutomatedAction);
        }
    #endif
    }

    void Update()
    {
        var m = BackdropMaterial;

#if UNITY_EDITOR
        // skip if open prefab in asset editor
        if (gameObject.scene.path == null || gameObject.scene.name == null)
            return;

        mCachedRenderer = GetComponent<Renderer>();
        mCachedReflectionProbe = GetComponentInChildren<ReflectionProbe>();

        transform.localScale = new Vector3(EnvDomeScale, EnvDomeScale, EnvDomeScale);

        if (m != null)
        {
            m.SetTexture("_EnvironmentCube", EnvironmentCube);

            if (CameraProjection)
            {
                m.EnableKeyword("_POSITIONTYPE_USE_CAMERAPOSITION");
                m.DisableKeyword("_POSITIONTYPE_USE_PIVOTPOSITION");
            }
            else
            {
                m.DisableKeyword("_POSITIONTYPE_USE_CAMERAPOSITION");
                m.EnableKeyword("_POSITIONTYPE_USE_PIVOTPOSITION");
            }
        }

        if (SyncEnvironment)
        {
            var skybox = RenderSettings.skybox;
            if (skybox != null)
            {
                if (string.IsNullOrEmpty(CubemapParamName) == false && skybox.HasProperty(CubemapParamName))
                {
                    skybox.SetTexture(CubemapParamName, EnvironmentCube);
                }
                if (string.IsNullOrEmpty(RotationParamName) == false && skybox.HasProperty(RotationParamName))
                {
                    skybox.SetFloat(RotationParamName, HDRIAngle);
                }

                if (mCachedReflectionProbe && mCachedReflectionProbe.enabled)
                {
                    // make sure all settings is we wanted
                    mCachedReflectionProbe.mode = UnityEngine.Rendering.ReflectionProbeMode.Realtime;
                    mCachedReflectionProbe.refreshMode = UnityEngine.Rendering.ReflectionProbeRefreshMode.ViaScripting;
                    mCachedReflectionProbe.size = new Vector3(EnvDomeScale * 2.0f, EnvDomeScale, EnvDomeScale * 2.0f);
                    mCachedReflectionProbe.center = new Vector3(0, EnvDomeScale * 0.5f, 0);
                    mCachedReflectionProbe.cullingMask = 0;
                    mCachedReflectionProbe.resolution = 64;
                    mCachedReflectionProbe.nearClipPlane = 0.3f;
                    mCachedReflectionProbe.farClipPlane = EnvDomeScale * 2.01f;

                    // re-capture if we are playing
                    if (Application.isPlaying)
                    {
                        UpdateEnvironment();
                    }
                }
            }
        }

        mCachedRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        mCachedRenderer.receiveShadows    = true;
#endif


        if (m != null)
        {
            var v = transform.localToWorldMatrix.MultiplyPoint(Vector3.zero) + transform.rotation * ProjectCenter;
            m.SetVector("_ProjectPosition", new Vector4(v.x, v.y, v.z, HDRIAngle / 180.0f * Mathf.PI));
        }

        if (mCachedReflectionProbe)
        {
            mCachedReflectionProbe.intensity = RenderSettings.ambientIntensity;
        }
    }

    Renderer        mCachedRenderer;
    ReflectionProbe mCachedReflectionProbe;
}
