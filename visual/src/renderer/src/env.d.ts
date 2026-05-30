/// <reference types="svelte" />
/// <reference types="vite/client" />

import type { SceneInput, SceneOutput } from '../types';

declare global {
	interface Window {
		electronAPI?: {
			platform: string;
			getDefaultScenePath: () => Promise<string>;
			loadSceneFile: (scenePath?: string) => Promise<{ path: string; scene: SceneInput }>;
			openSceneFile: () => Promise<{ path: string; scene: SceneInput } | null>;
			saveSceneFile: (scenePath: string, scene: SceneInput) => Promise<void>;
			saveSceneFileAs: (scene: SceneInput, suggestedPath?: string) => Promise<{ path: string } | null>;
			runBinary: (scenePath?: string) => Promise<SceneOutput>;
			onBinaryChanged: (callback: () => void) => void;
		};
	}
}

export {};
