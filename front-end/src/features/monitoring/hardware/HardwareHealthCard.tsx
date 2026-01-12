import { memo } from 'react';
import { useTelemetryStore } from '@/store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Badge } from '@/shared/components/ui/badge';
import { Thermometer, Fan, Zap, AlertTriangle } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { HardwareHealthDTO } from '@/types/omni';

// Helper extracted outside component
const getStatusColor = (health: HardwareHealthDTO): string => {
    if (health.fan_status === 'stopped' || health.fan_status === 'failing' || health.cooling_headroom < 5) {
        return 'text-red-500';
    }
    if (health.fan_status === 'degraded' || health.dry_thermal_paste || health.unstable_voltage) {
        return 'text-yellow-500';
    }
    return 'text-green-500';
};

export const HardwareHealthCard = memo(function HardwareHealthCard() {
    const data = useTelemetryStore((state) => state.liveData);

    if (!data?.hardware_health) {
        return (
            <Card className="h-full bg-white/5 backdrop-blur-md border-white/10">
                <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium flex items-center gap-2">
                        <Thermometer className="w-4 h-4 text-muted-foreground" />
                        Physical Diagnostics
                    </CardTitle>
                </CardHeader>
                <CardContent className="flex items-center justify-center h-32 text-muted-foreground text-xs">
                    Waiting for hardware data...
                </CardContent>
            </Card>
        );
    }
    const health = data.hardware_health;
    const statusColor = getStatusColor(health);

    return (
        <Card className="h-full bg-white/5 backdrop-blur-md border-white/10 overflow-hidden relative">
            <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center gap-2">
                    <Thermometer className="w-4 h-4 text-primary" />
                    Physical Diagnostics
                    <Badge variant="outline" className={cn("ml-auto", statusColor, "border-current bg-transparent")}>
                        {health.fan_status === 'healthy' && !health.unstable_voltage ? 'HEALTHY' : 'ATTENTION'}
                    </Badge>
                </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">

                {/* Critical Issues */}
                {health.diagnostics.length > 0 && (
                    <div className="bg-red-500/10 border border-red-500/20 rounded-md p-2 text-xs text-red-400">
                        {health.diagnostics.map((diag, i) => (
                            <div key={i} className="flex items-center gap-1.5 mb-1 last:mb-0">
                                <AlertTriangle className="w-3 h-3 flex-shrink-0" />
                                {diag}
                            </div>
                        ))}
                    </div>
                )}

                {/* Grid Metrics */}
                <div className="grid grid-cols-2 gap-2 text-sm">
                    {/* Thermal Efficiency */}
                    <div className="flex flex-col bg-white/5 p-2 rounded-md">
                        <span className="text-xs text-muted-foreground">Thermal Efficiency</span>
                        <div className="flex items-end justify-between mt-1">
                            <span className={cn("text-lg font-bold",
                                health.thermal_efficiency > 0.8 ? "text-green-400" :
                                    health.thermal_efficiency > 0.5 ? "text-yellow-400" : "text-red-400"
                            )}>
                                {(health.thermal_efficiency * 100).toFixed(0)}%
                            </span>
                            <span className="text-xs text-muted-foreground">Cooling</span>
                        </div>
                        {health.dry_thermal_paste && <span className="text-[10px] text-red-400 mt-1">Check Thermal Paste</span>}
                    </div>

                    {/* Voltage Stability */}
                    <div className="flex flex-col bg-white/5 p-2 rounded-md">
                        <span className="text-xs text-muted-foreground">Voltage Stability</span>
                        <div className="flex items-end justify-between mt-1">
                            <span className={cn("text-lg font-bold",
                                health.voltage_stability > 0.95 ? "text-green-400" :
                                    health.voltage_stability > 0.9 ? "text-yellow-400" : "text-red-400"
                            )}>
                                {(health.voltage_stability * 100).toFixed(0)}%
                            </span>
                            <Zap className="w-3 h-3 text-muted-foreground" />
                        </div>
                        {health.unstable_voltage && <span className="text-[10px] text-red-400 mt-1">Unstable</span>}
                    </div>
                </div>

                {/* Primary Metrics */}
                <div className="space-y-2">
                    <div className="flex justify-between items-center text-sm">
                        <div className="flex items-center gap-2 text-muted-foreground">
                            <Fan className="w-3 h-3" />
                            <span>Primary Fan</span>
                        </div>
                        <span className={cn("font-mono font-medium",
                            health.fan_status === 'stopped' ? 'text-red-500 animate-pulse' : ''
                        )}>
                            {health.primary_fan_rpm} RPM
                        </span>
                    </div>

                    <div className="flex justify-between items-center text-sm">
                        <div className="flex items-center gap-2 text-muted-foreground">
                            <Thermometer className="w-3 h-3" />
                            <span>Headroom</span>
                        </div>
                        <span className={cn("font-mono font-medium",
                            health.cooling_headroom < 10 ? "text-red-500" : "text-green-400"
                        )}>
                            {health.cooling_headroom.toFixed(1)}°C
                        </span>
                    </div>
                </div>

            </CardContent>
        </Card>
    );
});
