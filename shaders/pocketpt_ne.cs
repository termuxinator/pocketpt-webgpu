#version 460

layout(local_size_x = 16, local_size_y = 16) in;

struct Ray { vec3 o; vec3 d; };
struct Sphere { vec4 geo; vec4 e; vec4 c; };
struct Plane { vec4 equation; vec4 e; vec4 c; };

layout(std430, binding = 0) readonly buffer b0 { Sphere spheres []; };
// Plane planes[] *should* work here, but is strangely aliased with struct Sphere due to same mem layout, 
// but then leading to type errors => circumvent by using vec4[3] instead of Plane
layout(std430, binding = 1) readonly buffer b1 { vec4[3] planes []; }; 
layout(std430, binding = 2) buffer b2 { vec4 accRad []; };
layout(std140, set = 0, binding = 3) uniform u_global {
    uvec4 imgdim_samplecount;
};

// # object types; switch to enums?
#define ePlane      0
#define eSphere     1
#define eMesh       2

// # material types
#define eDiffuseMaterial        1
#define eReflectiveMaterial     2
#define eRefractiveMaterial     3

struct HitInfo { 
    float   rayT;
    int     objType; 
    int     objIdx; 
};

vec3 rand01(uvec3 x) {   // pseudo-random number generator
    for (int i = 3; i-- > 0;) x = ((x >> 8U) ^ x.yzx) * 1103515245U;
    return vec3(x) * (1.0 / float(0xffffffffU));
}

bool intersect(Ray ray, out HitInfo hitInfo) {
    float d, inf = 1e20, t = inf, eps = 1e-4;   // intersect ray with scene
    
    for (int i = 0; i < planes.length(); i++ ) {
        vec4 planeEqu = planes[i][0];
        float denom = dot( ray.d, planeEqu.xyz );
        if ( denom > eps ) {
            d = ( planeEqu.w - dot( ray.o, planeEqu.xyz ) ) / denom ;
            if ( d < t ) {
                t = d; hitInfo.objType = ePlane; hitInfo.objIdx = i;
            }
        }
    }

#if 0 // two different versions for sphere intersectionss
    for (int i = 0; i < spheres.length(); i++ ) {
        Sphere sphere = spheres[i];    
        // Compute a, b, c, for quadratic in ray-sphere intersection
        //    (Math can be simplified; left in its entirety for clarity.)
        
        vec3 toCtr = ray.o - sphere.geo.xyz;
        float a = dot(ray.d, ray.d);
        float b = 2.0f*dot(ray.d, toCtr);
        float c = dot(toCtr, toCtr) - sphere.geo.w * sphere.geo.w;

        // Checks if sqrt(b^2 - 4*a*c) in quadratic equation has real answer
        float discriminant = b * b - 4.0f*a*c;
        if (discriminant < 0.0) {continue;}

        float sqrtVal = sqrt(discriminant);

        float q = (b >= 0) ? (-0.5*(b + sqrtVal)) : (-0.5*(b - sqrtVal));

        // we don't bother testing for division by zero
        float d1 = q / a;
        float d2 = c / q;
        d = (min(d1,d2) > eps) ? min(d1,d2) : ((max(d1,d2) > eps) ? max(d1,d2) : inf);            

        if (d < t) { 
            t=d; hitInfo.objType = eSphere; hitInfo.objIdx = i;
        }
    }
#else
    for ( int i = 0; i < spheres.length(); i++ ) {
        Sphere sphere = spheres[i];                  
        
        // we would like to perform intersection tests in double precision, but unfortunately double precision is not available in WebGPU
        // dvec3 oc = dvec3(s.geo.xyz) - r.o;      // Solve t^2*d.d + 2*t*(o-s).d + (o-s).(o-s)-r^2 = 0 
        // double b = dot(oc, r.d), det = b * b - dot(oc, oc) + s.geo.w * s.geo.w; // WebGPU: not supported
        // d = (d = float(b - det)) > eps ? d : ((d = float(b + det)) > eps ? d : inf);

        vec3 oc = sphere.geo.xyz - ray.o;      // Solve t^2*d.d + 2*t*(o-s).d + (o-s).(o-s)-r^2 = 0 
        float b = dot(oc, ray.d), det = b * b - dot(oc, oc) + sphere.geo.w * sphere.geo.w; // WebGPU: not supported

        if (det < 0) { continue; } else { det = sqrt(det); }
        d = (d = (b - det)) > eps ? d : ((d = (b + det)) > eps ? d : inf);
        
        if (d < t) { 
            t=d; hitInfo.objType = eSphere; hitInfo.objIdx = i;
        }
    }
#endif

    if (t < inf) {
        hitInfo.rayT = t;
        return true;
    }
    return false;
}

