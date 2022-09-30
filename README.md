# pocketpt
A WebGPU path tracer in a single HTML file, inspired by [Reinhold Preiner's single-source GLSL path tracer in 111 lines of code](https://github.com/rpreiner/pocketpt), which itself is based on [Kevin Beason's smallpt](http://kevinbeason.com/smallpt). This project does not quite hit the sub 111 LOC target, but should remain quite readable at less than 485 LOC (WGSL), and less than 430 LOC (GLSL), respectively.

<img src="512x512@8Kspp.png" width="512">

## Usage 

* Platform: 
    - Google Chrome Canary (with --enable-unsafe-webgpu)
    - may run on Firefox Nightly (about:config and dom.webgpu.enabled and gfx.webrender.all) with slight adjustments

* Run: 
    - Simply open the HTML file in your browser, and wait for the rendered image to appear. There is no need for a local HTTP server to circumvent CORS, since CSS, Javascript and WGSL/GLSL shaders are all embedded into the respective HTML files.

* Adjust:
    - rendering resolution - search for "webgpu-canvas" and adjust its (max-)width/height attributes
    - samplesPerPixel - determines how many rays are traced per pixel (the more samples per pixel, the less noisy the result)
    - maxDepth - determines the maximum number of "bounces" per ray (default: 24)

## Implementation Notes

Due to WebGPU's lack of double-precision support, the walls that were originally made up of very large and distant spheres (so they appear locally flat), were replaced by simple planes, due to numerical imprecisions which would otherwise lead to rendering artifacts (surface acne).

In this project, WebGPU runs "headless" (without a "context window"), but for convenience the output buffer is read back from the GPU to the CPU and then displayed in the browser.

An internet connections is required for running the GLSL compute-shader version. The WGSL version will also work offline.

## Creating the single-file HTML
The basic idea is to merge all files(CSS, Javascript, WGSL/GLSL) into a single HTML file. First a python script from [Stackoverflow](https://stackoverflow.com/questions/44646481/merging-js-css-html-into-single-html) merges the CSS files into the HTML skeleton file. Then [pcpp 1.30, A C99 preprocessor written in pure Python](https://pypi.org/project/pcpp/) is used to resolve the '#include' statements in the Javascript and HTML files (also pulls in the shaders from their respective files into the Javascripts as strings). A recent Python 3 install is needed to run these scripts. For convenience, a batch file is provided (Windows only, but should be easily portable to Linux/macOS/...) that executes all necessary steps.
In the root directory of the project, run the following commands to generate the GLSL-compute-shader single-HTML file, and the WGSL-computer-shader single-HTML file, respectively:
* merge_to_single_html.bat GLSL
* merge_to_single_html.bat WGSL

Note that the actual single-file HTMLs on the main branch had some minor manual touch-up applied to them - mainly related to layout/indentation, adding some comments, and re-introducing '#defines' in the GLSL shader string which the C-preprocessor had substituted for their numerical values in the process.

## 
Special thanks go to Reinhold Preiner, and of course Kevin Beason for publishing their respective path tracing source code, as well as to 
[Austin Eng's WebGPU Samples](https://austin-eng.com/webgpu-samples/), [Tarek Sherif's WebGPU Examples](https://github.com/tsherif/webgpu-examples), and [Surma's article 'WebGPU - All of the cores, none of the canvas'](https://surma.dev/things/webgpu/), which were invaluable resources to get this project up and running.

Also of interest:
* [Precision Improvements for Ray/Sphere Intersection by Eric Haines, Johannes Günther, and Thomas Akenine-Möller](https://library.oapen.org/viewer/web/viewer.html?file=/bitstream/handle/20.500.12657/22837/1007324.pdf?sequence=1&isAllowed=y).
* https://prideout.net/emulating-double-precision
* http://blog.hvidtfeldts.net/index.php/2012/07/double-precision-in-opengl-and-webgl/
* https://blog.cyclemap.link/2011-06-09-glsl-part2-emu/
