#version 300 es
precision highp float;

// Input vertex attributes (from vertex shader)
in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

// NOTE: Add your custom variables here

#define     MAX_LIGHTS              4
#define     LIGHT_DIRECTIONAL       0
#define     LIGHT_POINT             1

struct Light {
    int enabled;
    int type;
    float attenuation;
    vec3 position;
    vec3 target;
    vec4 color;
};

// Input lighting values
uniform Light lights[MAX_LIGHTS];
uniform vec4 ambient;
uniform vec3 viewPos;

vec3 CalculateAttenuation(float distance, float light_intensity, vec3 light_color)
{
    float attenuation = 1.0 / (1.0 + 0.1 * distance + 0.01 * distance * distance * distance);
    attenuation *= light_intensity;
    return light_color * attenuation;
}

void main()
{
    // Texel color fetching from texture sampler
    vec4 texelColor = texture(texture0, fragTexCoord);
    vec3 lightDot = vec3(0.0);
    vec3 normal = normalize(fragNormal);
    vec3 viewD = normalize(viewPos - fragPosition);
    vec3 specular = vec3(0.0);

    vec4 tint = colDiffuse * fragColor;

    // NOTE: Implement here your fragment shader code

    for (int i = 0; i < MAX_LIGHTS; i++)
    {
        if (lights[i].enabled == 1)
        {
            vec3 light = vec3(0.0);

            if (lights[i].type == LIGHT_DIRECTIONAL)
            {
                light = -normalize(lights[i].target - lights[i].position);
            }

            if (lights[i].type == LIGHT_POINT)
            {
                light = normalize(lights[i].position - fragPosition);
            }

            float dist_l = length(lights[i].position - fragPosition);

            vec3 att = CalculateAttenuation(dist_l, lights[i].attenuation, lights[i].color.xyz);
            // vec3 att = CalculateAttenuation(dist_l, 1, lights[i].color.xyz);

            float NdotL = max(dot(normal, light), 0.0);
            lightDot += NdotL*att;

            float specCo = 0.0;
            if (NdotL > 0.0) specCo = pow(max(0.0, dot(viewD, reflect(-(light), normal))), 16.0); // 16 refers to shine
            specular += specCo;
        }
    }


    // todo fog
    // dist_to_cam = length(viewPos - fragPosition)
    // float fogV = 

    finalColor = (texelColor*((tint + vec4(specular, 1.0))*vec4(lightDot, 1.0)));
    finalColor += texelColor*(ambient/10.0)*tint;

    // finalColor = texelColor * ambient;

    // Gamma correction
    // finalColor = pow(finalColor, vec4(1.0/2.2));
}
