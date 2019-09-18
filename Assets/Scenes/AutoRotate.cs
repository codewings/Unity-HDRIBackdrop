using UnityEngine;

public class AutoRotate : MonoBehaviour
{
    public Transform center;
    public Vector3 axis = Vector3.up;
    public Vector3 desiredPosition;
    public float radius = 2.0f;
    public float radiusSpeed = 0.5f;
    public float rotationSpeed = 40.0f;

    void Start()
    {
        if (center == null)
            this.enabled = false;
    }

    void Update()
    {
        transform.RotateAround(center.position, axis, rotationSpeed * Time.deltaTime);
        desiredPosition = (transform.position - center.position).normalized * radius + center.position;
        transform.position = Vector3.MoveTowards(transform.position, desiredPosition, Time.deltaTime * radiusSpeed);
    }
}