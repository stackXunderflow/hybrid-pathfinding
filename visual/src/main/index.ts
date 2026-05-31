import { app, BrowserWindow, dialog, ipcMain } from 'electron';
import { execFile } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { watch } from 'chokidar';
import type { BinaryRunResult, SceneInput, SceneOutput } from '../shared/types';

const __dirname = import.meta.dirname;

const visualDir = resolve(__dirname, '../..');
const binaryPath = (() => {
	const p = import.meta.env.VITE_BINARY_PATH;
	if (!p) throw new Error('VITE_BINARY_PATH is not set');
	return resolve(visualDir, p);
})();
const defaultScenePath = (() => {
	const p = import.meta.env.VITE_SCENE_PATH;
	if (!p) throw new Error('VITE_SCENE_PATH is not set');
	return resolve(visualDir, p);
})();

function execBinary(scenePath: string): Promise<BinaryRunResult> {
	return new Promise((resolve) => {
		execFile(binaryPath, ['--scene', scenePath], (err, stdout, stderr) => {
			let output: SceneOutput | null = null;
			let parseError: string | null = null;
			try {
				output = JSON.parse(stdout) as SceneOutput;
			} catch (e) {
				parseError = e instanceof Error ? e.message : String(e);
			}
			resolve({
				stdout,
				stderr,
				output,
				error: err ? err.message : parseError,
			});
		});
	});
}

let mainWindow: BrowserWindow | null = null;

async function readSceneFile(path: string): Promise<SceneInput> {
	const content = await readFile(path, 'utf8');
	return JSON.parse(content) as SceneInput;
}

async function writeSceneFile(path: string, scene: SceneInput): Promise<void> {
	await writeFile(path, `${JSON.stringify(scene, null, 2)}\n`, 'utf8');
}

ipcMain.handle('get-default-scene-path', () => defaultScenePath);

ipcMain.handle('load-scene-file', async (_event, scenePath?: string) => {
	const path = scenePath || defaultScenePath;
	return { path, scene: await readSceneFile(path) };
});

ipcMain.handle('open-scene-file', async () => {
	if (!mainWindow) return null;
	const result = await dialog.showOpenDialog(mainWindow, {
		title: 'Open scene',
		properties: ['openFile'],
		filters: [{ name: 'JSON scenes', extensions: ['json'] }],
	});
	if (result.canceled || result.filePaths.length === 0) return null;
	const path = result.filePaths[0];
	return { path, scene: await readSceneFile(path) };
});

ipcMain.handle('save-scene-file', async (_event, scenePath: string, scene: SceneInput) => {
	await writeSceneFile(scenePath, scene);
});

ipcMain.handle('save-scene-file-as', async (_event, scene: SceneInput, suggestedPath?: string) => {
	if (!mainWindow) return null;
	const result = await dialog.showSaveDialog(mainWindow, {
		title: 'Save scene',
		defaultPath: suggestedPath || defaultScenePath,
		filters: [{ name: 'JSON scenes', extensions: ['json'] }],
	});
	if (result.canceled || !result.filePath) return null;
	await writeSceneFile(result.filePath, scene);
	return { path: result.filePath };
});

ipcMain.handle('run-binary', async (_event, scenePath?: string) => {
	const path = scenePath || defaultScenePath;
	return await execBinary(path);
});

const createWindow = () => {
	const win = new BrowserWindow({
		width: 800,
		height: 600,
		webPreferences: {
			preload: resolve(__dirname, '../preload/index.js'),
		},
	});

	if (process.env.ELECTRON_RENDERER_URL) {
		win.loadURL(process.env.ELECTRON_RENDERER_URL);
	} else {
		win.loadFile(resolve(__dirname, '../renderer/index.html'));
	}

	mainWindow = win;
};

app.whenReady().then(() => {
	createWindow();

	const watcher = watch(binaryPath, { ignoreInitial: true });
	const notify = () => {
		if (mainWindow && !mainWindow.isDestroyed()) {
			mainWindow.webContents.send('binary-changed');
		}
	};
	watcher.on('change', notify);
	watcher.on('add', notify);
});
