// Live fractal wallpaper: a raymarched 3D fractal behind the desktop, with a
// slowly orbiting camera. Exposes window.Wallpaper for the Fractals app and
// the terminal's `fractal` command.
(function () {
  "use strict";

  const FORMULAS = {
    mandelbox: {
      blurb: "Folded boxes and spheres, endlessly nested",
      dist: 6.2,
      de: `
        vec3 z = p; float dr = 1.0;
        for (int i = 0; i < 10; i++) {
          z = clamp(z, -1.0, 1.0) * 2.0 - z;
          float r2 = dot(z, z);
          if (r2 < 0.25) { z *= 4.0; dr *= 4.0; }
          else if (r2 < 1.0) { z /= r2; dr /= r2; }
          z = z * -1.8 + p; dr = dr * 1.8 + 1.0;
        }
        return length(z) / abs(dr);`,
    },
    mandelbulb: {
      blurb: "The power-8 bulb, a 3D Mandelbrot set",
      dist: 2.5,
      de: `
        vec3 z = p; float dr = 1.0; float r = 0.0;
        for (int i = 0; i < 8; i++) {
          r = length(z);
          if (r > 2.0) break;
          float th = acos(clamp(z.z / r, -1.0, 1.0)) * 8.0;
          float ph = atan(z.y, z.x) * 8.0;
          dr = pow(r, 7.0) * 8.0 * dr + 1.0;
          z = pow(r, 8.0) * vec3(sin(th) * cos(ph), sin(ph) * sin(th), cos(th)) + p;
        }
        return 0.5 * log(r) * r / dr;`,
    },
    sierpinski: {
      blurb: "A tetrahedron of tetrahedra, all the way down",
      dist: 2.9,
      de: `
        vec3 z = p;
        for (int i = 0; i < 12; i++) {
          if (z.x + z.y < 0.0) z.xy = -z.yx;
          if (z.x + z.z < 0.0) z.xz = -z.zx;
          if (z.y + z.z < 0.0) z.zy = -z.yz;
          z = z * 2.0 - vec3(1.0);
        }
        return length(z) * pow(2.0, -12.0);`,
    },
    menger: {
      blurb: "A sponge with holes in every hole",
      dist: 3.4,
      de: `
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
        return d;`,
    },
  };

  const VERTEX = `
    attribute vec2 aPos;
    void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

  function fragment(formula) {
    return `
    precision highp float;
    uniform vec2 uRes;
    uniform float uTime;
    uniform float uHue;
    uniform float uGlow;
    uniform float uDist;

    float DE(vec3 p) { ${formula.de} }

    // The theme's ramp, looping: mint -> teal -> amber -> mint.
    vec3 tint(float t) {
      t = fract(t) * 3.0;
      vec3 mint = vec3(0.239, 0.863, 0.592);
      vec3 teal = vec3(0.180, 0.560, 0.640);
      vec3 amber = vec3(0.910, 0.635, 0.290);
      if (t < 1.0) return mix(mint, teal, smoothstep(0.0, 1.0, t));
      if (t < 2.0) return mix(teal, amber, smoothstep(1.0, 2.0, t));
      return mix(amber, mint, smoothstep(2.0, 3.0, t));
    }

    void main() {
      vec2 uv = (gl_FragCoord.xy * 2.0 - uRes) / uRes.y;
      float a = uTime * 0.045;
      vec3 ro = uDist * vec3(sin(a), 0.32 + 0.18 * sin(a * 0.63), cos(a));
      vec3 ww = normalize(-ro);
      vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
      vec3 vv = cross(uu, ww);
      vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.7 * ww);

      float t = 0.0;
      float steps = 0.0;
      bool hit = false;
      for (int i = 0; i < 96; i++) {
        float h = DE(ro + rd * t);
        if (h < 0.0012 * t) { hit = true; break; }
        t += h;
        steps += 1.0;
        if (t > 24.0) break;
      }

      vec3 bg = mix(vec3(0.027, 0.07, 0.058), vec3(0.085, 0.028, 0.07), clamp(uv.y * 0.4 + 0.5, 0.0, 1.0));
      vec3 col = bg;
      float trap = steps / 96.0;

      if (hit) {
        vec3 p = ro + rd * t;
        vec2 e = vec2(0.0008 * t + 0.0004, 0.0);
        vec3 n = normalize(vec3(
          DE(p + e.xyy) - DE(p - e.xyy),
          DE(p + e.yxy) - DE(p - e.yxy),
          DE(p + e.yyx) - DE(p - e.yyx)));
        vec3 light = normalize(vec3(0.5, 0.8, 0.3));
        float diff = clamp(dot(n, light), 0.0, 1.0);
        float rim = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 3.0);
        float occ = clamp(1.0 - trap * 1.4, 0.15, 1.0);
        vec3 base = tint(fract(trap * 1.6 + uHue));
        col = base * (0.22 + 0.78 * diff) * occ * uGlow;
        col += rim * 0.35 * tint(uHue + 0.5);
        col = mix(col, bg, 1.0 - exp(-0.012 * t * t));
      }
      // Halo from rays that grazed the surface.
      col += tint(uHue + 0.08) * trap * trap * 0.45 * uGlow;
      col *= 1.0 - 0.32 * dot(uv * 0.55, uv * 0.55);
      gl_FragColor = vec4(pow(max(col, 0.0), vec3(0.9)), 1.0);
    }`;
  }

  const canvas = document.getElementById("wallpaper");
  const gl = canvas.getContext("webgl", { antialias: false, powerPreference: "low-power" });
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const state = {
    formula: "mandelbox",
    hue: 0.0,
    glow: 1.15,
    speed: reduceMotion ? 0 : 1,
    scale: 0.5, // render resolution relative to the screen; lowered if frames are slow
  };
  const listeners = new Set();
  let program = null;
  let uniforms = {};
  let clock = 8; // start a little way into the orbit
  let last = performance.now();
  let dirty = true;

  function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader) || "shader failed to compile");
    }
    return shader;
  }

  function useFormula(name) {
    const next = gl.createProgram();
    gl.attachShader(next, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(next, compile(gl.FRAGMENT_SHADER, fragment(FORMULAS[name])));
    gl.bindAttribLocation(next, 0, "aPos");
    gl.linkProgram(next);
    if (!gl.getProgramParameter(next, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(next) || "shader failed to link");
    }
    if (program) gl.deleteProgram(program);
    program = next;
    gl.useProgram(program);
    uniforms = {};
    for (const u of ["uRes", "uTime", "uHue", "uGlow", "uDist"]) {
      uniforms[u] = gl.getUniformLocation(program, u);
    }
  }

  function resize() {
    const ratio = Math.min(window.devicePixelRatio || 1, 2) * state.scale;
    const w = Math.max(1, Math.round(canvas.clientWidth * ratio));
    const h = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      dirty = true;
    }
  }

  function draw() {
    resize();
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.uniform2f(uniforms.uRes, canvas.width, canvas.height);
    gl.uniform1f(uniforms.uTime, clock);
    gl.uniform1f(uniforms.uHue, state.hue + clock * 0.004);
    gl.uniform1f(uniforms.uGlow, state.glow);
    gl.uniform1f(uniforms.uDist, FORMULAS[state.formula].dist);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function frame(now) {
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    if (!document.hidden && (state.speed > 0 || dirty)) {
      clock += dt * state.speed;
      const start = performance.now();
      draw();
      dirty = false;
      // Keep the desktop responsive on slow GPUs: render fewer pixels.
      if (performance.now() - start > 30 && state.scale > 0.3) {
        state.scale = Math.max(0.3, state.scale - 0.05);
      }
    }
    requestAnimationFrame(frame);
  }

  function emit() {
    for (const fn of listeners) fn({ ...state });
  }

  const api = {
    formulas: Object.keys(FORMULAS).map((id) => ({ id, blurb: FORMULAS[id].blurb })),
    get state() {
      return { ...state };
    },
    setFormula(name) {
      if (!FORMULAS[name] || !gl) return false;
      useFormula(name);
      state.formula = name;
      dirty = true;
      emit();
      return true;
    },
    set(key, value) {
      if (!(key in state) || key === "formula" || key === "scale") return;
      state[key] = value;
      dirty = true;
      emit();
    },
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    available: Boolean(gl),
  };
  window.Wallpaper = api;

  if (!gl) {
    canvas.classList.add("no-webgl");
    return;
  }
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  try {
    useFormula(state.formula);
  } catch (err) {
    console.error(err);
    canvas.classList.add("no-webgl");
    api.available = false;
    return;
  }
  window.addEventListener("resize", () => (dirty = true));
  requestAnimationFrame(frame);
})();
