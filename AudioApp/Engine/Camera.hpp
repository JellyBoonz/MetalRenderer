#pragma once
#include <simd/simd.h>
#include <GLFW/glfw3.h>

class Camera
{
public:
    Camera(float radius = 2.0f);

    float aspectRatio;
    float fov;
    float nearPlane;
    float farPlane;

    simd::float3 target;

    void update();
    void processMouseMovement(float xOffset, float yOffset);
    void processMouseScroll(float yOffset);

    simd::float4x4 getViewMatrix() const;
    simd::float4x4 getProjectionMatrix() const;
    simd::float4x4 lookAt(simd::float3 eye, simd::float3 center, simd::float3 up) const;

    void setAspectRatio(float aspectRatio);

    simd::float3 getPosition() const { return position; }

private:
    // Camera attributes
    simd::float3 position;
    simd::float3 up;

    // Spherical coordinates
    float radius;
    float theta; // Horizontal angle
    float phi;   // Vertical angle

    // Camera options
    float movementSpeed;
    float mouseSensitivity;
    float zoom;

    void updateCameraVectors();
};
