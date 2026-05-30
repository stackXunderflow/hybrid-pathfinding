<script lang="ts">
	import { onMount } from 'svelte';
	import Canvas from './components/Canvas.svelte';
	import {
		activeScenePath,
		dirty,
		error,
		initSceneWatch,
		loadDefaultScene,
		loading,
		openScene,
		runBinary,
		saveScene,
		saveSceneAs,
		sceneInput,
		sceneOutput,
		updateScene,
	} from './lib/scene.svelte';

	type Tool = 'select' | 'pan' | 'add-mesh' | 'add-vertex' | 'delete';

	let tool = $state<Tool>('select');
	let helpOpen = $state(false);
	let layers = $state({
		obstacles: true,
		robot: true,
		blobs: true,
		debug: true,
		vertices: true,
		fills: true,
		labels: false,
		debugLayouts: {} as Record<string, boolean>,
	});

	const tools: { id: Tool; label: string; icon: string }[] = [
		{ id: 'select', label: 'Select', icon: 'near_me' },
		{ id: 'pan', label: 'Pan', icon: 'pan_tool' },
		{ id: 'add-mesh', label: 'Polygon', icon: 'polyline' },
		{ id: 'add-vertex', label: 'Vertex', icon: 'add_circle' },
		{ id: 'delete', label: 'Delete', icon: 'delete' },
	];

	const baseLayers: { id: keyof Omit<typeof layers, 'debugLayouts'>; label: string }[] = [
		{ id: 'obstacles', label: 'Obstacles' },
		{ id: 'robot', label: 'Robot' },
		{ id: 'blobs', label: 'Convex hulls' },
	];

	const viewLayers: { id: keyof Omit<typeof layers, 'debugLayouts'>; label: string }[] = [
		{ id: 'vertices', label: 'Vertices' },
		{ id: 'fills', label: 'Fills' },
		{ id: 'labels', label: 'Labels' },
	];

	function fileName(path: string | null) {
		if (!path) return 'No scene';
		return path.split(/[\\/]/).at(-1) ?? path;
	}

	function directoryName(path: string | null) {
		if (!path) return '';
		const name = fileName(path);
		return path.slice(0, Math.max(0, path.length - name.length));
	}

	function toggleLayer(name: keyof Omit<typeof layers, 'debugLayouts'>) {
		layers = { ...layers, [name]: !layers[name] };
	}

	function toggleDebugLayout(name: string) {
		layers = {
			...layers,
			debugLayouts: { ...layers.debugLayouts, [name]: layers.debugLayouts[name] === false },
		};
	}

	function updateRadius(value: string) {
		const radius = Number(value);
		if (!Number.isFinite(radius) || radius <= 0) return;
		updateScene((draft) => {
			draft.robot.radius = radius;
		});
	}

	function onKeyDown(event: KeyboardEvent) {
		if ((event.ctrlKey || event.metaKey) && event.code === 'KeyS') {
			event.preventDefault();
			void saveScene();
		}
		if (event.code === 'Escape') helpOpen = false;
	}

	$effect(() => {
		const output = $sceneOutput;
		if (!output?.debug) return;
		let next = layers.debugLayouts;
		let changed = false;
		for (const layout of output.debug) {
			if (!(layout.name in next)) {
				next = { ...next, [layout.name]: true };
				changed = true;
			}
		}
		if (changed) layers = { ...layers, debugLayouts: next };
	});

	onMount(async () => {
		window.addEventListener('keydown', onKeyDown);
		initSceneWatch();
		await loadDefaultScene();
		return () => window.removeEventListener('keydown', onKeyDown);
	});
</script>

