import { app, BrowserWindow, ipcMain } from 'electron';
import { execFile } from 'node:child_process';
import { resolve } from 'node:path';
import { watch } from 'chokidar';
import type { SceneOutput } from '../shared/types';

const __dirname = import.meta.dirname;

const visualDir = resolve(__dirname, '../..');
const binaryPath = resolve(visualDir, import.meta.env.VITE_BINARY_PATH || '../code/zig-out/bin/code');
const defaultScenePath = resolve(visualDir, import.meta.env.VITE_SCENE_PATH || '../code/scene.json');

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
	watcher.on('change', () => {
		if (mainWindow && !mainWindow.isDestroyed()) {
			mainWindow.webContents.send('binary-changed');
		}
	});
});
