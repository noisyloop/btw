#!/usr/bin/env bash
# Builds the live wallpaper's shaders: one .qsb per fractal, from the same
# raymarcher as desktop/wallpaper.js. The .qsb files are committed, so
# installing btw doesn't need Qt's shader tools; rerun this after changing
# fractal.frag.in. Needs qsb (Arch: qt6-shadertools).
set -euo pipefail
cd "$(dirname "$0")"
qsb=$(command -v qsb || echo /usr/lib/qt6/bin/qsb)

de_mandelbox='
  vec3 z = p; float dr = 1.0;
  for (int i = 0; i < 10; i++) {
    z = clamp(z, -1.0, 1.0) * 2.0 - z;
    float r2 = dot(z, z);
    if (r2 < 0.25) { z *= 4.0; dr *= 4.0; }
    else if (r2 < 1.0) { z /= r2; dr /= r2; }
    z = z * -1.8 + p; dr = dr * 1.8 + 1.0;
  }
  return length(z) / abs(dr);'
de_mandelbulb='
  vec3 z = p; float dr = 1.0; float r = 0.0;
  for (int i = 0; i < 8; i++) {
    r = length(z);
    if (r > 2.0) break;
    float th = acos(clamp(z.z / r, -1.0, 1.0)) * 8.0;
    float ph = atan(z.y, z.x) * 8.0;
    dr = pow(r, 7.0) * 8.0 * dr + 1.0;
    z = pow(r, 8.0) * vec3(sin(th) * cos(ph), sin(ph) * sin(th), cos(th)) + p;
  }
  return 0.5 * log(r) * r / dr;'
de_sierpinski='
  vec3 z = p;
  for (int i = 0; i < 12; i++) {
    if (z.x + z.y < 0.0) z.xy = -z.yx;
    if (z.x + z.z < 0.0) z.xz = -z.zx;
    if (z.y + z.z < 0.0) z.zy = -z.yz;
    z = z * 2.0 - vec3(1.0);
  }
  return length(z) * pow(2.0, -12.0);'
de_menger='
  vec3 q = abs(p) - vec3(1.0);
  float d = length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
  float s = 1.0;
  for (int m = 0; m < 4; m++) {
    vec3 a = mod(p * s, 2.0) - 1.0;
    s *= 3.0;
    vec3 r = abs(1.0 - 3.0 * abs(a));
    float c = (min(max(r.x, r.y), min(max(r.y, r.z), max(r.z, r.x))) - 1.0) / s;
    d = max(d, c);
  }
  return d;'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for name in mandelbox mandelbulb sierpinski menger; do
  var="de_$name"
  DE="${!var}" python3 -c 'import os,sys; sys.stdout.write(open("fractal.frag.in").read().replace("@DE@", os.environ["DE"]))' >"$tmp/$name.frag"
  "$qsb" --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$name.frag.qsb" "$tmp/$name.frag"
  echo "built $name.frag.qsb"
done
