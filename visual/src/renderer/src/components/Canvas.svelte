<script lang="ts">
	import { onMount } from 'svelte';
	import type { DebugItem, SceneInput, SceneOutput, Point } from '@/types';
	import { blobColor, meshColors, robotColor, robotFill, theme } from '@/lib/colors';
	import {
		clonePoint,
		distance,
		distanceToSegment,
		ensureCcw,
		insertPointOnClosestEdge,
		pointInPolygon,
		translateMesh,
	} from '@/lib/geometry';
	import { updateScene } from '@/lib/scene.svelte';

	type Tool = 'select' | 'pan' | 'add-mesh' | 'add-vertex' | 'delete';
	type Selection =
		| { type: 'mesh'; meshIndex: number }
		| { type: 'vertex'; meshIndex: number; pointIndex: number }
		| { type: 'robot'; handle: 'start' | 'end' }
		| { type: 'border'; handle: BorderHandle }
		| null;
	type BorderHandle = 'top-left' | 'top' | 'top-right' | 'right' | 'bottom-right' | 'bottom' | 'bottom-left' | 'left';
	type Layers = {
		obstacles: boolean;
		robot: boolean;
		blobs: boolean;
		debug: boolean;
		vertices: boolean;
		fills: boolean;
		labels: boolean;
		debugLayouts: Record<string, boolean>;
	};

	let {
		scene,
		output,
		tool,
		layers,
	}: { scene: SceneInput | null; output: SceneOutput | null; tool: Tool; layers: Layers } =
		$props();

	let canvas: HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = $state(null);
	let scale = $state(1);

	const cursorMap: Record<Tool, string> = {
		select: 'cursor-default',
		pan: 'cursor-grab',
		'add-mesh': 'cursor-crosshair',
		'add-vertex': 'cursor-crosshair',
		delete: 'cursor-crosshair',
	};
	let offsetX = $state(0);
	let offsetY = $state(0);
	let mouse = $state<Point>({ x: 0, y: 0 });
	let mouseInCanvas = $state(false);
	let selection = $state<Selection>(null);
	let draftMesh = $state<Point[]>([]);
	let initialized = false;
	let drag:
		| { mode: 'pan'; last: Point }
		| { mode: 'vertex'; meshIndex: number; pointIndex: number }
		| { mode: 'mesh'; meshIndex: number; lastWorld: Point }
		| { mode: 'robot'; handle: 'start' | 'end' }
		| { mode: 'border'; handle: BorderHandle }
		| null = null;

	function sx(x: number) {
		return x * scale + offsetX;
	}

	function sy(y: number) {
		return y * scale + offsetY;
	}

	function worldFromScreen(screen: Point): Point {
		return {
			x: (screen.x - offsetX) / scale,
			y: (screen.y - offsetY) / scale,
		};
	}

	function screenFromEvent(event: MouseEvent | PointerEvent | WheelEvent): Point {
		const rect = canvas.getBoundingClientRect();
		return { x: event.clientX - rect.left, y: event.clientY - rect.top };
	}

	function expandBounds(bounds: { minX: number; minY: number; maxX: number; maxY: number }, point: Point) {
		bounds.minX = Math.min(bounds.minX, point.x);
		bounds.minY = Math.min(bounds.minY, point.y);
		bounds.maxX = Math.max(bounds.maxX, point.x);
		bounds.maxY = Math.max(bounds.maxY, point.y);
	}

	function getBounds() {
		if (scene?.borders) {
			const minX = Math.min(scene.borders.bottom_left.x, scene.borders.top_right.x);
			const minY = Math.min(scene.borders.bottom_left.y, scene.borders.top_right.y);
			const maxX = Math.max(scene.borders.bottom_left.x, scene.borders.top_right.x);
			const maxY = Math.max(scene.borders.bottom_left.y, scene.borders.top_right.y);
			const pad = 80;
			return { minX: minX - pad, minY: minY - pad, maxX: maxX + pad, maxY: maxY + pad };
		}
		const bounds = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
		for (const mesh of scene?.meshs ?? []) for (const point of mesh.points) expandBounds(bounds, point);
		for (const blob of output?.blobs ?? []) for (const point of blob.blob.points) expandBounds(bounds, point);
		if (scene?.robot) {
			expandBounds(bounds, scene.robot.start);
			expandBounds(bounds, scene.robot.end);
		}
		if (!Number.isFinite(bounds.minX)) return null;
		const pad = 80;
		return {
			minX: bounds.minX - pad,
			minY: bounds.minY - pad,
			maxX: bounds.maxX + pad,
			maxY: bounds.maxY + pad,
		};
	}

	function fitToScene() {
		if (!canvas) return;
		const bounds = getBounds();
		if (!bounds) return;
		const rect = canvas.getBoundingClientRect();
		const width = Math.max(1, rect.width);
		const height = Math.max(1, rect.height);
		const nextScale = Math.min(width / (bounds.maxX - bounds.minX), height / (bounds.maxY - bounds.minY));
		scale = nextScale;
		offsetX = (width - (bounds.maxX - bounds.minX) * nextScale) / 2 - bounds.minX * nextScale;
		offsetY = (height - (bounds.maxY - bounds.minY) * nextScale) / 2 - bounds.minY * nextScale;
		draw();
	}

	function drawPolyline(points: Point[], close: boolean) {
		if (!ctx || points.length === 0) return;
		ctx.beginPath();
		ctx.moveTo(sx(points[0].x), sy(points[0].y));
		for (let i = 1; i < points.length; i++) ctx.lineTo(sx(points[i].x), sy(points[i].y));
		if (close) ctx.closePath();
	}

	function drawPoint(point: Point, radius: number, color: string, square = false) {
		if (!ctx) return;
		ctx.beginPath();
		if (square) ctx.rect(sx(point.x) - radius, sy(point.y) - radius, radius * 2, radius * 2);
		else ctx.arc(sx(point.x), sy(point.y), radius, 0, Math.PI * 2);
		ctx.fillStyle = color;
		ctx.fill();
	}

	function borderRect() {
		if (!scene?.borders) return null;
		const left = Math.min(scene.borders.bottom_left.x, scene.borders.top_right.x);
		const right = Math.max(scene.borders.bottom_left.x, scene.borders.top_right.x);
		const top = Math.min(scene.borders.bottom_left.y, scene.borders.top_right.y);
		const bottom = Math.max(scene.borders.bottom_left.y, scene.borders.top_right.y);
		return { left, right, top, bottom };
	}

	function borderHandlePoints(rect: { left: number; right: number; top: number; bottom: number }) {
		const midX = (rect.left + rect.right) / 2;
		const midY = (rect.top + rect.bottom) / 2;
		return [
			{ handle: 'top-left' as const, point: { x: rect.left, y: rect.top } },
			{ handle: 'top' as const, point: { x: midX, y: rect.top } },
			{ handle: 'top-right' as const, point: { x: rect.right, y: rect.top } },
			{ handle: 'right' as const, point: { x: rect.right, y: midY } },
			{ handle: 'bottom-right' as const, point: { x: rect.right, y: rect.bottom } },
			{ handle: 'bottom' as const, point: { x: midX, y: rect.bottom } },
			{ handle: 'bottom-left' as const, point: { x: rect.left, y: rect.bottom } },
			{ handle: 'left' as const, point: { x: rect.left, y: midY } },
		];
	}

	function drawBorders() {
		if (!ctx) return;
		const rect = borderRect();
		if (!rect) return;
		ctx.beginPath();
		ctx.rect(sx(rect.left), sy(rect.top), (rect.right - rect.left) * scale, (rect.bottom - rect.top) * scale);
		ctx.strokeStyle = selection?.type === 'border' ? '#0f766e' : '#14b8a6';
		ctx.lineWidth = selection?.type === 'border' ? 3 : 2;
		ctx.setLineDash([8, 5]);
		ctx.stroke();
		ctx.setLineDash([]);
		for (const item of borderHandlePoints(rect)) {
			const selected = selection?.type === 'border' && selection.handle === item.handle;
			drawPoint(item.point, selected ? 6 : 5, selected ? '#0f766e' : '#14b8a6', true);
		}
	}

	function drawLabel(label: string | undefined, point: Point, color: string) {
		if (!ctx || !layers.labels || !label) return;
		ctx.fillStyle = color;
		ctx.font = '12px ui-monospace, monospace';
		ctx.fillText(label, sx(point.x) + 7, sy(point.y) - 7);
	}

	function drawArrow(from: Point, to: Point, color: string, width: number) {
		if (!ctx) return;
		const a = { x: sx(from.x), y: sy(from.y) };
		const b = { x: sx(to.x), y: sy(to.y) };
		const angle = Math.atan2(b.y - a.y, b.x - a.x);
		ctx.beginPath();
		ctx.moveTo(a.x, a.y);
		ctx.lineTo(b.x, b.y);
		ctx.strokeStyle = color;
		ctx.lineWidth = width;
		ctx.stroke();
		ctx.beginPath();
		ctx.moveTo(b.x, b.y);
		ctx.lineTo(b.x - Math.cos(angle - 0.5) * 10, b.y - Math.sin(angle - 0.5) * 10);
		ctx.lineTo(b.x - Math.cos(angle + 0.5) * 10, b.y - Math.sin(angle + 0.5) * 10);
		ctx.closePath();
		ctx.fillStyle = color;
		ctx.fill();
	}

	function drawDebugItem(item: DebugItem, index: number) {
		if (!ctx) return;
		const color = meshColors[(index + 4) % meshColors.length];
		ctx.setLineDash([]);
		if (item.type === 'point') {
			// Для точек всегда используем чёрный цвет, чтобы не было радуги
			const pointColor = '#111827';
			drawPoint(item.point, Math.max(1, 4 * scale), pointColor, true);
			drawLabel(item.label, item.point, pointColor);
		} else if (item.type === 'mesh') {
			ctx.setLineDash(item.dashed ? [8, 6] : []);
			drawPolyline(item.points, true);
			if (layers.fills) {
				ctx.fillStyle = `${color}22`;
				ctx.fill();
			}
			ctx.strokeStyle = color;
			ctx.lineWidth = 2;
			ctx.stroke();
			drawLabel(item.label, item.points[0], color);
		} else if (item.type === 'line') {
			drawPolyline([item.from, item.to], false);
			ctx.strokeStyle = color;
			ctx.lineWidth = 2;
			ctx.stroke();
			drawLabel(item.label, item.from, color);
		} else if (item.type === 'vector') {
			drawArrow(item.origin, { x: item.origin.x + item.vector.x, y: item.origin.y + item.vector.y }, color, 2);
			drawLabel(item.label, item.origin, color);
		} else if (item.type === 'path') {
			drawPolyline(item.points, false);
			ctx.strokeStyle = color;
			ctx.lineWidth = 4;
			ctx.stroke();
			if (item.points.length > 1) drawArrow(item.points[item.points.length - 2], item.points[item.points.length - 1], color, 2);
			drawLabel(item.label, item.points[0], color);
		} else if (item.type === 'triangulation') {
			ctx.strokeStyle = color;
			ctx.lineWidth = 1.5;
			ctx.setLineDash([4, 4]);
			for (let i = 0; i + 2 < item.triangles.length; i += 3) {
				const a = item.points[item.triangles[i]];
				const b = item.points[item.triangles[i + 1]];
				const c = item.points[item.triangles[i + 2]];
				if (!a || !b || !c) continue;
				drawPolyline([a, b, c], true);
				if (layers.fills) {
					ctx.fillStyle = `${color}12`;
					ctx.fill();
				}
				ctx.stroke();
			}
			ctx.setLineDash([]);
			if (layers.vertices) item.points.forEach((point) => drawPoint(point, 2.5, color, true));
			drawLabel(item.label, item.points[0], color);
		}
		ctx.setLineDash([]);
	}

	function draw() {
		if (!ctx || !canvas) return;
		const rect = canvas.getBoundingClientRect();
		ctx.clearRect(0, 0, rect.width, rect.height);
		ctx.fillStyle = theme.background;
		ctx.fillRect(0, 0, rect.width, rect.height);

		drawBorders();

		if (layers.obstacles && scene) {
			for (const [meshIndex, mesh] of scene.meshs.entries()) {
				if (mesh.points.length < 2) continue;
				const color = meshColors[meshIndex % meshColors.length];
				drawPolyline(mesh.points, mesh.points.length >= 3);
				if (mesh.points.length >= 3 && layers.fills) {
					ctx.fillStyle = `${color}26`;
					ctx.fill();
				}
				ctx.strokeStyle = color;
				ctx.lineWidth = selection?.type === 'mesh' && selection.meshIndex === meshIndex ? 4 : 2;
				ctx.setLineDash([]);
				ctx.stroke();
				if (layers.vertices) {
					mesh.points.forEach((point, pointIndex) => {
						const selected =
							selection?.type === 'vertex' &&
							selection.meshIndex === meshIndex &&
							selection.pointIndex === pointIndex;
						drawPoint(point, selected ? 6 : 4, selected ? '#111827' : color);
					});
				}
				drawLabel(`mesh ${meshIndex}`, mesh.points[0], color);
			}
		}

		if (layers.blobs) {
			for (const [index, blob] of (output?.blobs ?? []).entries()) {
				if (blob.blob.points.length < 3) continue;
				drawPolyline(blob.blob.points, true);
				ctx.strokeStyle = blobColor;
				ctx.lineWidth = 3;
				ctx.setLineDash([10, 7]);
				ctx.stroke();
				ctx.setLineDash([]);
				drawLabel(`blob ${index}`, blob.blob.points[0], blobColor);
			}
		}

		if (layers.debug) {
			for (const layout of output?.debug ?? []) {
				if (layers.debugLayouts[layout.name] === false) continue;
				layout.content.forEach(drawDebugItem);
			}
		}

		if (layers.robot && scene?.robot) {
			const rr = scene.robot.radius * scale;
			ctx.beginPath();
			ctx.arc(sx(scene.robot.start.x), sy(scene.robot.start.y), rr, 0, Math.PI * 2);
			ctx.fillStyle = robotFill;
			ctx.fill();
			ctx.strokeStyle = robotColor;
			ctx.lineWidth = 2;
			ctx.stroke();
			drawPoint(scene.robot.start, selection?.type === 'robot' && selection.handle === 'start' ? 7 : 5, robotColor);
			drawPoint(scene.robot.end, selection?.type === 'robot' && selection.handle === 'end' ? 7 : 5, '#dc2626');
			drawArrow(scene.robot.start, scene.robot.end, '#64748b', 1.5);
		}

		if (draftMesh.length > 0) {
			drawPolyline(draftMesh, false);
			ctx.strokeStyle = '#111827';
			ctx.lineWidth = 2;
			ctx.setLineDash([6, 5]);
			ctx.stroke();
			ctx.setLineDash([]);
			draftMesh.forEach((point) => drawPoint(point, 4, '#111827'));
		}
	}

	function hitTest(world: Point): Selection {
		if (!scene) return null;
		const tolerance = 9 / scale;
		const rect = borderRect();
		if (rect) {
			for (const item of borderHandlePoints(rect)) {
				if (distance(world, item.point) <= tolerance) return { type: 'border', handle: item.handle };
			}
			const edges: { handle: BorderHandle; from: Point; to: Point }[] = [
				{ handle: 'top', from: { x: rect.left, y: rect.top }, to: { x: rect.right, y: rect.top } },
				{ handle: 'right', from: { x: rect.right, y: rect.top }, to: { x: rect.right, y: rect.bottom } },
				{ handle: 'bottom', from: { x: rect.left, y: rect.bottom }, to: { x: rect.right, y: rect.bottom } },
				{ handle: 'left', from: { x: rect.left, y: rect.top }, to: { x: rect.left, y: rect.bottom } },
			];
			for (const edge of edges) {
				if (distanceToSegment(world, edge.from, edge.to) <= tolerance) return { type: 'border', handle: edge.handle };
			}
		}
		if (layers.robot) {
			if (distance(world, scene.robot.start) <= tolerance) return { type: 'robot', handle: 'start' };
			if (distance(world, scene.robot.end) <= tolerance) return { type: 'robot', handle: 'end' };
		}
		if (!layers.obstacles) return null;
		for (let meshIndex = scene.meshs.length - 1; meshIndex >= 0; meshIndex--) {
			const mesh = scene.meshs[meshIndex];
			for (let pointIndex = 0; pointIndex < mesh.points.length; pointIndex++) {
				if (distance(world, mesh.points[pointIndex]) <= tolerance) return { type: 'vertex', meshIndex, pointIndex };
			}
		}
		for (let meshIndex = scene.meshs.length - 1; meshIndex >= 0; meshIndex--) {
			const mesh = scene.meshs[meshIndex];
			if (mesh.points.length >= 3 && pointInPolygon(world, mesh.points)) return { type: 'mesh', meshIndex };
		}
		return null;
	}

	function findEdgeMesh(world: Point) {
		if (!scene) return -1;
		let bestMesh = -1;
		let bestDistance = Infinity;
		for (const [meshIndex, mesh] of scene.meshs.entries()) {
			for (let pointIndex = 0; pointIndex < mesh.points.length; pointIndex++) {
				const d = distanceToSegment(world, mesh.points[pointIndex], mesh.points[(pointIndex + 1) % mesh.points.length]);
				if (d < bestDistance) {
					bestDistance = d;
					bestMesh = meshIndex;
				}
			}
		}
		return bestDistance <= 18 / scale ? bestMesh : -1;
	}

	function deleteSelection(next: Selection) {
		if (!next) return;
		updateScene((draft) => {
			if (next.type === 'mesh') draft.meshs.splice(next.meshIndex, 1);
			if (next.type === 'vertex') {
				const mesh = draft.meshs[next.meshIndex];
				if (mesh.points.length <= 3) draft.meshs.splice(next.meshIndex, 1);
				else mesh.points.splice(next.pointIndex, 1);
			}
		});
		selection = null;
	}

	function onPointerDown(event: PointerEvent) {
		if (!canvas) return;
		canvas.setPointerCapture(event.pointerId);
		const screen = screenFromEvent(event);
		const world = worldFromScreen(screen);
		mouse = world;

		if (event.button === 1 || tool === 'pan') {
			drag = { mode: 'pan', last: screen };
			return;
		}

		if (tool === 'add-mesh') {
			draftMesh = [...draftMesh, world];
			draw();
			return;
		}

		if (tool === 'add-vertex') {
			const meshIndex = selection?.type === 'mesh' ? selection.meshIndex : findEdgeMesh(world);
			if (meshIndex >= 0) {
				updateScene((draft) => insertPointOnClosestEdge(draft.meshs[meshIndex], world));
				selection = { type: 'mesh', meshIndex };
			}
			return;
		}

		const next = hitTest(world);
		selection = next;
		if (tool === 'delete') {
			deleteSelection(next);
			return;
		}
		if (next?.type === 'vertex') drag = { mode: 'vertex', meshIndex: next.meshIndex, pointIndex: next.pointIndex };
		else if (next?.type === 'mesh') drag = { mode: 'mesh', meshIndex: next.meshIndex, lastWorld: world };
		else if (next?.type === 'robot') drag = { mode: 'robot', handle: next.handle };
		else if (next?.type === 'border') drag = { mode: 'border', handle: next.handle };
		draw();
	}

	function onPointerMove(event: PointerEvent) {
		const screen = screenFromEvent(event);
		const world = worldFromScreen(screen);
		mouse = world;
		mouseInCanvas = true;
		if (!drag) return;

		if (drag.mode === 'pan') {
			offsetX += screen.x - drag.last.x;
			offsetY += screen.y - drag.last.y;
			drag.last = screen;
			draw();
			return;
		}

		updateScene((draft) => {
			if (drag?.mode === 'vertex') {
				const mesh = draft.meshs[drag.meshIndex];
				mesh.points[drag.pointIndex] = clonePoint(world);
				mesh.points = ensureCcw(mesh.points);
			} else if (drag?.mode === 'mesh') {
				const dx = world.x - drag.lastWorld.x;
				const dy = world.y - drag.lastWorld.y;
				translateMesh(draft.meshs[drag.meshIndex], dx, dy);
				drag.lastWorld = world;
			} else if (drag?.mode === 'robot') {
				draft.robot[drag.handle] = clonePoint(world);
			} else if (drag?.mode === 'border') {
				const minSize = 1;
				const borders = draft.borders;
				if (drag.handle.includes('left')) borders.bottom_left.x = Math.min(world.x, borders.top_right.x - minSize);
				if (drag.handle.includes('right')) borders.top_right.x = Math.max(world.x, borders.bottom_left.x + minSize);
				if (drag.handle.includes('top')) borders.bottom_left.y = Math.min(world.y, borders.top_right.y - minSize);
				if (drag.handle.includes('bottom')) borders.top_right.y = Math.max(world.y, borders.bottom_left.y + minSize);
			}
		});
	}

	function onPointerUp(event: PointerEvent) {
		canvas?.releasePointerCapture(event.pointerId);
		drag = null;
	}

	function onWheel(event: WheelEvent) {
		event.preventDefault();
		const screen = screenFromEvent(event);
		const before = worldFromScreen(screen);
		const factor = event.deltaY < 0 ? 1.12 : 1 / 1.12;
		scale = Math.max(0.03, Math.min(80, scale * factor));
		offsetX = screen.x - before.x * scale;
		offsetY = screen.y - before.y * scale;
		draw();
	}

	function finishDraft() {
		if (draftMesh.length < 3) return;
		const points = ensureCcw(draftMesh.map(clonePoint));
		const meshIndex = scene?.meshs.length ?? 0;
		updateScene((draft) => draft.meshs.push({ points }));
		draftMesh = [];
		selection = { type: 'mesh', meshIndex };
		draw();
	}

	function onDoubleClick() {
		if (tool === 'add-mesh') finishDraft();
	}

	function onKeyDown(event: KeyboardEvent) {
		if (event.key === 'Enter' && tool === 'add-mesh') finishDraft();
		if (event.key === 'Escape') {
			draftMesh = [];
			drag = null;
			draw();
		}
		if ((event.key === 'Delete' || event.key === 'Backspace') && tool === 'select') deleteSelection(selection);
		if (event.key.toLowerCase() === 'f') fitToScene();
	}

	function resize() {
		if (!canvas) return;
		const rect = canvas.getBoundingClientRect();
		const dpr = Math.max(1, window.devicePixelRatio || 1);
		canvas.width = Math.max(1, Math.round(rect.width * dpr));
		canvas.height = Math.max(1, Math.round(rect.height * dpr));
		ctx = canvas.getContext('2d');
		ctx?.setTransform(dpr, 0, 0, dpr, 0, 0);
		if (!initialized) {
			initialized = true;
			fitToScene();
		} else {
			draw();
		}
	}

	$effect(() => {
		scene;
		output;
		layers;
		tool;
		if (canvas) draw();
	});

	onMount(() => {
		resize();
		const observer = new ResizeObserver(resize);
		observer.observe(canvas);
		window.addEventListener('keydown', onKeyDown);
		return () => {
			observer.disconnect();
			window.removeEventListener('keydown', onKeyDown);
		};
	});
