import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/server.ts', 'src/migrate.ts', 'src/scripts/create-admin.ts'],
  format: ['esm'],
  target: 'node20',
  clean: true,
  splitting: false,
  noExternal: ['@siagasos/shared'],
});
