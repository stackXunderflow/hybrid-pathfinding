/// <reference types="svelte" />
/// <reference types="vite/client" />

import type { SceneOutput } from '../types';

declare global {
	interface Window {
		electronAPI?: {
			platform: string;
			runBinary: (scenePath?: string) => Promise<SceneOutput>;
			onBinaryChanged: (callback: () => void) => void;
		};
	}
}

export {};
