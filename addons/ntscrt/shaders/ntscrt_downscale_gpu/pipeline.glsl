#[compute]
#version 450
// GPU-language translation of NTSCRT Sources/CrtCore/Downscaler.swift.
// Original authors retain copyright. Formula, sampling support, clamped
// boundaries and RGBA8 intermediate quantization are preserved.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D source_image;
layout(set = 0, binding = 1, rgba8) uniform writeonly image2D destination;
layout(push_constant, std430) uniform Dimensions {
    int sw;
    int sh;
    int dw;
    int dh;
    int method; // nearest, nearestAA, bilinear, bicubic, lanczos, area
    int vertical;
    int padding0;
    int padding1;
} d;

float sinc(float x) {
    if (abs(x) < 1e-6) return 1.0;
    float xp = x * 3.14159265358979323846;
    return sin(xp) / xp;
}

float weight(float t) {
    if (d.method == 1) return exp(t * t * -4.0816);
    if (d.method == 2) return max(0.0, 1.0 - abs(t));
    if (d.method == 3) {
        float x = abs(t);
        const float B = 1.0 / 3.0;
        const float C = 1.0 / 3.0;
        float x2 = x * x;
        float x3 = x2 * x;
        if (x < 1.0) {
            return ((12.0 - 9.0 * B - 6.0 * C) * x3
                + (-18.0 + 12.0 * B + 6.0 * C) * x2
                + (6.0 - 2.0 * B)) * (1.0 / 6.0);
        }
        if (x < 2.0) {
            return ((-B - 6.0 * C) * x3
                + (6.0 * B + 30.0 * C) * x2
                + (-12.0 * B - 48.0 * C) * x
                + (8.0 * B + 24.0 * C)) * (1.0 / 6.0);
        }
        return 0.0;
    }
    if (abs(t) >= 3.0) return 0.0;
    return sinc(t) * sinc(t / 3.0);
}

void area(ivec2 pixel) {
    float sx0 = float(pixel.x) * float(d.sw) / float(d.dw);
    float sx1 = float(pixel.x + 1) * float(d.sw) / float(d.dw);
    float sy0 = float(pixel.y) * float(d.sh) / float(d.dh);
    float sy1 = float(pixel.y + 1) * float(d.sh) / float(d.dh);
    int x0 = int(floor(sx0)), x1 = int(ceil(sx1));
    int y0 = int(floor(sy0)), y1 = int(ceil(sy1));
    vec4 accumulated = vec4(0.0);
    float weight_sum = 0.0;
    for (int y = y0; y < y1; y++) {
        float fy = clamp(min(float(y) + 1.0, sy1) - max(float(y), sy0), 0.0, 1.0);
        int cy = clamp(y, 0, d.sh - 1);
        for (int x = x0; x < x1; x++) {
            float fx = clamp(min(float(x) + 1.0, sx1) - max(float(x), sx0), 0.0, 1.0);
            int cx = clamp(x, 0, d.sw - 1);
            float w = fx * fy;
            accumulated += texelFetch(source_image, ivec2(cx, cy), 0) * w;
            weight_sum += w;
        }
    }
    imageStore(destination, pixel, accumulated / max(weight_sum, 1e-6));
}

void separable(ivec2 pixel) {
    bool vertical = d.vertical != 0;
    int source_count = vertical ? d.sh : d.sw;
    int target_count = vertical ? d.dh : d.dw;
    int coordinate = vertical ? pixel.y : pixel.x;
    float scale = max(1.0, float(source_count) / float(target_count));
    float center = (float(coordinate) + 0.5) * float(source_count) / float(target_count) - 0.5;
    float radius = d.method == 3 ? 2.0 : d.method == 4 ? 3.0 : 1.0;
    float support = radius * scale;
    int lo = int(ceil(center - support));
    int hi = int(floor(center + support));
    vec4 accumulated = vec4(0.0);
    float weight_sum = 0.0;
    for (int position = lo; position <= hi; position++) {
        float w = weight((float(position) - center) / scale);
        int clamped = clamp(position, 0, source_count - 1);
        ivec2 source_pixel = vertical ? ivec2(pixel.x, clamped) : ivec2(clamped, pixel.y);
        accumulated += texelFetch(source_image, source_pixel, 0) * w;
        weight_sum += w;
    }
    imageStore(destination, pixel, accumulated / max(weight_sum, 1e-6));
}

void main() {
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    bool filtered = d.method > 0 && d.method < 5;
    int target_height = filtered && d.vertical == 0 ? d.sh : d.dh;
    if (pixel.x >= d.dw || pixel.y >= target_height) return;
    if (d.method == 0) {
        vec2 uv = (vec2(pixel) + 0.5) / vec2(d.dw, d.dh);
        imageStore(destination, pixel, textureLod(source_image, uv, 0.0));
    } else if (d.method == 5) {
        area(pixel);
    } else {
        separable(pixel);
    }
}
