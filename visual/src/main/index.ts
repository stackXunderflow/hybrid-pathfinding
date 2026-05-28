import { app, BrowserWindow, ipcMain } from 'electron';
import { execFile } from 'node:child_process';
import { resolve } from 'node:path';
import { watch } from 'chokidar';
import type { SceneOutput } from '../shared/types';

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

function execBinary(scenePath: string): Promise<string> {
	return new Promise((resolve, reject) => {
		execFile(binaryPath, ['--scene', scenePath], (err, stdout) => {
			if (err) reject(err);
			else resolve(stdout);
		});
	});
}

let mainWindow: BrowserWindow | null = null;

ipcMain.handle('run-binary', async (_event, scenePath?: string) => {
	const path = scenePath || defaultScenePath;
	const stdout = await execBinary(path);
	return JSON.parse(stdout) as SceneOutput;
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
