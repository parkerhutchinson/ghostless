// A light map (gradient map) for the sign-in screen's 3D scene: each
// pixel's lightness is mapped through a ramp of the theme's background
// color, so the model takes on the background's hue. Shadows become a
// darker shade of it, mid-tones the color itself, highlights a lighter
// tint. Used through ImageFilter.shader (SignInModel), which sets
// u_size and u_scene itself; the colors are set from Dart, in order.
#version 460 core

#include <flutter/runtime_effect.glsl>

// Set by the engine: the size of the filtered texture.
uniform vec2 u_size;

// The ramp, in sRGB, 0 to 1: lightness 0, 0.5 and 1.
uniform vec3 u_shadow;
uniform vec3 u_mid;
uniform vec3 u_light;

// How much of the ramp to use: 0 leaves the scene as drawn, 1 is fully
// the background's colors.
uniform float u_amount;

// The scene's fade in, 0 to 1. Applied here because an opacity widget
// around this filter doesn't reach its output under Impeller.
uniform float u_opacity;

// Set by the engine: the scene, as drawn.
uniform sampler2D u_scene;

out vec4 frag_color;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 color = texture(u_scene, uv);
  // Transparent around the model: leave it so the screen shows through.
  if (color.a <= 0.0) {
    frag_color = vec4(0.0);
    return;
  }
  // Premultiplied: back to the drawn color to read its lightness.
  vec3 rgb = color.rgb / color.a;
  float lightness = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
  vec3 mapped = lightness < 0.5
      ? mix(u_shadow, u_mid, lightness * 2.0)
      : mix(u_mid, u_light, (lightness - 0.5) * 2.0);
  vec3 result = mix(rgb, mapped, u_amount);
  frag_color = vec4(result * color.a, color.a) * u_opacity;
}
