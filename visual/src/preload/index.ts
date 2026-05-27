import { contextBridge, ipcRenderer } from 'electron';
import type { SceneOutput } from '../shared/types';

contextBridge.exposeInMainWorld('electronAPI', {
	platform: process.platform,
	runBinary: (scenePath?: string) =>
		ipcRenderer.invoke('run-binary', scenePath) as Promise<SceneOutput>,
	onBinaryChanged: (callback: () => void) => {
		ipcRenderer.on('binary-changed', () => callback());
	},
});
