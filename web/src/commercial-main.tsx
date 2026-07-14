import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { CommercialPortal } from './CommercialPortal';
import './styles.css';
createRoot(document.getElementById('root')!).render(<StrictMode><CommercialPortal /></StrictMode>);
