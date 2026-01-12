import { memo } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Box } from 'lucide-react';
import { Scene } from './components/Scene';

export const DigitalTwinWidget = memo(function DigitalTwinWidget() {
    return (
        <Card className="h-full bg-white/5 backdrop-blur-md border-white/10 overflow-hidden flex flex-col">
            <CardHeader className="pb-2 flex-shrink-0">
                <CardTitle className="text-sm font-medium flex items-center gap-2 text-slate-100">
                    <Box className="w-4 h-4 text-[#4ade80]" />
                    Smart Digital Twin
                </CardTitle>
            </CardHeader>
            <CardContent className="flex-1 min-h-0 p-2 relative">
                <Scene />
            </CardContent>
        </Card>
    );
});
