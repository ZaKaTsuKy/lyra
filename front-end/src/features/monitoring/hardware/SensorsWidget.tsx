import { memo } from 'react';
import { useTelemetryStore } from '@/store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Fan, Zap } from 'lucide-react';

export const SensorsWidget = memo(function SensorsWidget() {
    const data = useTelemetryStore((state) => state.liveData);

    if (!data?.hardware_health) {
        return (
            <Card className="h-full bg-white/5 backdrop-blur-md border-white/10">
                <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium">Sensors</CardTitle>
                </CardHeader>
                <CardContent className="flex items-center justify-center h-32 text-muted-foreground text-xs">
                    Waiting for sensor data...
                </CardContent>
            </Card>
        );
    }
    const { primary_fan_rpm, vcore_voltage } = data.hardware_health;

    return (
        <Card className="h-full bg-white/5 backdrop-blur-md border-white/10">
            <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium">Sensors</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
                <div className="flex items-center justify-between p-2 bg-white/5 rounded-md">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-blue-500/20 rounded-full text-blue-400">
                            <Fan className="w-4 h-4" />
                        </div>
                        <div className="flex flex-col">
                            <span className="text-xs text-muted-foreground">CPU Fan</span>
                            <span className="font-mono text-sm font-bold">{primary_fan_rpm} RPM</span>
                        </div>
                    </div>
                </div>

                <div className="flex items-center justify-between p-2 bg-white/5 rounded-md">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-yellow-500/20 rounded-full text-yellow-400">
                            <Zap className="w-4 h-4" />
                        </div>
                        <div className="flex flex-col">
                            <span className="text-xs text-muted-foreground">Vcore</span>
                            <span className="font-mono text-sm font-bold">{vcore_voltage.toFixed(3)} V</span>
                        </div>
                    </div>
                </div>
            </CardContent>
        </Card>
    );
});
