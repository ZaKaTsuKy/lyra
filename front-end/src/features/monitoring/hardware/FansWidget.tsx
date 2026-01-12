import React from 'react';
import { useTelemetryStore } from '../../../store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Fan as FanIcon } from 'lucide-react';
import { ProgressBar } from '@/shared/components/ui/progress-bar';
import type { FanDTO, FullSensorsDTO } from '../../../types/omni';

// ============================================
// Fan status helpers
// ============================================
function getFanStatus(rpm: number): { label: string; color: string } {
    if (rpm === 0) return { label: 'Stopped', color: 'text-red-500' };
    if (rpm < 500) return { label: 'Low', color: 'text-yellow-500' };
    if (rpm < 2000) return { label: 'Normal', color: 'text-green-500' };
    if (rpm < 3500) return { label: 'High', color: 'text-orange-500' };
    return { label: 'Max', color: 'text-red-500' };
}

function getRpmPercent(rpm: number, maxRpm: number = 5000): number {
    return Math.min((rpm / maxRpm) * 100, 100);
}

interface FanItemProps {
    fan: FanDTO;
    maxRpm?: number;
}

const FanItem: React.FC<FanItemProps> = ({ fan, maxRpm = 5000 }) => {
    const status = getFanStatus(fan.rpm);
    const percent = getRpmPercent(fan.rpm, maxRpm);

    // Animation speed based on RPM
    const animationDuration = fan.rpm > 0 ? Math.max(0.1, 60 / fan.rpm) : 0;

    return (
        <div className="flex items-center gap-3 p-2 rounded-lg bg-secondary/30 transition-all hover:bg-secondary/50">
            {/* Spinning fan icon */}
            <div className="relative w-8 h-8 flex items-center justify-center">
                <FanIcon
                    className={`w-6 h-6 ${fan.rpm > 0 ? 'text-blue-500' : 'text-gray-400'}`}
                    style={{
                        animation: fan.rpm > 0 ? `spin ${animationDuration}s linear infinite` : 'none'
                    }}
                />
            </div>

            {/* Fan info */}
            <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between">
                    <span className="font-medium text-sm truncate">{fan.label}</span>
                    <span className={`text-xs font-semibold ${status.color}`}>
                        {status.label}
                    </span>
                </div>
                <div className="flex items-center gap-2 mt-1">
                    <div className="flex-1">
                        <ProgressBar
                            value={percent}
                            variant={fan.rpm === 0 ? 'danger' : fan.rpm > 3000 ? 'warning' : 'success'}
                        />
                    </div>
                    <span className="text-xs font-mono text-muted-foreground w-16 text-right">
                        {fan.rpm} RPM
                    </span>
                </div>
            </div>
        </div>
    );
};

export const FansWidget: React.FC = React.memo(() => {
    const liveData = useTelemetryStore((s) => s.liveData);
    const sensors = liveData?.full_sensors as FullSensorsDTO | null | undefined;

    if (!sensors || !sensors.fans || sensors.fans.length === 0) {
        return (
            <Card className="h-full">
                <CardHeader className="pb-2">
                    <CardTitle className="flex items-center gap-2 text-sm">
                        <FanIcon className="w-4 h-4 text-blue-500" />
                        System Fans
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="text-muted-foreground text-sm">
                        No fans detected
                    </div>
                </CardContent>
            </Card>
        );
    }

    const fans = sensors.fans;
    const maxRpm = Math.max(...fans.map(f => f.rpm), 3000);
    const activeFans = fans.filter(f => f.rpm > 0).length;
    const totalFans = fans.length;

    return (
        <Card className="h-full">
            <CardHeader className="pb-2">
                <CardTitle className="flex items-center justify-between text-sm">
                    <div className="flex items-center gap-2">
                        <FanIcon className="w-4 h-4 text-blue-500" />
                        System Fans
                    </div>
                    <span className="text-xs text-muted-foreground font-normal">
                        {activeFans}/{totalFans} active
                    </span>
                </CardTitle>
            </CardHeader>
            <CardContent>
                <div className="space-y-2 max-h-64 overflow-y-auto">
                    {fans.map((fan, i) => (
                        <FanItem key={`fan-${i}-${fan.chip}-${fan.index}`} fan={fan} maxRpm={maxRpm} />
                    ))}
                </div>
            </CardContent>
        </Card>
    );
});

FansWidget.displayName = 'FansWidget';