<main class="grid h-screen grid-rows-[56px_1fr_28px] bg-slate-100 text-slate-900">
	<header class="flex items-center gap-2 border-b border-slate-200 bg-white px-3 shadow-sm">
		<div class="mr-2 text-sm font-semibold text-slate-900">Hybrid Pathfinding</div>

		<button class="rounded border border-slate-200 px-3 py-1.5 text-xs font-medium hover:bg-slate-50" onclick={openScene}>
			Open
		</button>
		<button class="rounded border border-slate-200 px-3 py-1.5 text-xs font-medium hover:bg-slate-50" onclick={saveScene} disabled={!$sceneInput}>
			Save
		</button>
		<button class="rounded border border-slate-200 px-3 py-1.5 text-xs font-medium hover:bg-slate-50" onclick={saveSceneAs} disabled={!$sceneInput}>
			Save as
		</button>
		<button class="rounded bg-slate-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-slate-700" onclick={runBinary} disabled={!$activeScenePath}>
			Run
		</button>

		<div class="ml-3 min-w-0 flex-1 truncate rounded border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-xs text-slate-500" title={$activeScenePath ?? ''}>
			<span>{directoryName($activeScenePath)}</span><span class="font-semibold text-slate-950">{fileName($activeScenePath)}</span>
			{#if $dirty}
				<span class="ml-2 rounded bg-amber-100 px-1.5 py-0.5 font-medium text-amber-800">modified</span>
			{/if}
		</div>

		{#if $loading}
			<div class="rounded bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700">Running</div>
		{/if}
		<button
			class="grid h-8 w-8 place-items-center rounded border border-slate-200 text-slate-700 hover:bg-slate-50"
			title="Help"
			onclick={() => (helpOpen = true)}
		>
			<span class="material-symbols-outlined">help</span>
		</button>
	</header>

	<section class="grid min-h-0 grid-cols-[220px_1fr_260px]">
		<aside class="min-h-0 overflow-y-auto border-r border-slate-200 bg-white p-3">
			<div class="mb-4">
				<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Tools</div>
				<div class="grid grid-cols-5 gap-1">
					{#each tools as item}
						<button
							class={`grid h-10 place-items-center rounded border ${tool === item.id ? 'border-slate-900 bg-slate-900 text-white' : 'border-slate-200 text-slate-700 hover:bg-slate-50'}`}
							title={item.label}
							onclick={() => (tool = item.id)}
						>
							<span class="material-symbols-outlined">{item.icon}</span>
						</button>
					{/each}
				</div>
			</div>

			<div class="mb-4">
				<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Scene layers</div>
				{#each baseLayers as layer}
					<label class="flex cursor-pointer items-center justify-between rounded px-1.5 py-1 text-sm hover:bg-slate-50">
						<span>{layer.label}</span>
						<input
							class="layer-checkbox"
							type="checkbox"
							checked={layers[layer.id] as boolean}
							onchange={() => toggleLayer(layer.id)}
						/>
					</label>
				{/each}
			</div>

			<div class="mb-4 border-t border-slate-200 pt-4">
				<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Display</div>
				{#each viewLayers as layer}
					<label class="flex cursor-pointer items-center justify-between rounded px-1.5 py-1 text-sm hover:bg-slate-50">
						<span>{layer.label}</span>
						<input
							class="layer-checkbox"
							type="checkbox"
							checked={layers[layer.id] as boolean}
							onchange={() => toggleLayer(layer.id)}
						/>
					</label>
				{/each}
			</div>

			<div class="mb-4 border-t border-slate-200 pt-4">
				<div class="mb-2 flex items-center justify-between">
					<div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Debug</div>
					<input
						class="layer-checkbox"
						type="checkbox"
						title="Toggle debug"
						checked={layers.debug}
						onchange={() => toggleLayer('debug')}
					/>
				</div>
			</div>

			{#if $sceneOutput?.debug?.length}
				<div class="border-t border-slate-200 pt-4">
					<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Debug layouts</div>
					{#each $sceneOutput.debug as layout}
						<label class="flex cursor-pointer items-center justify-between rounded px-1.5 py-1 text-sm hover:bg-slate-50">
							<span class="truncate" title={layout.name}>{layout.name}</span>
							<input
								class="layer-checkbox"
								type="checkbox"
								checked={layers.debugLayouts[layout.name] !== false}
								onchange={() => toggleDebugLayout(layout.name)}
							/>
						</label>
					{/each}
				</div>
			{/if}
		</aside>

		<div class="min-h-0">
			{#if $sceneInput}
				<Canvas scene={$sceneInput} output={$sceneOutput} {tool} {layers} />
			{:else}
				<div class="grid h-full place-items-center text-sm text-slate-500">Scene is not loaded</div>
			{/if}
		</div>

		<aside class="min-h-0 overflow-y-auto border-l border-slate-200 bg-white p-3">
			<div class="mb-4">
				<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Robot</div>
				{#if $sceneInput}
					<label class="mb-2 block text-xs text-slate-500">
						Radius
						<input
							class="mt-1 w-full rounded border border-slate-200 px-2 py-1 text-sm"
							type="number"
							min="1"
							step="1"
							value={$sceneInput.robot.radius}
							onchange={(event) => updateRadius(event.currentTarget.value)}
						/>
					</label>
					<div class="grid grid-cols-2 gap-2 text-xs text-slate-600">
						<div class="rounded bg-slate-50 p-2">
							<div class="font-medium text-slate-900">Start</div>
							<div>{$sceneInput.robot.start.x.toFixed(1)}, {$sceneInput.robot.start.y.toFixed(1)}</div>
						</div>
						<div class="rounded bg-slate-50 p-2">
							<div class="font-medium text-slate-900">End</div>
							<div>{$sceneInput.robot.end.x.toFixed(1)}, {$sceneInput.robot.end.y.toFixed(1)}</div>
						</div>
					</div>
				{/if}
			</div>

			<div class="mb-4">
				<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Scene</div>
				<div class="space-y-1 text-sm text-slate-700">
					<div>Meshes: {$sceneInput?.meshs.length ?? 0}</div>
					<div>Blobs: {$sceneOutput?.blobs.length ?? 0}</div>
					<div>Debug: {$sceneOutput?.debug?.length ?? 0}</div>
				</div>
			</div>

			<div>
				<div class="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">Active tool</div>
				<div class="rounded bg-slate-50 p-2 text-sm font-medium text-slate-800">{tool}</div>
			</div>
		</aside>
	</section>

	<footer class="flex items-center gap-3 border-t border-slate-200 bg-white px-3 text-xs text-slate-500">
		{#if $error}
			<span class="truncate text-red-600">{$error}</span>
		{:else}
			<span>Ready</span>
		{/if}
	</footer>

	{#if helpOpen}
		<div class="fixed inset-0 z-50 grid place-items-center bg-slate-950/35 p-6" role="presentation" onclick={() => (helpOpen = false)}>
			<section
				class="w-full max-w-2xl rounded-lg border border-slate-200 bg-white shadow-xl"
				role="dialog"
				aria-modal="true"
				tabindex="-1"
				onclick={(event) => event.stopPropagation()}
				onkeydown={(event) => event.stopPropagation()}
			>
				<header class="flex items-center justify-between border-b border-slate-200 px-4 py-3">
					<div class="text-sm font-semibold text-slate-950">Help</div>
					<button class="grid h-8 w-8 place-items-center rounded hover:bg-slate-100" onclick={() => (helpOpen = false)} title="Close">
						<span class="material-symbols-outlined">close</span>
					</button>
				</header>
				<div class="grid gap-4 p-4 text-sm text-slate-700">
					<div class="grid grid-cols-[120px_1fr] gap-3">
						<div class="font-medium text-slate-950">Select</div>
						<div>Drag vertices, polygons, robot start, and robot end points.</div>
						<div class="font-medium text-slate-950">Pan</div>
						<div>Drag the viewport. Mouse wheel zooms to cursor.</div>
						<div class="font-medium text-slate-950">Polygon</div>
						<div>Click polygon points, then double click or press Enter to finish. Esc cancels the draft.</div>
						<div class="font-medium text-slate-950">Vertex</div>
						<div>Click near a polygon edge to insert a vertex.</div>
						<div class="font-medium text-slate-950">Delete</div>
						<div>Click a vertex or polygon to remove it.</div>
					</div>
					<div class="border-t border-slate-200 pt-3 text-xs text-slate-500">
						Ctrl+S saves the active scene. F fits the scene in the viewport. Convex hulls are shown as dashed contours.
					</div>
				</div>
			</section>
		</div>
	{/if}
</main>
