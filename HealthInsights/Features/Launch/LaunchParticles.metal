#include <metal_stdlib>
using namespace metal;

// The launch screen's heart, drawn as point sprites.
//
// Everything below is per-vertex work on eighty-six thousand points, which is
// nothing for a GPU and was impossible for the thing it replaces: a SwiftUI
// TimelineView redrawing on the main thread, on a screen that exists precisely
// because the main thread is busy.
//
// The point cloud itself is built in InsightKit (`LaunchParticleField`), where
// its shape can be tested. This file only turns and projects it.

struct LaunchUniforms {
    float  heartAngle;
    float  ringAngle;
    float  scale;        // pixels per model unit
    float2 centre;       // pixels
    float2 viewport;     // pixels
    float  pointSize;    // pixels, before perspective
};

struct ParticleOut {
    float4 position [[position]];
    float  size     [[point_size]];
    half4  colour;
};

vertex ParticleOut launchParticleVertex(uint vid [[vertex_id]],
                                        const device float4 *points [[buffer(0)]],
                                        constant LaunchUniforms &u [[buffer(1)]])
{
    float4 p = points[vid];
    bool isRing = p.w > 0.5;

    // The ring turns slower than the heart so the two never lock into one rigid
    // object — which is what makes a rotating cloud read as a solid instead.
    float a = isRing ? u.ringAngle : u.heartAngle;
    float c = cos(a);
    float s = sin(a);

    // Turn about the screen-vertical axis. For this heart surface that is model
    // z (lobes at +z, point at -z), with model y as the direction the camera
    // looks down. Rotating x against z instead spins it in the screen plane like
    // a pinwheel; the first prototype did exactly that.
    float rx = c * p.x - s * p.y;
    float ry = s * p.x + c * p.y;      // depth
    float rz = p.z;

    float persp = 3.6 / (3.6 + ry);
    float2 pixel = u.centre + float2(rx, -rz) * persp * u.scale;

    ParticleOut o;
    float2 ndc = pixel / u.viewport * 2.0 - 1.0;
    o.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    o.size = max(u.pointSize * persp, 1.0);

    // Front-lit: points nearer the camera pick up a white highlight. This is
    // what gives a flat scatter of dots the sense of a volume, and it is the
    // only lighting there is — there is no normal to shade with, because a point
    // sprite has no surface.
    float lit = clamp((0.45 - ry) / 1.35, 0.0, 1.0);
    half3 base = isRing ? half3(0.804h, 0.376h, 0.376h)
                        : half3(0.776h, 0.306h, 0.306h);
    half3 col = mix(base, half3(1.0h), half(lit * 0.82));

    // Premultiplied, so the blend below is a plain source-over and the order the
    // points arrive in stops mattering as much. It matters *some* — there is no
    // depth sort, because depth changes every frame under this rotation and
    // sorting eighty-six thousand points per frame would cost more than the
    // draw. Verified by eye against a sorted reference render: at these alphas
    // the difference is not visible.
    half alpha = half(clamp((isRing ? 0.40 : 0.30) * pow(persp, 2.2), 0.0, 1.0));
    o.colour = half4(col * alpha, alpha);
    return o;
}

fragment half4 launchParticleFragment(ParticleOut in [[stage_in]],
                                      float2 coord [[point_coord]])
{
    // A soft round dot rather than a square one. Without this the mist is
    // visibly made of pixels at close range, which is the whole complaint the
    // procedural version exists to answer.
    float d = length(coord - 0.5) * 2.0;
    half fade = half(smoothstep(1.0, 0.4, d));
    return in.colour * fade;
}
