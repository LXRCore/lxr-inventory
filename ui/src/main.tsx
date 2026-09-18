import { createRoot } from 'react-dom/client';
import { App } from './App';
import { bootMock } from './nui';

createRoot(document.getElementById('root')!).render(<App />);
bootMock();
