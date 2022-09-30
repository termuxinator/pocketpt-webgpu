struct Ray {
    o: vec3<f32>,
    d: vec3<f32>,
}

struct Sphere {
    geo: vec4<f32>,
    e: vec4<f32>,
    c: vec4<f32>,
}

struct Plane {
    equation: vec4<f32>,
    e: vec4<f32>,
    c: vec4<f32>,
}

struct Spheres {
    data: array<Sphere>,
}

struct Planes {
    //planes: array<array<vec4<f32>,3u>>,
    data: array<Plane>,
}

struct AccRad {
    data: array<vec4<f32>>,
}

struct Global {
    imgdim_samplecount: vec4<u32>,
}

struct HitInfo {
    rayT: f32,
    objType: u32,
    objIdx: u32,
}

@group(0) @binding(0) var<storage> spheres: Spheres;
@group(0) @binding(1) var<storage> planes: Planes;
@group(0) @binding(2) var<storage, read_write> accRad: AccRad;
@group(0) @binding(3) var<uniform> u_global: Global;

var<private> gl_GlobalInvocationID: vec3<u32>;

const ePlane : u32 =     0u;
const eSphere: u32 =     1u;

// ### material types
const eDiffuseMaterial    : u32 =    1u;
const eReflectiveMaterial : u32 =    2u;
const eRefractiveMaterial : u32 =    3u;


fn rand01(val_in: vec3<u32>) -> vec3<f32> {
    var val = val_in;
    for (var i: i32 = 0; i < 3; i += 1 ) { val = ((vec3<u32>(val.x >> 8u, val.y >> 8u, val.z >> 8u )) ^ val.yzx) * 1103515245u; }
    return vec3<f32>(val) * (1.0 / f32(0xffffffffu));
}

fn intersect(ray: Ray, hitInfo: ptr<function, HitInfo>) -> bool {
    // float d, inf = 1e20, t = inf, eps = 1e-4;   // intersect ray with scene
    let eps: f32 = 1.0e-4;
    let inf: f32 = 1.0e20;
    var d: f32 = inf;
    var t: f32 = inf;
    
    for ( var i: u32 = 0u; i < arrayLength( &planes.data ); i += 1u ) {
        let planeEqu = planes.data[i].equation;
        let denom = dot( ray.d, planeEqu.xyz );
        if ( denom > eps ) {
            d = ( planeEqu.w - dot( ray.o, planeEqu.xyz ) ) / denom ;
            if ( d < t ) {
                t = d; *(hitInfo).objType = ePlane; *(hitInfo).objIdx = i;
            }
        }
    }

    for ( var i: u32 = 0u; i < arrayLength( &spheres.data ); i += 1u ) {
        let sphere = spheres.data[i]; // perform intersection test in double precision
        // Compute a, b, c, for quadratic in ray-sphere intersection
        //    (Math can be simplified; left in its entirety for clarity.)
        
        let toCtr = ray.o - sphere.geo.xyz;
        let a = dot( ray.d, ray.d );
        let b = 2.0 * dot( ray.d, toCtr );
        let c = dot( toCtr, toCtr ) - sphere.geo.w * sphere.geo.w;

        // Checks if sqrt(b^2 - 4*a*c) in quadratic equation has real answer
        let discriminant = b * b - 4.0 * a * c;
        if ( discriminant < 0.0 ) { continue; }

        let sqrtVal = sqrt(discriminant);

        let q = select( -0.5*(b - sqrtVal), -0.5*(b + sqrtVal), b >= 0.0 );

        // we don't bother testing for division by zero
        let d1 = q / a;
        let d2 = c / q;
        d = select (
            select( inf, max(d1,d2), max(d1,d2) > eps ),
            min(d1,d2),
            min(d1,d2) > eps );

        if (d < t) { 
            t=d; *(hitInfo).objType = eSphere; *(hitInfo).objIdx = i;
        }
    }

    if (t < inf) {
        *(hitInfo).rayT = t;
        return true;
    }
    return false;
}


