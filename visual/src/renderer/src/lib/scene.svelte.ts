import { writable } from 'svelte/store';
import type { SceneInput, SceneOutput } from '@/types';

export const sceneInput = writable<SceneInput | null>(null);
export const sceneOutput = writable<SceneOutput | null>(null);
export const activeScenePath = writable<string | null>(null);
export const loading = writable(false);
export const error = writable<string | null>(null);
export const dirty = writable(false);

let currentPath: string | null = null;
let currentInput: SceneInput | null = null;

activeScenePath.subscribe((value) => {
	currentPath = value;
});

sceneInput.subscribe((value) => {
	currentInput = value;
});

function cloneScene(scene: SceneInput): SceneInput {
	return JSON.parse(JSON.stringify(scene)) as SceneInput;
}

export async function loadDefaultScene() {
	loading.set(true);
	error.set(null);
	try {
		const result = await window.electronAPI!.loadSceneFile();
		activeScenePath.set(result.path);
		sceneInput.set(result.scene);
		dirty.set(false);
		await runBinary();
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
		sceneInput.set(null);
		sceneOutput.set(null);
	} finally {
		loading.set(false);
	}
}

export async function runBinary() {
	loading.set(true);
	error.set(null);
	try {
		const result = await window.electronAPI!.runBinary(currentPath ?? undefined);
		sceneOutput.set(result);
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
		sceneOutput.set(null);
	} finally {
		loading.set(false);
	}
}

export async function openScene() {
	loading.set(true);
	error.set(null);
	try {
		const result = await window.electronAPI!.openSceneFile();
		if (!result) return;
		activeScenePath.set(result.path);
		sceneInput.set(result.scene);
		dirty.set(false);
		await runBinary();
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
	} finally {
		loading.set(false);
	}
}

export async function saveScene() {
	if (!currentInput) return;
	loading.set(true);
	error.set(null);
	try {
		if (currentPath) {
			await window.electronAPI!.saveSceneFile(currentPath, currentInput);
		} else {
			const result = await window.electronAPI!.saveSceneFileAs(currentInput, currentPath ?? undefined);
			if (!result) return;
			activeScenePath.set(result.path);
		}
		dirty.set(false);
		await runBinary();
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
	} finally {
		loading.set(false);
	}
}

export async function saveSceneAs() {
	if (!currentInput) return;
	loading.set(true);
	error.set(null);
	try {
		const result = await window.electronAPI!.saveSceneFileAs(currentInput, currentPath ?? undefined);
		if (!result) return;
		activeScenePath.set(result.path);
		dirty.set(false);
		await runBinary();
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
	} finally {
		loading.set(false);
	}
}

export function updateScene(updater: (scene: SceneInput) => void) {
	if (!currentInput) return;
	const next = cloneScene(currentInput);
	updater(next);
	sceneInput.set(next);
	dirty.set(true);
}

export function initSceneWatch() {
	window.electronAPI?.onBinaryChanged(() => {
		runBinary();
	});
}
