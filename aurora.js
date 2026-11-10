// aurora.js
// AuroraShaderJS Native – OGL Aurora Background for Hyggshi OS
(function () {
    // Load OGL
    function loadOGL(cb) {
      if (window.OGL) return cb();
      var s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/ogl@0.0.41/dist/ogl.min.js';
      s.onload = cb;
      document.head.appendChild(s);
    }
  
    function hexToRgbArr(hex) {
      let c = new window.OGL.Color(hex);
      return [c.r, c.g, c.b];
    }
  
    function startAurora({
      colorStops = ["#5227FF", "#7cff67", "#5227FF"],
      amplitude = 1.0, blend = 0.5, speed = 1.0
    } = {}) {
      let cEl = document.createElement('div');
      cEl.style = 'position:fixed;z-index:0;inset:0;pointer-events:none;overflow:hidden;';
      document.body.prepend(cEl);
  
      let renderer = new window.OGL.Renderer({ dpr: window.devicePixelRatio, alpha: true });
      let gl = renderer.gl;
      gl.clearColor(0, 0, 0, 0);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  
      let geometry = new window.OGL.Triangle(gl);
  
      const VERT = `#version 300 es
  in vec2 position;
  void main() {
    gl_Position = vec4(position, 0.0, 1.0);
  }`;
  
      const FRAG = `#version 300 es
  precision highp float;
  uniform float uTime, uAmplitude, uBlend;
  uniform vec3 uColorStops[3];
  uniform vec2 uResolution, uMouse;
  out vec4 fragColor;
  
  vec3 permute(vec3 x){return mod(((x*34.0)+1.0)*x,289.0);}
  float snoise(vec2 v){
    const vec4 C=vec4(0.211324865405187,0.366025403784439,-0.577350269189626,0.024390243902439);
    vec2 i=floor(v+dot(v,C.yy));
    vec2 x0=v-i+dot(i,C.xx);
    vec2 i1=(x0.x>x0.y)?vec2(1.0,0.0):vec2(0.0,1.0);
    vec4 x12=x0.xyxy+C.xxzz;
    x12.xy-=i1;
    i=mod(i,289.0);
    vec3 p=permute(permute(i.y+vec3(0.0,i1.y,1.0))+i.x+vec3(0.0,i1.x,1.0));
    vec3 m=max(0.5-vec3(dot(x0,x0),dot(x12.xy,x12.xy),dot(x12.zw,x12.zw)),0.0);
    m=m*m; m=m*m;
    vec3 x=2.0*fract(p*C.www)-1.0;
    vec3 h=abs(x)-0.5;
    vec3 ox=floor(x+0.5);
    vec3 a0=x-ox;
    m*=1.79284291400159-0.85373472095314*(a0*a0+h*h);
    vec3 g; g.x=a0.x*x0.x+h.x*x0.y; g.yz=a0.yz*x12.xz+h.yz*x12.yw;
    return 130.0*dot(m,g);
  }
  struct ColorStop { vec3 color; float position; };
  #define COLOR_RAMP(colors,factor,finalColor){ \
    int index=0;\
    for(int i=0;i<2;i++){\
      ColorStop currentColor=colors[i];\
      bool inBetween=currentColor.position<=factor;\
      index=int(mix(float(index),float(i),float(inBetween)));\
    }\
    ColorStop currentColor=colors[index];\
    ColorStop nextColor=colors[index+1];\
    float range=nextColor.position-currentColor.position;\
    float lerpFactor=(factor-currentColor.position)/range;\
    finalColor=mix(currentColor.color,nextColor.color,lerpFactor);\
  }
  void main(){
    vec2 uv=gl_FragCoord.xy/uResolution;
    vec2 m = uMouse / uResolution;
  
    ColorStop colors[3];
    colors[0]=ColorStop(uColorStops[0],0.0);
    colors[1]=ColorStop(uColorStops[1],0.5);
    colors[2]=ColorStop(uColorStops[2],1.0);
  
    vec3 rampColor; COLOR_RAMP(colors, uv.x, rampColor);
    float noise = snoise(vec2(uv.x * 3.0, uTime * 0.2 + m.x * 0.5));
    float waveHeight = uv.y - (noise * 0.15 * uAmplitude);
    float fade = smoothstep(0.0, 0.4, uv.y);
    waveHeight = mix(uv.y, waveHeight, fade);
    float core = 0.5;
    float intensity = smoothstep(core-uBlend,core+uBlend,waveHeight);
    vec3 auroraColor = intensity * rampColor;
    float auroraAlpha = intensity;
    fragColor = vec4(auroraColor*auroraAlpha, auroraAlpha);
  }`;
  
      let program = new window.OGL.Program(gl, {
        vertex: VERT,
        fragment: FRAG,
        uniforms: {
          uTime: { value: 0 },
          uAmplitude: { value: amplitude },
          uBlend: { value: blend },
          uResolution: { value: [window.innerWidth, window.innerHeight] },
          uColorStops: { value: colorStops.map(hexToRgbArr) },
          uMouse: { value: [0, 0] }
        }
      });
      let mesh = new window.OGL.Mesh(gl, { geometry, program });
      cEl.appendChild(gl.canvas);
  
      function resize() {
        const width = window.innerWidth, height = window.innerHeight;
        renderer.setSize(width, height);
        program.uniforms.uResolution.value = [width, height];
      }
      window.addEventListener('resize', resize);
      resize();
  
      let mouse = [0, 0];
      window.addEventListener('mousemove', (e) => {
        mouse[0] += (e.clientX - mouse[0]) * 0.06;
        mouse[1] += (e.clientY - mouse[1]) * 0.06;
      });
  
      let tId = 0;
      function animate(t) {
        tId = requestAnimationFrame(animate);
        program.uniforms.uTime.value = (t || performance.now()) * 0.001 * speed;
        program.uniforms.uMouse.value = mouse;
        renderer.render({ scene: mesh });
      }
      animate();
    }
  
    window.AuroraShader = startAurora;
    loadOGL(function () { /* OGL loaded */ });
  })();