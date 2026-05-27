#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform float atmo_ratio;   // (atmo_radius - planet_radius) / atmo_radius
uniform vec4 atmo_color;

void main() {
    // Map texture coords to [-1, 1] space, origin at centre
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float dist = length(uv);

    float inner = 1.0 - atmo_ratio;

    const float edge_eps = 0.005;

    float inner_mask = smoothstep(inner - edge_eps, inner, dist);
    float outer_mask = 1.0 - smoothstep(1.0 - edge_eps, 1.0, dist);
    float ring_mask = inner_mask * outer_mask;

    float chord = sqrt(max(0.0, 1.0 - dist * dist));

    float max_chord = sqrt(1.0 - inner * inner);
    float t = chord / max_chord;

    
    float alpha = atmo_color.a * t * ring_mask;

    
    alpha = pow(alpha, 2.0);   

    finalColor = vec4(atmo_color.rgb, alpha);
}
