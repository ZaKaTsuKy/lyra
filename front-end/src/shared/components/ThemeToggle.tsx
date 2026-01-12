import { Moon, Sun } from 'lucide-react';
import { Button } from '@/shared/components/ui/button';
import { usePreferencesStore } from '@/store/preferencesStore';

export function ThemeToggle() {
    const theme = usePreferencesStore((s) => s.theme);
    const setTheme = usePreferencesStore((s) => s.setTheme);

    const toggleTheme = () => {
        setTheme(theme === 'light' ? 'dark' : 'light');
    };

    return (
        <Button
            variant="ghost"
            size="icon"
            onClick={toggleTheme}
            className="rounded-full"
            aria-label="Toggle theme"
        >
            {theme === 'light' ? <Moon className="w-5 h-5" /> : <Sun className="w-5 h-5" />}
        </Button>
    );
}
