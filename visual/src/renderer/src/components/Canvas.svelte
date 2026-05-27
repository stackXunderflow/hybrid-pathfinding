<script lang="ts">
	import { onMount } from 'svelte';
	import type { BlobContent } from '@/types';
	import { meshColors, blobColor, theme } from '@/lib/colors';

	let { blobs }: { blobs: BlobContent[] } = $props();

	let canvas: HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = $state(null);

	function getBounds() {
		let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
		for (const b of blobs) {
			for (const m of b.meshs) {
				for (const p of m.points) {
					if (p.x < minX) minX = p.x;
					if (p.y < minY) minY = p.y;
					if (p.x > maxX) maxX = p.x;
					if (p.y > maxY) maxY = p.y;
				}
			}
		}
		const pad = 40;
		return { minX: minX - pad, minY: minY - pad, maxX: maxX + pad, maxY: maxY + pad };
	}

	function draw() {
		if (!ctx || !canvas) return;

		const bounds = getBounds();
		if (!isFinite(bounds.minX)) return;

		const scaleX = canvas.width / (bounds.maxX - bounds.minX);
		const scaleY = canvas.height / (bounds.maxY - bounds.minY);
		const scale = Math.min(scaleX, scaleY);

		const offsetX = (canvas.width - (bounds.maxX - bounds.minX) * scale) / 2 - bounds.minX * scale;
		const offsetY = (canvas.height - (bounds.maxY - bounds.minY) * scale) / 2 - bounds.minY * scale;

		function tx(x: number) { return x * scale + offsetX; }
		function ty(y: number) { return y * scale + offsetY; }

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

				ctx.fillStyle = color + '30';
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

				ctx.fillStyle = blobColor + '30';
				ctx.fill();
				ctx.strokeStyle = blobColor;
				ctx.lineWidth = 3;
				ctx.stroke();
			}
		}
	}

	function resize() {
		if (!canvas) return;
		const rect = canvas.getBoundingClientRect();
		canvas.width = rect.width * devicePixelRatio;
		canvas.height = rect.height * devicePixelRatio;
		ctx = canvas.getContext('2d')!;
		ctx.scale(devicePixelRatio, devicePixelRatio);
		draw();
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

<canvas
	bind:this={canvas}
	class="canvas"
></canvas>

<style>
	.canvas {
		display: block;
		width: 100%;
		height: 100%;
	}
</style>
