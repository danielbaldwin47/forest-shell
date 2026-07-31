// A stand-in desktop to judge the fog scrim against.
//
// Deliberately *not* one of the Pinterest pins: those are copyrighted reference
// material, gitignored, and can't be committed as screenshots to a public repo.
// These are drawn procedurally from the board's own composition rules (vertical
// luminance gradient, receding ridgelines, haze between layers) with a seeded
// PRNG, so every run renders identically and two screenshots differ only by the
// knob under test.
//
// Three flavours, chosen to bracket the scrim's real difficulty:
//   ridge  — high-key misty ridgeline. The bright case a pale wash struggles on.
//   forest — dark green forest floor. The easy case.
//   busy   — high-frequency foliage plus a blown-out sky patch. Worst case for
//            legibility of hairlines and muted text.
import QtQuick

Item {
    id: root

    /// "ridge" | "forest" | "busy"
    property string flavour: "ridge"

    onFlavourChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Immediate

        // Deterministic: same picture every launch.
        property int seed: 1337
        function rand() {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            return seed / 0x7fffffff;
        }

        function ridgeline(ctx, w, h, baseY, amp, roughness, color) {
            ctx.beginPath();
            ctx.moveTo(0, h);
            ctx.lineTo(0, baseY);
            var x = 0;
            var y = baseY;
            while (x < w) {
                var step = 14 + rand() * 26;
                var dy = (rand() - 0.5) * amp * roughness;
                y = Math.max(baseY - amp, Math.min(baseY + amp * 0.4, y + dy));
                x += step;
                ctx.lineTo(x, y);
            }
            ctx.lineTo(w, h);
            ctx.closePath();
            ctx.fillStyle = color;
            ctx.fill();
        }

        function conifers(ctx, w, h, baseY, count, height, color) {
            ctx.fillStyle = color;
            for (var i = 0; i < count; i++) {
                var x = rand() * w;
                var hh = height * (0.6 + rand() * 0.7);
                var hw = hh * 0.22;
                ctx.beginPath();
                ctx.moveTo(x, baseY - hh);
                ctx.lineTo(x + hw, baseY + 4);
                ctx.lineTo(x - hw, baseY + 4);
                ctx.closePath();
                ctx.fill();
            }
        }

        onPaint: {
            var ctx = getContext("2d");
            var w = width, h = height;
            seed = 1337;
            ctx.reset();

            if (root.flavour === "forest") {
                var g = ctx.createLinearGradient(0, 0, 0, h);
                g.addColorStop(0.0, "#2f4a3c");
                g.addColorStop(0.45, "#1b2c24");
                g.addColorStop(1.0, "#080d0a");
                ctx.fillStyle = g;
                ctx.fillRect(0, 0, w, h);
                ridgeline(ctx, w, h, h * 0.42, h * 0.10, 0.5, "#22362c");
                ridgeline(ctx, w, h, h * 0.58, h * 0.12, 0.6, "#182a21");
                conifers(ctx, w, h, h * 0.78, 90, h * 0.30, "#0d1712");
                conifers(ctx, w, h, h * 1.02, 60, h * 0.42, "#070d0a");
                return;
            }

            if (root.flavour === "busy") {
                var gb = ctx.createLinearGradient(0, 0, 0, h);
                gb.addColorStop(0.0, "#eef4f2");
                gb.addColorStop(0.30, "#b9d3cd");
                gb.addColorStop(0.65, "#5c7f6b");
                gb.addColorStop(1.0, "#20301f");
                ctx.fillStyle = gb;
                ctx.fillRect(0, 0, w, h);
                // blown-out sun patch, upper right — where pale-on-pale hurts most
                var sun = ctx.createRadialGradient(w * 0.74, h * 0.16, 0, w * 0.74, h * 0.16, h * 0.45);
                sun.addColorStop(0.0, "#ffffff");
                sun.addColorStop(0.5, "rgba(255,255,255,0.45)");
                sun.addColorStop(1.0, "rgba(255,255,255,0.0)");
                ctx.fillStyle = sun;
                ctx.fillRect(0, 0, w, h);
                // dense high-frequency foliage across the whole frame
                for (var i = 0; i < 2600; i++) {
                    var x = rand() * w;
                    var y = h * 0.25 + rand() * h * 0.75;
                    var l = 6 + rand() * 26;
                    var a = 0.18 + rand() * 0.5;
                    ctx.strokeStyle = (rand() > 0.5 ? "rgba(24,48,30," : "rgba(150,190,140,") + a.toFixed(2) + ")";
                    ctx.lineWidth = 1 + rand() * 2;
                    ctx.beginPath();
                    ctx.moveTo(x, y);
                    ctx.lineTo(x + (rand() - 0.5) * 14, y - l);
                    ctx.stroke();
                }
                conifers(ctx, w, h, h * 1.05, 40, h * 0.5, "rgba(14,26,16,0.9)");
                return;
            }

            // "ridge" — high-key misty ridgeline, the hard case for a pale wash
            var gr = ctx.createLinearGradient(0, 0, 0, h);
            gr.addColorStop(0.0, "#dbe7ea");
            gr.addColorStop(0.35, "#c2d6d8");
            gr.addColorStop(0.72, "#93aeaa");
            gr.addColorStop(1.0, "#4b6a5f");
            ctx.fillStyle = gr;
            ctx.fillRect(0, 0, w, h);
            // strata receding into haze: each layer lighter and lower-contrast
            var layers = [
                { y: 0.46, amp: 0.055, c: "#a9c2c1" },
                { y: 0.57, amp: 0.070, c: "#8fada9" },
                { y: 0.68, amp: 0.085, c: "#71938c" },
                { y: 0.80, amp: 0.100, c: "#517569" },
                { y: 0.94, amp: 0.110, c: "#2f4b3f" }
            ];
            for (var li = 0; li < layers.length; li++)
                ridgeline(ctx, w, h, h * layers[li].y, h * layers[li].amp, 0.55, layers[li].c);
            conifers(ctx, w, h, h * 1.02, 70, h * 0.26, "#1c3128");
        }
    }
}
