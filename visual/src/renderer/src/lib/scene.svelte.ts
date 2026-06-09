import { writable } from 'svelte/store';
import type { SceneInput, SceneOutput } from '@/types';

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

const apiUrl = import.meta.env.VITE_API_URL || '/solve';
const isElectron = () => window.electronAPI !== undefined;

activeScenePath.subscribe((value) => {
	currentPath = value;
});

sceneInput.subscribe((value) => {
	currentInput = value;
});

function cloneScene(scene: SceneInput): SceneInput {
	return JSON.parse(JSON.stringify(scene)) as SceneInput;
}

let fileInput: HTMLInputElement | undefined;
function getFileInput(): HTMLInputElement {
	if (!fileInput) {
		fileInput = document.createElement('input');
		fileInput.type = 'file';
		fileInput.accept = '.json';
		fileInput.style.display = 'none';
		document.body.appendChild(fileInput);
	}
	return fileInput;
}

function downloadScene(scene: SceneInput, filename: string) {
	const blob = new Blob([JSON.stringify(scene, null, 2)], { type: 'application/json' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	a.click();
	URL.revokeObjectURL(url);
}

export async function loadDefaultScene() {
	if (!isElectron()) {
		sceneInput.set({
			robot: { radius: 30, start: { x: 100, y: 100 }, end: { x: 500, y: 500 } },
			borders: { bottom_left: { x: 0, y: 0 }, top_right: { x: 600, y: 600 } },
			meshs: [],
		});
		dirty.set(false);
		return;
	}
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
		if (isElectron()) {
			const result = await window.electronAPI!.runBinary(currentPath ?? undefined);
			runLogs.set({
				stdout: result.stdout,
				stderr: result.stderr,
				ranAt: Date.now(),
				error: result.error,
			});
			sceneOutput.set(result.output);
			if (result.error) error.set(result.error);
		} else {
			const res = await fetch(apiUrl, {
				method: 'POST',
				body: JSON.stringify(currentInput),
				headers: { 'Content-Type': 'application/json' },
			});
			if (!res.ok) throw new Error(`Server error: ${res.status} ${res.statusText}`);
			const output: SceneOutput = await res.json();
			sceneOutput.set(output);
			runLogs.set({
				stdout: JSON.stringify(output, null, 2),
				stderr: '',
				ranAt: Date.now(),
				error: null,
			});
		}
	} catch (e) {
		error.set(e instanceof Error ? e.message : String(e));
		sceneOutput.set(null);
	} finally {
		loading.set(false);
	}
}

export async function openScene() {
	if (!isElectron()) {
		const input = getFileInput();
		const file = await new Promise<File | null>((resolve) => {
			input.onchange = () => {
				resolve(input.files?.[0] ?? null);
			};
			input.click();
		});
		if (!file) return;
		try {
			const text = await file.text();
			const scene = JSON.parse(text) as SceneInput;
			activeScenePath.set(file.name);
			sceneInput.set(scene);
			dirty.set(false);
			await runBinary();
		} catch (e) {
			error.set(e instanceof Error ? e.message : String(e));
		}
		return;
	}
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
	if (!isElectron()) {
		downloadScene(currentInput, currentPath ?? 'scene.json');
		dirty.set(false);
		await runBinary();
		return;
	}
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
	if (!isElectron()) {
		downloadScene(currentInput, 'scene.json');
		dirty.set(false);
		await runBinary();
		return;
	}
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
