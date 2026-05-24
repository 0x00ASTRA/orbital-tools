#version 330

in vec2 fragTexCoord;

uniform vec2 center;
uniform float radius;
uniform float atmo_size;
uniform vec4 atmo_color;
uniform vec2 resolution;

out vec4 finalColor;

void main() {
    vec2 pixel = vec2(gl_FragCoord.x, gl_FragCoord.y);
    float dist = length(pixel - center);
    float outer = radius + atmo_size;

    if (dist > outer || dist < radius * 0.98) {
        finalColor = vec4(0.0);
        return;
    }

    float t = (dist - radius) / atmo_size;
    t = clamp(t, 0.0, 1.0);

    float inner_feather = smoothstep(radius * 0.98, radius, dist);
    float alpha = pow(1.0 - t, 1.2) * atmo_color.a * inner_feather;

    finalColor = vec4(atmo_color.rgb, alpha);
}
