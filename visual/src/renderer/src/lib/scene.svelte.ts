import { writable } from 'svelte/store';
import type { SceneInput, SceneOutput } from '@/types';
import * as api from './api';

export type RunLogs = {
	stdout: string;
	stderr: string;
	ranAt: number | null;
	error: string | null;
};

export const sceneInput = writable<SceneInput | null>(null);
export const sceneOutput = writable<SceneOutput | null>(null);
export const activeScenePath = writable<string | null>(null);
export const loading = writable(false);
export const error = writable<string | null>(null);
export const dirty = writable(false);
export const runLogs = writable<RunLogs>({
	stdout: '',
	stderr: '',
	ranAt: null,
	error: null,
});

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
		const result = await api.loadScene();
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
	if (!currentInput) return;
	loading.set(true);
	error.set(null);
	try {
		const result = await api.runBinary(currentPath, currentInput);
		runLogs.set({
			stdout: result.stdout,
			stderr: result.stderr,
			ranAt: Date.now(),
			error: result.error,
		});
		sceneOutput.set(result.output);
		if (result.error) error.set(result.error);
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
		const result = await api.openSceneFile();
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
			await api.saveSceneFile(currentPath, currentInput);
		} else {
			const result = await api.saveSceneFileAs(currentInput, currentPath ?? undefined);
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
		const result = await api.saveSceneFileAs(currentInput, currentPath ?? undefined);
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
	api.initSceneWatch(() => {
		runBinary();
	});
}
