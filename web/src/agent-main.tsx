import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { AgentPortal } from './AgentPortal';
import './styles.css';
createRoot(document.getElementById('root')!).render(<StrictMode><AgentPortal /></StrictMode>);
