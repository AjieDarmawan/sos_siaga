import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Panel admin dipisah dari portal (origin berbeda, token berbeda), tapi memakai komponen & token desain portal.
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@portal': fileURLToPath(new URL('../portal/src', import.meta.url)) },
    dedupe: ['react', 'react-dom', '@phosphor-icons/react'],
  },
  server: { port: 5175, strictPort: true },
});
