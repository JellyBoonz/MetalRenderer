#include "Camera.hpp"

Camera::Camera(float radius)
    : radius(radius), theta(3.14f), phi(1.57f), target(simd::float3{0.0f, 0.0f, 0.0f}),
      mouseSensitivity(0.005f), movementSpeed(0.2f), fov(45.0f),
      nearPlane(0.01f), farPlane(100.0f), aspectRatio(1.0f)
{
    updateCameraVectors();
}

void Camera::update()
{
    updateCameraVectors();
}

void Camera::updateCameraVectors()
{
    // Clamp phi to avoid flipping at the poles
    const float epsilon = 0.001f;
    phi = fmaxf(epsilon, fminf(phi, M_PI - epsilon));

    // Convert spherical to Cartesian
    position.x = target.x + radius * sinf(phi) * sinf(theta);
    position.y = target.y + radius * cosf(phi);
    position.z = target.z + radius * sinf(phi) * cosf(theta);

    // Keep up vector constant
    up = simd::float3{0, 1, 0};
}

void Camera::processMouseMovement(float xOffset, float yOffset)
{
    theta += xOffset * mouseSensitivity;
    phi -= yOffset * mouseSensitivity * 0.5;

    updateCameraVectors();
}

void Camera::processMouseScroll(float yOffset)
{
    radius -= yOffset * movementSpeed;
    radius = fmaxf(0.5f, radius); // Clamp minimum distance

    updateCameraVectors();
}

simd::float4x4 Camera::getViewMatrix() const
{
    return lookAt(position, target, up);
}

simd::float4x4 Camera::lookAt(simd::float3 eye, simd::float3 center, simd::float3 up) const
{
    // Calculate the forward vector (normalized)
    simd::float3 f = simd::normalize(center - eye);

    // Calculate the right vector (normalized)
    simd::float3 r = simd::normalize(simd::cross(f, up));

    // Recalculate the up vector to ensure orthogonality
    simd::float3 u = simd::cross(r, f);

    // Create the view matrix
    simd::float4x4 viewMatrix = {
        simd::float4{r.x, u.x, -f.x, 0.0f}, // Column 1, from top=left to bottom=right
        simd::float4{r.y, u.y, -f.y, 0.0f}, // Column 2, etc...
        simd::float4{r.z, u.z, -f.z, 0.0f},
        simd::float4{-simd::dot(r, eye), -simd::dot(u, eye), simd::dot(f, eye), 1.0f}};

    return viewMatrix;
}
