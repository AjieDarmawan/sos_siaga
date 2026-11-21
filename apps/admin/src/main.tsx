import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@portal/styles.css';
import './admin.css';
import { App } from './App';
import { initTheme } from '@portal/lib/theme';

initTheme();

createRoot(document.getElementById('root')!).render(<StrictMode><App /></StrictMode>);
