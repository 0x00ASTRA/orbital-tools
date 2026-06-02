#version 330

in vec2 fragTexCoord;
in vec3 fragPos;
in vec4 fragColor;

out vec4 finalColor;

uniform float lineWidth = 0.008;
uniform int latLines = 18;
uniform int lonLines = 36;
uniform vec4 gridColor = vec4(0.4, 0.8, 1.0, 0.8);
uniform vec4 baseColor = vec4(0.05, 0.05, 0.15, 1.0);

const float PI = 3.14159265358979;
const float TAU = PI * 2.0;

void main()
{
    vec3 n = normalize(fragPos);

    float lon = atan(n.x, n.z);
    float lat = asin(clamp(n.y, -1.0, 1.0));

    float u = lon / TAU + 0.5;
    float v = lat / PI + 0.5;

    float du = abs(dFdx(u));
    if (du > 0.3) discard;

    vec2 uv = vec2(u, v);

    float latCell = fract(uv.y * float(latLines));
    float lonCell = fract(uv.x * float(lonLines));

    float latDist = min(latCell, 1.0 - latCell);
    float lonDist = min(lonCell, 1.0 - lonCell);

    float latCellSize = 1.0 / float(latLines);
    float lonCellSize = 1.0 / float(lonLines);

    // pixel footprint in UV space per cell
    float latPx = fwidth(uv.y * float(latLines));
    float lonPx = fwidth(uv.x * float(lonLines));

    float latEdge = lineWidth / latCellSize;
    float lonEdge = lineWidth / lonCellSize;

    // AA: transition over 1 pixel worth of UV
    float latLine = 1.0 - smoothstep(latEdge - latPx, latEdge + latPx, latDist);
    float lonLine = 1.0 - smoothstep(lonEdge - lonPx, lonEdge + lonPx, lonDist);

    float grid = max(latLine, lonLine);

    finalColor = mix(baseColor, gridColor, grid * gridColor.a);
}
