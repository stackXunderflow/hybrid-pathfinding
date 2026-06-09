import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
	plugins: [tailwindcss(), svelte()],
	root: 'src/renderer',
	base: './',
	build: {
		outDir: resolve(__dirname, 'dist'),
		emptyOutDir: true,
	},
	resolve: {
		alias: {
			'@': resolve('src/renderer/src'),
		},
	},
});
