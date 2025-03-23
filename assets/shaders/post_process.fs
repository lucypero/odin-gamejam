#version 300 es

precision highp float;
// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;

// Input uniform values
uniform sampler2D texture0;
uniform sampler2D texture1;

// Output fragment color
out vec4 finalColor;

uniform float renderWidth;
uniform float renderHeight;

const float pixelSize = 2.0;

const float gamma = 0.6;
const float numColors = 6.0;

void main()
{
	if (fragTexCoord.y < 0.01 || fragTexCoord.y > 0.99) 
	{
		discard;
		return;
	}
	float dx = pixelSize * (1.0/renderWidth);
	float dy = pixelSize * (1.0/renderHeight);

	vec2 coord = vec2(dx * floor(fragTexCoord.x/dx), -dy*floor(fragTexCoord.y/dy));

	vec4 tc = texture(texture0, coord);
	vec4 texelColor = tc;

	tc = pow(tc, vec4(gamma, gamma, gamma, 1.0));
	tc = tc * numColors;
	tc = floor(tc);
	tc = tc/numColors;
	tc = pow(tc, vec4(1.0/gamma, 1.0/gamma, 1.0/gamma, 1.0));
	tc = tc * 1.2;

    vec4 base_color = mix(tc, texelColor, 0.70);
	vec2 screen_coords = fragTexCoord;
	float dither_mask = texture(texture1, screen_coords/8.0).r;

	float pass = step(1.0 - dither_mask, base_color.r + .92);
	
	finalColor = vec4(pass, pass, pass, 1.0);
	finalColor = vec4(mix(vec3(pass) * 0.9, base_color.rgb, pass), 1.0) * 1.4;
	// finalColor = texelColor;
}