@compute @workgroup_size(16, 16, 1) 
fn main(@builtin(global_invocation_id) param: vec3<u32>) {
    gl_GlobalInvocationID = param;
    
    let imgdim = u_global.imgdim_samplecount.xy;
    let samps = u_global.imgdim_samplecount.zw;
    let pix = gl_GlobalInvocationID.xy;
    if (pix.x >= imgdim.x || pix.y >= imgdim.y) { return; }
    let gid = pix.y * imgdim.x + (imgdim.x - 1u - pix.x);

    //-- define camera
    let cam = Ray(vec3<f32>(0.0, 0.52, 7.4), normalize(vec3<f32>(0.0, -0.06, -1.0)));
    // var cx: vec3<f32>;
    // if ( abs(cam.d.y) < 0.9 ) {
    //     cx = normalize(cross(cam.d, vec3<f32>(0.0, 1.0, 0.0)));
    // } else {
    //     cx = normalize(cross(cam.d, vec3<f32>(0.0, 0.0, 1.0)));
    // }     
    var cx = normalize( cross( cam.d, select( vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, 1.0, 0.0), abs(cam.d.y) < 0.9 ) ) );

    var cy = cross(cx, cam.d);
    //const vec2 sdim = vec2(0.036, 0.024);    // sensor size (36 x 24 mm)
    let sdim = vec2<f32>(0.03); // TODO: this must match the ratio of the canvas

    //-- sample sensor
    let rnd2 = 2.0 * rand01(vec3<u32>(pix, samps.x)).xy;   // vvv tent filter sample  
    let tent = vec2<f32>( select( 1.0 - sqrt(2.0 - rnd2.x), sqrt(rnd2.x) - 1.0, rnd2.x < 1.0 ), 
                          select( 1.0 - sqrt(2.0 - rnd2.y), sqrt(rnd2.y) - 1.0, rnd2.y < 1.0 ) );
    let s = ((vec2<f32>(pix) + 0.5 * (0.5 + vec2<f32>((f32(samps.x) * 0.5) % 2.0, f32(samps.x) % 2.0) + tent)) / vec2<f32>(imgdim) - 0.5) * sdim;
    let spos = cam.o + cx * s.x + cy * s.y;
    let lc = cam.o + cam.d * 0.035;           // sample on 3d sensor plane
    var accrad = vec3<f32>(0);
    var accmat = vec3<f32>(1);        // initialize accumulated radiance and bxdf
    var ray = Ray(lc, normalize(lc - spos));      // construct ray
    
    var emissive: f32 = 1.0;
    //-- loop over ray bounces
    let maxDepth: u32 = 24u;
    for ( var depth: u32 = 0u; depth < maxDepth; depth += 1u ) {
        var hitInfo: HitInfo;
        
        if ( !intersect( ray, &hitInfo ) ) { continue; } // intersect ray with scene

        var objEmissiveColor: vec3<f32>;
        var objDiffuseColor: vec3<f32>;
        var objMaterialType: u32;
        var objIsectNormal: vec3<f32>;
        let objIsectPoint = ray.o + hitInfo.rayT * ray.d;
 
        if ( hitInfo.objType == ePlane ) {
            let hitPlane: Plane = planes.data[ hitInfo.objIdx ];
            objEmissiveColor = hitPlane.e.rgb;
            objDiffuseColor  = hitPlane.c.rgb;
            objMaterialType  = u32( planes.data[ hitInfo.objIdx ].c.a + 0.5 );
            objIsectNormal = hitPlane.equation.xyz;
        } else if ( hitInfo.objType == eSphere ) {
            let hitSphere = spheres.data[ hitInfo.objIdx ];
            objMaterialType  = u32( hitSphere.c.a + 0.5 );
            objEmissiveColor = hitSphere.e.rgb;
            objDiffuseColor  = hitSphere.c.rgb;
            objIsectNormal = normalize( objIsectPoint - hitSphere.geo.xyz );
        }

        let nl = select( -objIsectNormal, objIsectNormal, dot(objIsectNormal,ray.d) < 0.0 );
        accrad += accmat * objEmissiveColor * emissive;      // add emssivie term only if emissive flag is set to 1
        accmat *= objDiffuseColor;
        let rnd = rand01(vec3<u32>(pix, samps.x*maxDepth + depth));    // vector of random numbers for sampling
        let p = max(max(objDiffuseColor.x, objDiffuseColor.y), objDiffuseColor.z);  // max reflectance
        if (depth > 5u) {
            if (rnd.z >= p) { break; }  // Russian Roulette ray termination
            else { accmat /= p; }       // Energy compensation of surviving rays
        }
        
        if ( objMaterialType == eDiffuseMaterial ) { //-- Ideal DIFFUSE reflection
            let M_PI: f32 = 3.141592653589793;
            // Direct Illumination: Next Event Estimation over any present lights
            for (var i: u32 = 0u; i < arrayLength( &spheres.data ); i++ ) {
                let ls = spheres.data[i];
                if ( ls.e.r == 0.0 && ls.e.g == 0.0 && ls.e.b == 0.0 ) { continue; }
                
                var xls: vec3<f32>;
                var nls: vec3<f32>; 
                let xc = ls.geo.xyz - objIsectPoint;
                let sw = normalize(xc);
                let su = normalize( cross( select( vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), abs(sw.x) > 0.1 ), sw ) );
                let sv = cross(sw, su);
                let cos_a_max = sqrt( 1.0 - ls.geo.w * ls.geo.w / dot( xc, xc ) );
                let cos_a = 1.0 - rnd.x + rnd.x * cos_a_max;
                let sin_a = sqrt( 1.0 - cos_a * cos_a );
                let phi = 2.0 * M_PI * rnd.y;
                let l = normalize(su*cos(phi)*sin_a + sv*sin(phi)*sin_a + sw*cos_a);   // sampled direction towards light
                let idls:i32 = 0; 
                var hitInfo_ne: HitInfo;
                if (intersect(Ray(objIsectPoint,l), &hitInfo_ne) && hitInfo_ne.objType == eSphere && hitInfo_ne.objIdx == i ) {      // test if shadow ray hits this light source
                    let omega = 2.0 * M_PI * (1.0 - cos_a_max);
                    accrad += accmat / M_PI * max(dot(l,nl),0) * ls.e.rgb * omega;   // brdf term obj.c.xyz already in accmat, 1/pi for brdf
                }
            }
            // Indirect Illumination: cosine-weighted importance sampling
            let r1 = 2.0 * M_PI * rnd.x;
            let r2 = rnd.y;
            let r2s = sqrt(r2);
            let w = nl;
            
            // vec3 w = nl, u = normalize( (cross(abs(w.x) > 0.1 ? vec3(0, 1, 0) : vec3(1, 0, 0), w)) );
            let u = normalize( cross( select( vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), abs(w.x) > 0.1), w ) ); 
            let v = cross(w, u);
            
            ray = Ray(objIsectPoint, normalize(u * cos(r1) * r2s + v * sin(r1) * r2s + w * sqrt(1.0 - r2)));
            emissive = 0.0;   // in the next bounce, consider reflective part only!
        } else if ( objMaterialType == eReflectiveMaterial ) { //-- Ideal SPECULAR reflection
            ray = Ray(objIsectPoint, reflect(ray.d, objIsectNormal));
            emissive = 1.0;
        } else if ( objMaterialType == eRefractiveMaterial ) { //-- Ideal dielectric REFRACTION
            let into = ( objIsectNormal.x == nl.x && objIsectNormal.y == nl.y && objIsectNormal.z == nl.z );
            let nc: f32 = 1.0;
            let nt: f32 = 1.5;
            let nnt = select( nt / nc, nc / nt, into );
            let ddn = dot(ray.d, nl);
            let cos2t = 1.0 - nnt * nnt * ( 1.0 - ddn * ddn );
            if ( cos2t >= 0.0 ) {     // Fresnel reflection/refraction
                let tdir = normalize( ray.d * nnt - objIsectNormal * 
                ( select( -1.0, 1.0, into ) * ( ddn * nnt + sqrt( cos2t ) ) ) );
                
                let a = nt - nc;
                let b = nt + nc;
                let R0 = a * a / (b * b);
                let c = 1.0 - select( dot( tdir, objIsectNormal ), -ddn, into );
                let Re = R0 + (1.0 - R0) * c * c * c * c * c;
                let Tr = 1.0 - Re;
                let P = 0.25 + 0.5 * Re;
                let RP = Re / P;
                let TP = Tr / (1.0 - P);
                
                ray = Ray(objIsectPoint, select( tdir, reflect( ray.d, objIsectNormal ), rnd.x < P ) );      // pick reflection with probability P
                accmat *= select( TP, RP, rnd.x < P );                     // energy compensation
            }
            else { ray = Ray(objIsectPoint, reflect(ray.d, objIsectNormal)); }                      // Total internal reflection
            emissive = 1.0;
        }
    }

    accRad.data[gid] += vec4<f32>(accrad / f32( samps.y ), 0.0);   // <<< accumulate radiance   vvv write 8bit rgb gamma encoded color
    if (samps.x == samps.y - 1) { // actually rather do this "outside"
        accRad.data[gid] = vec4<f32>( pow(vec3<f32>(clamp(accRad.data[gid].xyz, vec3<f32>(0.0f), vec3<f32>(1.0f))), vec3<f32>(0.45)) * 255.0 + 0.5, accRad.data[gid].w );
    }
}
