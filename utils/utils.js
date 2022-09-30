(function() {
    window.utils = {        
        checkSupport() {
            if (!navigator.gpu) {
                document.body.innerHTML = `
                    <h1>WebGPU not supported!</h1>
                    <div>
                        WebGPU is currently only supported in <a href="https://www.google.com/chrome/canary/">Chrome Canary</a> with the flag "enable-unsafe-webgpu" enabled.
                    </div>
                `;
                throw new Error("WebGPU not supported");
            }
        },
        reflectVarName(varName) { // note: surround variable with cury braces at call site!
            return Object.keys(varName)[0];
        },
        loadTextfile(url) {
            return fetch(url).then($ => $.text());
        },
        parseUrlArgs(location) {
            var params = {};
            location.search.slice(1).split("&").forEach(function(pair) {
               pair = pair.split("=");
               params[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1]);
            });
            return params;            
        },
    }
})();

