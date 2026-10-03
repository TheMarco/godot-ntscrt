#[compute]
#version 450
// Port of NTSCRT Sources/CrtCore/GlitchStage.swift. Original authors retain copyright.
// Original source snapshot and provenance: tools/ntscrt/receiver_schema.json.
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;




    struct GlitchU {
        uint width, activeLines, vbiLines, totalLines;
        uint preEqEnd, vsyncEnd, postEqEnd, ccEnabled;
        uint ccBits, fieldIndex, seed, dropoutCount;
        uint docEnabled, tapsI, tapsQ, colorOnInit;
        float usPerPixel, lineUS, ghostLevel, ghostDelay;
        float ghostCos, ghostSin, brightness, pictureGain;
        float burstAmp, chromaAlpha, accGamma, killerKappa;
        float phaseInit, gainInit, killerInit, gateNoise;
    };
    struct Row {
        float u0; int fieldLine; float lenPrev; float lenCur; float lenNext;
        float noiseIRE; float humIRE; float burstScale;
        float tapeLoss; float gateShift; float pad1; float pad2;
    };
    struct Dropout { int fieldLine; float uStart; float uLength; float pad; };


layout(set=0,binding=0,std430) buffer Rows { Row rows[]; };
layout(set=0,binding=1,std430) buffer Uniforms { GlitchU U; };
layout(set=0,binding=2,std430) buffer Gates { vec2 gate[]; };
layout(set=0,binding=3,std430) buffer Colors { vec4 color[]; };
layout(set=0,binding=4,std430) buffer Drops { Dropout drops[]; };
layout(set=0,binding=5) uniform sampler2D src;
layout(set=0,binding=6,rgba8) uniform writeonly image2D dst;
    const float SYNC_END = 4.7;
    const float BURST_S = 5.3;
    const float BURST_E = 7.8;
    const float GATE_S = 4.55;           // 4 µs gate around the burst
    const float GATE_E = 8.55;
    const float ACT_S = 9.4;
    const float ACT_L = 52.656;
    const float EQ_PULSE = 2.3;
    const float BROAD = 27.1;
    const vec2 BURST_DIR = vec2(0.5446390350, -0.8386705679);

    // ---- colour space (NTSC Y'IQ on the gamma-encoded picture) ----
    vec3 rgb2yiq(vec3 c) {
        return vec3(0.299 * c.r + 0.587 * c.g + 0.114 * c.b,
                      0.596 * c.r - 0.274 * c.g - 0.322 * c.b,
                      0.211 * c.r - 0.523 * c.g + 0.312 * c.b);
    }
    vec3 yiq2rgb(vec3 y) {
        return vec3(y.x + 0.9561706854 * y.y + 0.6214325663 * y.z,
                      y.x - 0.2726886023 * y.y - 0.6468132370 * y.z,
                      y.x - 1.1037440822 * y.y + 1.7006230947 * y.z);
    }
    float ire2y(float ire) { return (ire - 7.5) / 92.5; }

    // ---- deterministic noise ----
    uint hash4(uint a, uint b, uint c, uint d) {
        uint h = a * 0x8DA6B343u ^ b * 0xD8163841u ^ c * 0xCB1AB31Fu ^ d * 0x165667B1u;
        h ^= h >> 15; h *= 0x2C1B3C6Du; h ^= h >> 12; h *= 0x297A2D39u; h ^= h >> 15;
        return h;
    }
    float uni(uint a, uint b, uint c, uint d) {
        return (float(hash4(a, b, c, d) >> 8) + 0.5) * (1.0 / 16777216.0);
    }
    float gauss(uint a, uint b, uint c, uint d) {
        float u1 = uni(a, b, c, d);
        float u2 = uni(a ^ 0x5bd1e995u, b, c, d + 7u);
        return sqrt(-2.0 * log(u1)) * cos(6.2831853 * u2);
    }

    // ---- where in the signal a moment of a TV line falls ----
    struct Loc { int line; float u; };
    Loc locate(Row rw, float u, uint L) {
        int line = rw.fieldLine;
        if (u < 0.0) { u += rw.lenPrev; line -= 1; }
        else if (u >= rw.lenCur) {
            u -= rw.lenCur; line += 1;
            if (u >= rw.lenNext) { u -= rw.lenNext; line += 1; }
        }
        int iL = int(L);
        line = ((line % iL) + iL) % iL;
        return Loc(line, u);
    }

    // Is (line, u) inside a dropout? Reports where that dropout starts.
    bool inDropout(uint count, int line, float u, out float start) {
        for (uint i = 0; i < count; i++) {
            Dropout d = drops[i];
            if (d.fieldLine == line && u >= d.uStart && u < d.uStart + d.uLength) {
                start = d.uStart;
                return true;
            }
        }
        return false;
    }

    // Line 21: 7 cycles of clock run-in at 503.5 kHz, then 19 bits.
    float captionIRE(float u, uint bits) {
        float t = u - 10.5;
        const float period = 1.986;
        if (t < 0.0) return 0.0;
        if (t < 7.0 * period) return 25.0 - 25.0 * cos(6.2831853 * t / period);
        float b = (t - 7.0 * period) / period;
        int k = int(floor(b));
        if (k < 0 || k >= 19) return 0.0;
        float on = float((bits >> uint(k)) & 1u);
        float prev = k > 0 ? float((bits >> uint(k - 1)) & 1u) : 0.0;
        float edge = smoothstep(0.0, 0.25, b - float(k));
        return 50.0 * mix(prev, on, edge);
    }

    // What the signal carries at (line, u): returns Y'IQ on the decoder's
    // scale, and the raw texel + exactness flag when it is a picture pixel.
    struct Sig { vec3 yiq; vec3 rgb; bool picture; bool exact; };
    Sig signalAt(int line, float u) {
        Sig s; s.picture = false; s.exact = false; s.rgb = vec3(0.0);
        int vbi = int(U.vbiLines);
        float halfLine = U.lineUS * 0.5;
        float ire = 0.0;                                   // blanking
        if (line < vbi) {
            if (line < int(U.preEqEnd) || (line >= int(U.vsyncEnd) && line < int(U.postEqEnd))) {
                if (u < EQ_PULSE || (u >= halfLine && u < halfLine + EQ_PULSE)) ire = -40.0;
            } else if (line < int(U.vsyncEnd)) {
                if (u < BROAD || (u >= halfLine && u < halfLine + BROAD)) ire = -40.0;
            } else {
                if (u < SYNC_END) ire = -40.0;
                else if (line == vbi - 1 && U.ccEnabled != 0u && u >= ACT_S && u < ACT_S + ACT_L)
                    ire = captionIRE(u, U.ccBits);
            }
            s.yiq = vec3(ire2y(ire), 0.0, 0.0);
            return s;
        }
        if (u < SYNC_END) { s.yiq = vec3(ire2y(-40.0), 0.0, 0.0); return s; }
        if (u < ACT_S || u >= ACT_S + ACT_L) { s.yiq = vec3(ire2y(0.0), 0.0, 0.0); return s; }
        int row = line - vbi;
        float xs = (u - ACT_S) / U.usPerPixel - 0.5;
        float x0 = floor(xs);
        float f = xs - x0;
        int w = int(U.width);
        int ix = int(x0);
        if (f < 1e-3 || f > 1.0 - 1e-3) {
            int xi = clamp(f < 0.5 ? ix : ix + 1, 0, w - 1);
            s.rgb = texelFetch(src, ivec2(uvec2(uint(xi), uint(row))), 0).rgb;
            s.exact = true;
        } else {
            vec3 a = texelFetch(src, ivec2(uvec2(uint(clamp(ix, 0, w - 1)), uint(row))), 0).rgb;
            vec3 b = texelFetch(src, ivec2(uvec2(uint(clamp(ix + 1, 0, w - 1)), uint(row))), 0).rgb;
            s.rgb = mix(a, b, f);
        }
        s.picture = true;
        s.yiq = rgb2yiq(s.rgb);
        return s;
    }

    void main()
    {
        uvec2 gid = gl_GlobalInvocationID.xy; uint y = gid.x; uint tid = gid.x;
        if (gid.x >= U.width || gid.y >= U.activeLines) return;
        Row rw = rows[gid.y];
        vec4 rc = color[gid.y];
        float u = rw.u0 + ACT_S + (float(gid.x) + 0.5) * U.usPerPixel;
        Loc l = locate(rw, u, U.totalLines);

        // Oxide dropout. Without compensation the FM demodulator throws a
        // white streak with a dark tail. With it, the deck replays the
        // stretch from its one-line delay — which, when the line above was
        // a dropout too, is that line's own replacement, so a tall flaw
        // repeats one line down several (a frozen smear). The detector and
        // switch react ~0.7 µs late, so each dropout still flashes a tick.
        int sigLine = l.line;
        bool streak = false;
        float tail = 0.0;
        float dStart = 0.0;
        if (inDropout(U.dropoutCount, l.line, l.u, dStart)) {
            if (U.docEnabled != 0u && l.u - dStart >= 0.7) {
                int src = l.line - 1;
                float s2 = 0.0;
                for (int k = 0; k < 6 && src > int(U.vbiLines)
                     && inDropout(U.dropoutCount, src, l.u, s2); k++) src -= 1;
                sigLine = max(int(U.vbiLines), src);
            } else {
                streak = true;
            }
        } else if (U.docEnabled == 0u) {
            for (uint i = 0; i < U.dropoutCount; i++) {
                Dropout d = drops[i];
                if (d.fieldLine == l.line && l.u >= d.uStart + d.uLength
                    && l.u < d.uStart + d.uLength + 1.5) {
                    tail = max(tail, 1.0 - (l.u - d.uStart - d.uLength) / 1.5);
                }
            }
        }

        Sig s = signalAt(sigLine, l.u);
        bool plain = s.picture && s.exact && sigLine == l.line && !streak && tail == 0.0
            && U.ghostLevel == 0.0 && rw.noiseIRE == 0.0 && rw.humIRE == 0.0 && rw.tapeLoss == 0.0
            && U.pictureGain == 1.0 && U.brightness == 0.0
            && rc.x == 1.0 && rc.y == 0.0 && rc.z == 1.0;
        if (plain) { imageStore(dst, ivec2(gid), vec4(s.rgb, 1.0)); return; }

        vec3 yiq = s.yiq;
        if (streak) yiq = vec3(1.0, 0.0, 0.0);
        if (tail > 0.0) yiq.x = mix(yiq.x, -0.08, tail * 0.6);

        // Multipath: the same signal again, later, possibly inverted.
        if (U.ghostLevel != 0.0) {
            float ug = l.u - U.ghostDelay;
            int gl = l.line;
            if (ug < 0.0) { ug += U.lineUS; gl = (gl - 1 + int(U.totalLines)) % int(U.totalLines); }
            Sig g = signalAt(gl, ug);
            vec2 iq = vec2(g.yiq.y * U.ghostCos - g.yiq.z * U.ghostSin,
                               g.yiq.y * U.ghostSin + g.yiq.z * U.ghostCos);
            // The ghost adds the signal's variation about blanking.
            yiq.x += U.ghostLevel * (g.yiq.x - ire2y(0.0));
            yiq.yz += U.ghostLevel * iq;
        }

        // Tape signal loss: past the FM threshold the deck's demodulator
        // outputs streaks instead of picture — black and white dashes a
        // fraction of a microsecond to a couple long — and its colour
        // killer drops chroma with the signal.
        if (rw.tapeLoss > 0.0) {
            float seg = 0.5 + 1.6 * uni(U.seed, U.fieldIndex, gid.y, 201u);
            float pos = l.u + uni(U.seed, U.fieldIndex, gid.y, 202u) * seg;
            uint run = uint(max(0.0, pos) / seg);
            float g = gauss(U.seed ^ 0xF00Du, U.fieldIndex, run, gid.y);
            float sparkle = uni(U.seed ^ 0xBEEFu, U.fieldIndex, run, gid.y) > 0.93 ? 0.6 : 0.0;
            float streak = clamp(0.35 + 0.32 * g + sparkle, -0.08, 1.05);
            yiq.x = mix(yiq.x, streak, rw.tapeLoss);
            yiq.yz *= 1.0 - rw.tapeLoss;
        }

        // AGC running out of gain: everything shrinks toward blanking.
        if (U.pictureGain != 1.0) {
            float ire = 7.5 + 92.5 * yiq.x;
            yiq.x = ire2y(ire * U.pictureGain);
            yiq.yz *= U.pictureGain;
        }

        yiq.x += rw.humIRE / 92.5;

        // Snow with the decoder's spectrum: luma near-white, chroma
        // low-passed to the I and Q bandwidths.
        if (rw.noiseIRE > 0.0) {
            float n = rw.noiseIRE / 92.5;
            yiq.x += gauss(U.seed, U.fieldIndex, gid.x, gid.y * 3u) * n;
            float ni = 0.0, nq = 0.0;
            for (uint k = 0; k < U.tapsI; k++)
                ni += gauss(U.seed ^ 0x1234u, U.fieldIndex, gid.x + k, gid.y * 3u + 1u);
            for (uint k = 0; k < U.tapsQ; k++)
                nq += gauss(U.seed ^ 0x4321u, U.fieldIndex, gid.x + k, gid.y * 3u + 2u);
            // Chroma noise carries the I and Q channels' share of the
            // noise power (1.3 and 0.6 MHz of the 4.2 MHz video band).
            yiq.y += ni / sqrt(float(U.tapsI)) * n * 0.35;
            yiq.z += nq / sqrt(float(U.tapsQ)) * n * 0.25;
        }

        // Decode chroma against the row's reference: a phase error rotates
        // it, ACC scales it, the killer removes it.
        vec2 iq = vec2(yiq.y * rc.x - yiq.z * rc.y, yiq.y * rc.y + yiq.z * rc.x) * rc.z;
        yiq.y = iq.x; yiq.z = iq.y;

        // Brightness lowers the tube's cutoff: blanking (0 IRE) and sync
        // (−40) become visible as the black level drops below them.
        if (U.brightness > 0.0) {
            float cutoff = 7.5 - 47.5 * U.brightness;
            float ire = 7.5 + 92.5 * yiq.x;
            yiq.x = (ire - cutoff) / (100.0 - cutoff);
            yiq.yz *= 92.5 / (100.0 - cutoff);
        }

        vec3 rgb = clamp(yiq2rgb(yiq), 0.0, 1.0);
        imageStore(dst, ivec2(gid), vec4(rgb, 1.0));
    }