void main() {
    uvec2 imgdim = /*u_global.*/imgdim_samplecount.xy;
    uvec2 samps = /*u_global.*/imgdim_samplecount.zw;

    uvec2 pix = gl_GlobalInvocationID.xy;
    if (pix.x >= imgdim.x || pix.y >= imgdim.y) return;
    uint gid = pix.y * imgdim.x + (imgdim.x - 1 - pix.x);

    //-- define camera
    Ray cam = Ray(vec3(0, 0.52, 7.4), normalize(vec3(0, -0.06, -1)));
    vec3 cx = normalize(cross(cam.d, abs(cam.d.y) < 0.9 ? vec3(0, 1, 0) : vec3(0, 0, 1))), cy = cross(cx, cam.d);
    //const vec2 sdim = vec2(0.036, 0.024);    // sensor size (36 x 24 mm)
    const vec2 sdim = vec2(0.03); // TODO: this must match the ratio of the canvas

    //-- sample sensor
    vec2 rnd2 = 2 * rand01(uvec3(pix, samps.x)).xy;   // vvv tent filter sample  
    vec2 tent = vec2(rnd2.x < 1 ? sqrt(rnd2.x) - 1 : 1 - sqrt(2 - rnd2.x), rnd2.y < 1 ? sqrt(rnd2.y) - 1 : 1 - sqrt(2 - rnd2.y));
    vec2 s = ((pix + 0.5 * (0.5 + vec2((samps.x / 2) % 2, samps.x % 2) + tent)) / vec2(imgdim) - 0.5) * sdim;
    vec3 spos = cam.o + cx * s.x + cy * s.y, lc = cam.o + cam.d * 0.035;           // sample on 3d sensor plane
    vec3 accrad = vec3(0), accmat = vec3(1);      // initialize accumulated radiance and bxdf
    Ray ray = Ray(lc, normalize(lc - spos));      // construct ray
    

    //-- loop over ray bounces
    float emissive = 1;
    for (int depth = 0, maxDepth = 12; depth < maxDepth; depth++)
    {
        HitInfo hitInfo;
        
        if ( !intersect( ray, hitInfo ) ) { continue; } // intersect ray with scene

        vec3 objEmissiveColor, objDiffuseColor;
        int objMaterialType;
        vec3 objIsectNormal;
        vec3 objIsectPoint = ray.o + hitInfo.rayT * ray.d;


        if ( hitInfo.objType == ePlane ) {
            // Plane_t hitPlane = planes[ hitInfo.objIdx ];
            Plane hitPlane;
            hitPlane.equation = planes[ hitInfo.objIdx ][0];
            objEmissiveColor = planes[ hitInfo.objIdx ][1].rgb;
            objDiffuseColor  = planes[ hitInfo.objIdx ][2].rgb;
            objMaterialType  = int( floor( planes[ hitInfo.objIdx ][2].w + 0.5f ) );
            vec4 hitPlaneEqu = hitPlane.equation;
            objIsectNormal = hitPlaneEqu.xyz;
        } else if ( hitInfo.objType == eSphere ) {
            Sphere hitSphere = spheres[ hitInfo.objIdx ];
            objMaterialType  = int( floor( hitSphere.c.w + 0.5f ) );
            objEmissiveColor = hitSphere.e.rgb;
            objDiffuseColor  = hitSphere.c.rgb;
            objIsectNormal = normalize( objIsectPoint - hitSphere.geo.xyz );
        }

        vec3 nl = dot(objIsectNormal,ray.d) < 0 ? objIsectNormal : -objIsectNormal;
        accrad += accmat * objEmissiveColor * emissive;      // add emssivie term only if emissive flag is set to 1
        accmat *= objDiffuseColor;
        vec3 rnd = rand01(uvec3(pix, samps.x*maxDepth + depth));    // vector of random numbers for sampling
        float p = max(max(objDiffuseColor.x, objDiffuseColor.y), objDiffuseColor.z);  // max reflectance
        if (depth > 5) {
            if (rnd.z >= p) { break; }  // Russian Roulette ray termination
            else { accmat /= p; }       // Energy compensation of surviving rays
        }
        //-- Ideal DIFFUSE reflection
        if ( objMaterialType == eDiffuseMaterial ) { 
            const float pi = 3.141592653589793;
            // Direct Illumination: Next Event Estimation over any present lights
            for (int i = 0; i < spheres.length(); i++) {
                Sphere ls = spheres[i];

                if (all(equal(ls.e.rgb, vec3(0)))) { continue; } // skip non-emissive spheres 
                vec3 xls, nls, xc = ls.geo.xyz - objIsectPoint;
                vec3 sw = normalize(xc), su = normalize(cross((abs(sw.x) > .1 ? vec3(0, 1, 0) : vec3(1, 0, 0)), sw)), sv = cross(sw, su);
                float cos_a_max = sqrt(1.0 - ls.geo.w * ls.geo.w / dot(xc, xc));
                float cos_a = 1 - rnd.x + rnd.x * cos_a_max, sin_a = sqrt(1 - cos_a * cos_a);
                float phi = 2 * pi * rnd.y;
                vec3 l = normalize(su*cos(phi)*sin_a + sv*sin(phi)*sin_a + sw*cos_a);   // sampled direction towards light
                int idls = 0; 
                HitInfo hitInfo_ne;
                if (intersect(Ray(objIsectPoint,l), hitInfo_ne) && hitInfo_ne.objType == eSphere && hitInfo_ne.objIdx == i ) { // test if shadow ray hits this light source
                    float omega = 2 * pi * (1-cos_a_max);
                    accrad += accmat / pi * max(dot(l,nl),0) * ls.e.rgb * omega;   // brdf term obj.c.xyz already in accmat, 1/pi for brdf
                }
            }
            // Indirect Illumination: cosine-weighted importance sampling
            float r1 = 2 * pi * rnd.x, r2 = rnd.y, r2s = sqrt(r2);
            vec3 w = nl, u = normalize( (cross(abs(w.x) > 0.1 ? vec3(0, 1, 0) : vec3(1, 0, 0), w)) ), v = cross(w, u);
            ray = Ray(objIsectPoint, normalize(u * cos(r1) * r2s + v * sin(r1) * r2s + w * sqrt(1 - r2)));
            emissive = 0;   // in the next bounce, consider reflective part only!
        }
        //-- Ideal SPECULAR reflection
        else if ( objMaterialType == eReflectiveMaterial ) {   
            ray = Ray(objIsectPoint, reflect(ray.d, objIsectNormal));
            emissive = 1;
        }
        //-- Ideal dielectric REFRACTION
        else if ( objMaterialType == eRefractiveMaterial ) {  
            bool into = ( objIsectNormal == nl );
            float cos2t, nc = 1, nt = 1.5, nnt = into ? nc / nt : nt / nc, ddn = dot(ray.d, nl);
            if ((cos2t = 1 - nnt * nnt * (1 - ddn * ddn)) >= 0)
            {     // Fresnel reflection/refraction
                vec3 tdir = normalize(ray.d * nnt - objIsectNormal * ((into ? 1 : -1) * (ddn * nnt + sqrt(cos2t))));
                float a = nt - nc, b = nt + nc, R0 = a * a / (b * b), c = 1 - (into ? -ddn : dot(tdir, objIsectNormal));
                float Re = R0 + (1 - R0) * c * c * c * c * c, Tr = 1 - Re, P = 0.25 + 0.5 * Re, RP = Re / P, TP = Tr / (1 - P);
                ray = Ray(objIsectPoint, rnd.x < P ? reflect(ray.d, objIsectNormal) : tdir);      // pick reflection with probability P
                accmat *= rnd.x < P ? RP : TP;                     // energy compensation
            }
            else ray = Ray(objIsectPoint, reflect(ray.d, objIsectNormal));                      // Total internal reflection
            emissive = 1;
        }
    }

    accRad[gid] += vec4(accrad / samps.y, 0.0);   // <<< accumulate radiance   vvv write 8bit rgb gamma encoded color
    if (samps.x == samps.y - 1.0) { // actually rather do this "outside" (?)
        accRad[gid] = vec4( pow(vec3(clamp(accRad[gid].xyz, 0.0, 1.0)), vec3(0.45)) * 255.0 + 0.5, accRad[gid].w );
    }
}