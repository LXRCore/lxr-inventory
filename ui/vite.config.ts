import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// builds into ../html — the folder the fxmanifest ships. The kit files come from ./public verbatim.
export default defineConfig({
  plugins: [react()],
  base: './',
  publicDir: 'public',
  build: {
    outDir: '../html',
    emptyOutDir: false,
    assetsDir: '.',
    rollupOptions: { output: { format: 'iife', entryFileNames: 'app.js', assetFileNames: '[name][extname]' } },
    minify: true,
    sourcemap: false,
  },
});