</script>

<div class="relative h-full w-full bg-white">
	<canvas
		bind:this={canvas}
		class="block h-full w-full {cursorMap[tool]}"
		onpointerdown={onPointerDown}
		onpointermove={onPointerMove}
		onpointerup={onPointerUp}
		onpointercancel={onPointerUp}
		onmouseleave={() => (mouseInCanvas = false)}
		onwheel={onWheel}
		ondblclick={onDoubleClick}
	></canvas>

	<div class="absolute bottom-3 right-3 rounded border border-slate-200 bg-white px-2 py-1 font-mono text-xs text-slate-600 shadow-sm">
		{#if mouseInCanvas}
			{mouse.x.toFixed(1)}, {mouse.y.toFixed(1)}
		{:else}
			-
		{/if}
	</div>

	<button
		type="button"
		class="absolute right-3 top-3 rounded border border-slate-200 bg-white px-3 py-1.5 text-xs font-medium text-slate-700 shadow-sm hover:bg-slate-50"
		onclick={fitToScene}
	>
		Fit
	</button>

	{#if tool === 'add-mesh' && draftMesh.length > 0}
		<div class="absolute left-3 top-3 rounded border border-slate-200 bg-white px-3 py-2 text-xs text-slate-600 shadow-sm">
			Draft polygon: {draftMesh.length}
		</div>
	{/if}
</div>
