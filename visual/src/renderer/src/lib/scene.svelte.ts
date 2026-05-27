import { writable } from 'svelte/store';
import type { SceneOutput } from '@/types';

export const currentScene = writable<SceneOutput | null>(null);
export const loading = writable(false);
export const error = writable<string | null>(null);

export async function loadScene(scenePath?: string) {
	loading.set(true);
	error.set(null);
	try {
		const result = await window.electronAPI!.runBinary(scenePath);
		currentScene.set(result);
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
		currentScene.set(null);
	} finally {
		loading.set(false);
	}
}

export function initSceneWatch() {
	window.electronAPI?.onBinaryChanged(() => {
		loadScene();
	});
}
