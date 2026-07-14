import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { FinancePortal } from './FinancePortal';
import './styles.css';

createRoot(document.getElementById('root')!).render(<StrictMode><FinancePortal /></StrictMode>);
