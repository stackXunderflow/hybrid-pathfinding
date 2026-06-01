import type { BinaryRunResult, SceneInput, SceneOutput } from '@/types';

const API_URL = import.meta.env.VITE_API_URL ?? '/solve';

function isElectron(): boolean {
	return typeof window !== 'undefined' && 'electronAPI' in window;
}

function defaultScene(): SceneInput {
	return {
		robot: { radius: 1, start: { x: 2, y: 2 }, end: { x: 8, y: 8 } },
		meshs: [],
	};
}

export async function loadScene(scenePath?: string): Promise<{ path: string; scene: SceneInput }> {
	if (isElectron()) {
		return window.electronAPI!.loadSceneFile(scenePath);
	}
	if (scenePath) {
		const resp = await fetch(scenePath);
		const scene = (await resp.json()) as SceneInput;
		return { path: scenePath, scene };
	}
	return { path: 'default', scene: defaultScene() };
}

export async function runBinary(
	path: string | null,
	scene: SceneInput,
): Promise<BinaryRunResult> {
	if (isElectron()) {
		return window.electronAPI!.runBinary(path ?? undefined);
	}
	try {
		const resp = await fetch(API_URL, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(scene),
		});
		if (!resp.ok) {
			return {
				stdout: '',
				stderr: `HTTP ${resp.status}`,
				output: null,
				error: `HTTP ${resp.status}`,
			};
		}
		const output = (await resp.json()) as SceneOutput;
		return { stdout: JSON.stringify(output), stderr: '', output, error: null };
	} catch (e) {
		const msg = e instanceof Error ? e.message : String(e);
		return { stdout: '', stderr: msg, output: null, error: msg };
	}
}

export async function openSceneFile(): Promise<{ path: string; scene: SceneInput } | null> {
	if (isElectron()) {
		return window.electronAPI!.openSceneFile();
	}
	return new Promise((resolve) => {
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = '.json';
		input.onchange = async () => {
			const file = input.files?.[0];
			if (!file) {
				resolve(null);
				return;
			}
			const text = await file.text();
			const scene = JSON.parse(text) as SceneInput;
			resolve({ path: file.name, scene });
		};
		input.click();
	});
}

export async function saveSceneFile(path: string, scene: SceneInput): Promise<void> {
	if (isElectron()) {
		return window.electronAPI!.saveSceneFile(path, scene);
	}
	const blob = new Blob([JSON.stringify(scene, null, 2)], { type: 'application/json' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = path;
	a.click();
	URL.revokeObjectURL(url);
}

export async function saveSceneFileAs(
	scene: SceneInput,
	suggestedPath?: string,
): Promise<{ path: string } | null> {
	if (isElectron()) {
		return window.electronAPI!.saveSceneFileAs(scene, suggestedPath);
	}
	const name = suggestedPath || 'scene.json';
	const blob = new Blob([JSON.stringify(scene, null, 2)], { type: 'application/json' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = name;
	a.click();
	URL.revokeObjectURL(url);
	return { path: name };
}

export function initSceneWatch(onChange: () => void): void {
	if (isElectron()) {
		window.electronAPI?.onBinaryChanged(onChange);
	}
}
