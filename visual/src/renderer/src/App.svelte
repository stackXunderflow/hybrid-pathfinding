<script lang="ts">
	import { onMount } from 'svelte';
	import Canvas from './components/Canvas.svelte';
	import { currentScene, loading, error, loadScene, initSceneWatch } from './lib/scene.svelte';

	onMount(async () => {
		initSceneWatch();
		await loadScene();
	});
</script>

<main>
	<h1>Hybrid Pathfinding</h1>

	{#if $loading && !$currentScene}
		<div class="status">Загрузка сцены...</div>
	{:else if $error}
		<div class="status error">{$error}</div>
	{:else if $currentScene}
		<div class="canvas-wrapper">
			<Canvas blobs={$currentScene.blobs} robot={$currentScene.robot} />
		</div>
		<div class="info">
			Блобов: {$currentScene.blobs.length} | Робот: ({$currentScene.robot.start.x}, {$currentScene.robot.start.y}) → ({$currentScene.robot.end.x}, {$currentScene.robot.end.y})
		</div>
	{/if}

	{#if $loading}
		<div class="status loading">Перезагрузка...</div>
	{/if}
</main>

<style>
	main {
		display: flex;
		flex-direction: column;
		height: 100vh;
		margin: 0;
		padding: 0;
		background: #f8f9fa;
		color: #212529;
		font-family: system-ui, sans-serif;
	}

	h1 {
		margin: 0;
		padding: 12px 20px;
		font-size: 1.1rem;
		color: #4361ee;
		background: #ffffff;
		border-bottom: 1px solid #dee2e6;
	}

	.canvas-wrapper {
		flex: 1;
		overflow: hidden;
	}

	.status {
		padding: 20px;
		text-align: center;
		color: #6c757d;
	}

	.status.error {
		color: #e63946;
	}

	.status.loading {
		position: fixed;
		bottom: 12px;
		right: 16px;
		padding: 6px 12px;
		font-size: 0.8rem;
		background: #ffffff;
		border: 1px solid #dee2e6;
		border-radius: 6px;
	}

	.info {
		position: fixed;
		bottom: 12px;
		left: 16px;
		padding: 6px 12px;
		font-size: 0.8rem;
		background: #ffffff;
		border: 1px solid #dee2e6;
		border-radius: 6px;
		color: #6c757d;
	}
</style>
