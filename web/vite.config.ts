import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    sourcemap: true,
    outDir: 'dist',
    rollupOptions: {
      input: {
        employee: 'index.html',
        finance: 'finance.html',
        admin: 'admin.html',
        advisor: 'agent.html',
        commercial: 'commercial.html',
      },
    },
  },
  server: { port: 5173 },
});
