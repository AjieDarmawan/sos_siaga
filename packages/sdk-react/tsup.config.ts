import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.tsx'],
  format: ['esm', 'cjs'],
  dts: { resolve: true },
  clean: true,
  minify: true,
  target: 'es2019',
  external: ['react', '@siagasos/js'],
  noExternal: ['@siagasos/shared'],
  banner: { js: "'use client';" },
});
