import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';

const __dirname = dirname(fileURLToPath(import.meta.url));

const rendererDir = resolve(__dirname, 'src/renderer');

export default defineConfig({
	plugins: [tailwindcss(), svelte()],
	root: rendererDir,
	base: '/',
	publicDir: false,
	build: {
		outDir: resolve(__dirname, 'dist-web'),
		emptyOutDir: true,
		rollupOptions: {
			input: resolve(rendererDir, 'index.web.html'),
		},
	},
	resolve: {
		alias: {
			'@': resolve(rendererDir, 'src'),
		},
	},
});
