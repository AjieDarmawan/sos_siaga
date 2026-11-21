import { defineConfig } from 'tsup';

export default defineConfig([
  {
    entry: ['src/index.ts'],
    format: ['esm', 'cjs'],
    dts: { resolve: true },
    clean: true,
    minify: true,
    target: 'es2019',
    noExternal: ['@siagasos/shared'],
  },
  {
    // <script src="https://unpkg.com/@siagasos/js"></script> → window.SiagaSOS.SiagaSOS.init(...)
    entry: { index: 'src/index.ts' },
    format: ['iife'],
    globalName: 'SiagaSOS',
    minify: true,
    target: 'es2019',
    noExternal: ['@siagasos/shared'],
  },
]);
