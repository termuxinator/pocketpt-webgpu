# pocketpt
A WebGPU path tracer in a single HTML file, inspired by [Reinhold Preiner's single-source GLSL path tracer in 111 lines of code](https://github.com/rpreiner/pocketpt), which itself is based on [Kevin Beason's smallpt](http://kevinbeason.com/smallpt). This project does not quite hit the sub 111 LOC target, but should remain quite readable at about 490 LOC.

<img src="512x512@8Kspp.png" width="512">

## Usage 

* Platform: 
    - Google Chrome Canary (with --enable-unsafe-webgpu)
    - may run on Firefox Nightly (about:config and dom.webgpu.enabled and gfx.webrender.all) with slight adjustments

* Run: 
    - Simply open the HTML file in your browser, and wait for the rendered image to appear. There is no need for a local HTTP server to circumvent CORS, since CSS, Javascript and WGSL shaders are all embedded into the index.html file.

* Adjust:
    - rendering resolution - search for "webgpu-canvas" and adjust it's (max-)width/height
    - samplesPerPixel - determines how many rays are traced per pixel (the more samples per pixel, the less noisy the result)
    - maxDepth - determines the maximum number of "bounces" per ray (default: 24)

## Implementation Notes

Due to WebGPU's lack of double-precision support, the walls that were originally made up of very large and distant spheres (so they appear locally flat), were replaced by simple planes, due to numerical imprecisions which would otherwise lead to rendering artifacts (surface acne).

## 
Special thanks go to Reinhold Preiner, and of course Kevin Beason for publishing their respective path tracing source code, as well as to 
[Austin Eng's WebGPU Samples](https://austin-eng.com/webgpu-samples/), [Tarek Sherif's WebGPU Examples](https://github.com/tsherif/webgpu-examples), and [Surma's article 'WebGPU - All of the cores, none of the canvas'](https://surma.dev/things/webgpu/), which were invaluable resources to get this project up and running.

Also of interest:
* [Precision Improvements for Ray/Sphere Intersection by Eric Haines, Johannes Günther, and Thomas Akenine-Möller](https%3A%2F%2Flink.springer.com%2Fcontent%2Fpdf%2F*%2010.1007%2F978-1-4842-4427-2_7.pdf).
* https://prideout.net/emulating-double-precision
* http://blog.hvidtfeldts.net/index.php/2012/07/double-precision-in-opengl-and-webgl/
* https://blog.cyclemap.link/2011-06-09-glsl-part2-emu/