import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { AdminPortal } from './AdminPortal';
import './styles.css';
createRoot(document.getElementById('root')!).render(<StrictMode><AdminPortal /></StrictMode>);
