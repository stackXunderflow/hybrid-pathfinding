import { contextBridge, ipcRenderer } from 'electron';
import type { SceneInput, SceneOutput } from '../shared/types';

contextBridge.exposeInMainWorld('electronAPI', {
	platform: process.platform,
	getDefaultScenePath: () => ipcRenderer.invoke('get-default-scene-path') as Promise<string>,
	loadSceneFile: (scenePath?: string) =>
		ipcRenderer.invoke('load-scene-file', scenePath) as Promise<{ path: string; scene: SceneInput }>,
	openSceneFile: () =>
		ipcRenderer.invoke('open-scene-file') as Promise<{ path: string; scene: SceneInput } | null>,
	saveSceneFile: (scenePath: string, scene: SceneInput) =>
		ipcRenderer.invoke('save-scene-file', scenePath, scene) as Promise<void>,
	saveSceneFileAs: (scene: SceneInput, suggestedPath?: string) =>
		ipcRenderer.invoke('save-scene-file-as', scene, suggestedPath) as Promise<{ path: string } | null>,
	runBinary: (scenePath?: string) =>
		ipcRenderer.invoke('run-binary', scenePath) as Promise<SceneOutput>,
	onBinaryChanged: (callback: () => void) => {
		ipcRenderer.on('binary-changed', () => callback());
	},
});
