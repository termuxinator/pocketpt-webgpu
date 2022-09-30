async function init() {
    utils.checkSupport();

    //////////////////////////////////////////
    // Set up WebGPU adapter and load glslang
    // to compile GLSL to SPIR-V
    //////////////////////////////////////////

    const params = utils.parseUrlArgs(window.location);

    const shaderLangMode = ( params.shaderlang == "wgsl" ) ? "wgsl" : "glsl";
    if ( shaderLangMode == "wgsl" ) {
        console.log("wgsl shader path");
    } else {
        console.log("glsl shader path");
    }
    
    var adapter, glslang;
    [adapter, glslang] = await Promise.all([
        navigator.gpu.requestAdapter(),
        
        ( ( shaderLangMode == "glsl" ) ?
            // import("https://unpkg.com/@webgpu/glslang@0.0.15/dist/web-devel/glslang.js").then(m => m.default()), // for single-file solution
            import("./dist/web-devel/glslang.js").then(m => m.default()) // for offline fetching
            : null
        ),
    ]);
    
    ////////////////////////////////////
    // Set up device and canvas context
    ////////////////////////////////////

    const device = await adapter.requestDevice();

    const canvas = document.getElementById("webgpu-canvas");

    const context = canvas.getContext("webgpu");
    const presentationFormat = await navigator.gpu.getPreferredCanvasFormat(); // new code
    //console.log(presentationFormat);
    context.configure({
        device: device,
        format: presentationFormat,
        alphaMode: "opaque",
        usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_DST,
    });


    /////////////////////////////////////////
    // Create scene data
    /////////////////////////////////////////

    const numSpheres = 3;
    const floatsPerSphere = 12;
    const spheresByteSize = floatsPerSphere * 4 * numSpheres;
    const spheresBuffer = device.createBuffer({
        size: spheresByteSize,
        usage: GPUBufferUsage.STORAGE,
        mappedAtCreation: true
    });
    new Float32Array(spheresBuffer.getMappedRange()).set([// center.xyz, radius  |  emmission.xyz, 0  |  color.rgb, refltype     
        
        // these 6 large spheres (radius = 1e5) can be used to model walls, but that causes numerical issues
        // 1e5 - 2.6, 0, 0, 1e5, 0, 0, 0, 0, .85, .25, .25, 1, // Left (DIFFUSE)
        // 1e5 + 2.6, 0, 0, 1e5, 0, 0, 0, 0, .25, .35, .85, 1, // Right
        // 0, 1e5 + 2, 0, 1e5, 0, 0, 0, 0, .75, .75, .75, 1, // Top
        // 0, -1e5 - 2, 0, 1e5, 0, 0, 0, 0, .75, .75, .75, 1, // Bottom
        // 0, 0, -1e5 - 2.8, 1e5, 0, 0, 0, 0, .85, .85, .25, 1, // Back 
        // 0, 0, 1e5 + 7.9, 1e5, 0, 0, 0, 0, 0.1, 0.7, 0.7, 1, // Front

        -1.3, -1.2, -1.3, 0.8,   0.0,   0.0,   0.0, 0.0, 0.999, 0.999, 0.999, 2.0, // Reflective sphere
         1.3, -1.2, -0.2, 0.8,   0.0,   0.0,   0.0, 0.0, 0.999, 0.999, 0.999, 3.0, // Refractive sphere
         0.0,  1.6,  0.0, 0.2, 100.0, 100.0, 100.0, 0.0, 0.0,   0.0,   0.0,   1.0, // Light source
    ]);
    spheresBuffer.unmap();

    const numPlanes = 6;
    const floatsPerPlane = 12;
    const planesByteSize = floatsPerPlane * 4 * numPlanes;
    const planesBuffer = device.createBuffer({
        size: planesByteSize,
        usage: GPUBufferUsage.STORAGE,
        mappedAtCreation: true
    });
    new Float32Array(planesBuffer.getMappedRange()).set([// center.xyz, radius  |  emmission.xyz, 0  |  color.rgb, refltype     
        // model walls as planes instead of as spheres
        -1.0, +0.0, +0.0, +2.6, 0, 0, 0, 0, .85, .25, .25, 1, // Left Wall
        +1.0, +0.0, +0.0, +2.6, 0, 0, 0, 0, .25, .35, .85, 1, // Right Wall
        +0.0, +1.0, +0.0, +2.0, 0, 0, 0, 0, .75, .75, .75, 1, // Top Wall
        +0.0, -1.0, +0.0, +2.0, 0, 0, 0, 0, .75, .75, .75, 1, // Bottom Wall
        +0.0, +0.0, -1.0, +2.8, 0, 0, 0, 0, .85, .85, .25, 1, // Back Wall
        +0.0, +0.0, +1.0, +7.9, 0, 0, 0, 0, 0.1, 0.7, 0.7, 1, // Front Wall
    ]);
    planesBuffer.unmap();

    const numComponents = 4;
    const radiancesBufferLength = numComponents * canvas.width * canvas.height;
    const radiancesBufferByteLength = radiancesBufferLength * 4;
    const radiancesBuffer = device.createBuffer({
        size: radiancesBufferByteLength,
        usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC | GPUBufferUsage.STORAGE,
        mappedAtCreation: true
    });
    const radiancesBufferData = new Float32Array(radiancesBuffer.getMappedRange());
    for (var i = 0; i < radiancesBufferLength; i += 1) {
        radiancesBufferData[i] = 0.0;
    }
    radiancesBuffer.unmap();

    // read-back-to-CPU buffer
    const readbackBuffer = device.createBuffer({
        size: radiancesBufferByteLength,
        usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
        mappedAtCreation: false
    });


    //////////////////////////
    // Compute uniform buffer 
    //////////////////////////
    var pass = 0;
    const samplesPerPixel = 400;
    const computeUniformData = new Uint32Array([
        canvas.width, canvas.height, pass, samplesPerPixel
    ]);
    const computeUniformBuffer = device.createBuffer({
        size: computeUniformData.byteLength,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    });
    device.queue.writeBuffer(computeUniformBuffer, 0, computeUniformData);

    //////////////////////////////////////////////////////////
    // Compute binding layouts 
    // One for reading from A buffers and writing to B,
    // the other for reading from B buffers and writing to A
    //////////////////////////////////////////////////////////
    const computeBindGroupLayout = device.createBindGroupLayout({
        entries: [
            {
                binding: 0, // spheres
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "read-only-storage"
                }
            },
            {
                binding: 1, // planes
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "read-only-storage"
                }
            },
            {
                binding: 2, // radiances
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "storage"
                }
            },
            {
                binding: 3,
                visibility: GPUShaderStage.COMPUTE,
                buffer: {
                    type: "uniform"
                }
            }
        ]
    });
    const computeBindGroup = device.createBindGroup({
        layout: computeBindGroupLayout,
        entries: [
            {
                binding: 0,
                resource: {
                    buffer: spheresBuffer
                }
            },
            {
                binding: 1,
                resource: {
                    buffer: planesBuffer
                }
            },
            {
                binding: 2,
                resource: {
                    buffer: radiancesBuffer
                }
            },
            {
                binding: 3,
                resource: {
                    buffer: computeUniformBuffer
                }
            }
        ]
    });

    ///////////////////////////
    // Create compute pipeline
    ///////////////////////////

    const computeShaderString = ( shaderLangMode == "wgsl" ) ? 
        await utils.loadTextfile("./shaders/pocketpt_ne.wgsl") :
        await utils.loadTextfile("./shaders/pocketpt_ne.cs");

    const computePipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [computeBindGroupLayout] }),
        compute: {
                module: device.createShaderModule({
                code: ( shaderLangMode == "wgsl" ) ? computeShaderString : glslang.compileGLSL(computeShaderString, "compute")
            }),
            entryPoint: "main"
        }
    });

    ////////////////////////////////
    // Kick off path tracing in the compute shader
    ////////////////////////////////
    console.log("path tracing start (async)");
    for (var curr_pass = 0; curr_pass < samplesPerPixel; curr_pass += 1) {
        const commandEncoder = device.createCommandEncoder();
        ///////////////////////
        // Encode compute pass
        ///////////////////////
        const computePass = commandEncoder.beginComputePass();
        computePass.setPipeline(computePipeline);

        // First argument here refers to array index
        // in computePipeline layout.bindGroupLayouts
        computePass.setBindGroup(0, computeBindGroup);
        device.queue.writeBuffer(computeUniformBuffer, 0, new Uint32Array([
            canvas.width, canvas.height, curr_pass, samplesPerPixel
        ]));
        computePass.dispatchWorkgroups((canvas.width + 15) / 16, (canvas.height + 15) / 16);
        computePass.end();
        device.queue.submit([commandEncoder.finish()]);
    }
    console.log("path tracing end (async)");

    {
        const commandEncoder = device.createCommandEncoder();
        commandEncoder.copyBufferToBuffer(radiancesBuffer, 0, readbackBuffer, 0, radiancesBufferByteLength);
        device.queue.submit([commandEncoder.finish()]);

        await readbackBuffer.mapAsync(
            GPUMapMode.READ,
            0, // Offset
            radiancesBufferByteLength // Length
        );
        const copyArrayBuffer = readbackBuffer.getMappedRange(0, radiancesBufferByteLength);
        const dataRaw = copyArrayBuffer.slice();
        readbackBuffer.unmap();
        const data = new Float32Array(dataRaw);
        const imgData = new Uint8ClampedArray({ length: canvas.width * canvas.height * 4 }).fill(128);
        for (let i = 0; i < imgData.length; i += 1) {
            imgData[i] = Math.floor(data[i]);
        }

        // Create canvas
        var readBackCanvas = document.createElement('canvas');
        var readBackCanvasContext = readBackCanvas.getContext('2d');
        readBackCanvas.width = canvas.width;
        readBackCanvas.height = canvas.height;
        var readBackImgData = readBackCanvasContext.getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 0; i < imgData.length; i += 1) {
            readBackImgData.data[i] = imgData[i];
            if (i % 4 == 3) { readBackImgData.data[i] = 255; }
        }
        readBackCanvasContext.putImageData(readBackImgData, 0, 0);
        
        // output image
        var img = new Image();
        img.src = readBackCanvas.toDataURL();
        document.body.appendChild(img);
        await img.decode();
        const imageBitmap = await createImageBitmap(img);
        device.queue.copyExternalImageToTexture(
            { source: imageBitmap },
            { texture: context.getCurrentTexture() },
            [canvas.width, canvas.height]
        );
    }
};

export default init;
