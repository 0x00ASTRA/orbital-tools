#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform vec2 resolution;
uniform vec3 cam_forward; // Normalized camera forward vector
uniform vec3 cam_up;      // Normalized camera up vector

// Simple 3D hash function for procedural noise
float hash3(vec3 p) {
    p = fract(p * vec3(443.8975, 397.2973, 491.1871));
    p += dot(p.xyz, p.yzx + 19.19);
    return fract(p.x * p.y * p.z);
}

void main() {
    // 1. Normalize screen coordinates to -1.0 .. 1.0 (Aspect ratio corrected)
    vec2 uv = (gl_FragCoord.xy - 0.5 * resolution) / resolution.y;

    // 2. Reconstruct a 3D view vector for the current screen pixel
    vec3 cam_right = normalize(cross(cam_forward, cam_up));
    vec3 ray_dir = normalize(cam_forward + uv.x * cam_right + uv.y * cam_up);

    // 3. Grid cell coordinates to isolate individual stars
    vec3 grid_pos = floor(ray_dir * 150.0); // Adjust grid size for star density
    
    // Generate a unique value for each grid cell
    float n = hash3(grid_pos);

    vec4 color = vec4(0.0);

    // Only draw a star if the hash passes a threshold (controls scarcity)
    if (n > 0.985) {
        // Calculate a random offset inside the grid cell for the star center
        vec3 star_center = grid_pos + vec3(hash3(grid_pos + 1.0), hash3(grid_pos + 2.0), hash3(grid_pos + 3.0));
        
        // Find distance from current pixel ray to the star's center position
        float dist = length(ray_dir * 150.0 - star_center);
        
        // Star size and sharpness interpolation
        float star_intensity = smoothstep(0.6, 0.0, dist);
        
        // Vary star brightness and color temperature slightly based on hash values
        vec3 star_color = vec3(0.8 + 0.2 * hash3(grid_pos + 4.0), 
                               0.85 + 0.15 * hash3(grid_pos + 5.0), 
                               1.0);

        color = vec4(star_color * star_intensity, 1.0);
    }

    finalColor = color;
}
