import { defineConfig } from 'vite';

export default defineConfig({
  base: process.env.BASE_URL || (process.env.NODE_ENV === 'production' ? '/BarRoomTrivia/' : '/'),
});
