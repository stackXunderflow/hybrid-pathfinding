<script lang="ts">
    import { onMount } from "svelte";
    import type { BlobContent, Robot } from "@/types";
    import {
        meshColors,
        blobColor,
        robotColor,
        robotFill,
        theme,
    } from "@/lib/colors";

    let { blobs, robot }: { blobs: BlobContent[]; robot: Robot | null } =
        $props();

    let canvas: HTMLCanvasElement;
    let ctx: CanvasRenderingContext2D | null = $state(null);

    let scale = $state(1);
    let offsetX = $state(0);
    let offsetY = $state(0);

    let mouseX = $state(0);
    let mouseY = $state(0);
    let mouseInCanvas = $state(false);

    function getBounds() {
        let minX = Infinity,
            minY = Infinity,
            maxX = -Infinity,
            maxY = -Infinity;

        function expand(x: number, y: number) {
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
        }

        for (const b of blobs) {
            for (const m of b.meshs) {
                for (const p of m.points) expand(p.x, p.y);
            }
        }

        if (robot) {
            expand(robot.start.x, robot.start.y);
            expand(robot.end.x, robot.end.y);
        }

        const pad = 40;
        return {
            minX: minX - pad,
            minY: minY - pad,
            maxX: maxX + pad,
            maxY: maxY + pad,
        };
    }

    function updateTransform() {
        if (!canvas) return;
        const bounds = getBounds();
        if (!isFinite(bounds.minX)) return;
        const scaleX = canvas.width / (bounds.maxX - bounds.minX);
        const scaleY = canvas.height / (bounds.maxY - bounds.minY);
        scale = Math.min(scaleX, scaleY);
        offsetX =
            (canvas.width - (bounds.maxX - bounds.minX) * scale) / 2 -
            bounds.minX * scale;
        offsetY =
            (canvas.height - (bounds.maxY - bounds.minY) * scale) / 2 -
            bounds.minY * scale;
    }

    function tx(x: number) {
        return x * scale + offsetX;
    }
    function ty(y: number) {
        return y * scale + offsetY;
    }

    function draw() {
        if (!ctx || !canvas) return;

        updateTransform();
        const bounds = getBounds();
        if (!isFinite(bounds.minX)) return;

        ctx.clearRect(0, 0, canvas.width, canvas.height);

        ctx.fillStyle = theme.background;
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        let colorIndex = 0;
        for (const b of blobs) {
            for (const mesh of b.meshs) {
                if (mesh.points.length < 3) continue;

                const color = meshColors[colorIndex % meshColors.length];
                colorIndex++;

                ctx.beginPath();
                ctx.moveTo(tx(mesh.points[0].x), ty(mesh.points[0].y));
                for (let i = 1; i < mesh.points.length; i++) {
                    ctx.lineTo(tx(mesh.points[i].x), ty(mesh.points[i].y));
                }
                ctx.closePath();

                ctx.fillStyle = color + "30";
                ctx.fill();
                ctx.strokeStyle = color;
                ctx.lineWidth = 2;
                ctx.stroke();
            }

            if (b.blob.points.length >= 3) {
                ctx.beginPath();
                ctx.moveTo(tx(b.blob.points[0].x), ty(b.blob.points[0].y));
                for (let i = 1; i < b.blob.points.length; i++) {
                    ctx.lineTo(tx(b.blob.points[i].x), ty(b.blob.points[i].y));
                }
                ctx.closePath();

                ctx.fillStyle = blobColor + "30";
                ctx.fill();
                ctx.strokeStyle = blobColor;
                ctx.lineWidth = 3;
                ctx.stroke();
            }
        }

        if (robot) {
            const rx = tx(robot.start.x);
            const ry = ty(robot.start.y);
            const rr = robot.radius * scale;

            ctx.beginPath();
            ctx.arc(rx, ry, rr, 0, Math.PI * 2);
            ctx.fillStyle = robotFill;
            ctx.fill();
            ctx.strokeStyle = robotColor;
            ctx.lineWidth = 2;
            ctx.stroke();

            const ex = tx(robot.end.x);
            const ey = ty(robot.end.y);
            ctx.beginPath();
            ctx.arc(ex, ey, 4, 0, Math.PI * 2);
            ctx.fillStyle = robotColor;
            ctx.fill();
        }
    }

    function resize() {
        if (!canvas) return;
        const rect = canvas.getBoundingClientRect();
        canvas.width = rect.width * devicePixelRatio;
        canvas.height = rect.height * devicePixelRatio;
        ctx = canvas.getContext("2d")!;
        ctx.scale(devicePixelRatio, devicePixelRatio);
        draw();
    }

    function onMouseMove(e: MouseEvent) {
        mouseInCanvas = true;
        const rect = canvas.getBoundingClientRect();
        const screenX = e.clientX - rect.left;
        const screenY = e.clientY - rect.top;
        mouseX = (screenX * devicePixelRatio - offsetX) / scale;
        mouseY = (screenY * devicePixelRatio - offsetY) / scale;
    }

    function onMouseLeave() {
        mouseInCanvas = false;
    }

    $effect(() => {
        blobs;
        if (canvas) resize();
    });

    onMount(() => {
        resize();
        const observer = new ResizeObserver(resize);
        observer.observe(canvas);
        return () => observer.disconnect();
    });
</script>

<div class="container">
    <canvas
        bind:this={canvas}
        class="canvas"
        onmousemove={onMouseMove}
        onmouseleave={onMouseLeave}
    ></canvas>

    {#if mouseInCanvas}
        <div
            class="coords"
            style="background: {theme.background}; border: 1px solid {theme.border}; color: {theme.textSecondary};"
        >
            {mouseX.toFixed(1)}, {mouseY.toFixed(1)}
        </div>
    {/if}
</div>

<style>
    .container {
        position: relative;
        width: 100%;
        height: 100%;
    }

    .canvas {
        display: block;
        width: 100%;
        height: 100%;
    }

    .coords {
        position: absolute;
        bottom: 8px;
        right: 8px;
        padding: 4px 8px;
        font-size: 0.75rem;
        font-family: monospace;
        border-radius: 4px;
        pointer-events: none;
    }
</style>
