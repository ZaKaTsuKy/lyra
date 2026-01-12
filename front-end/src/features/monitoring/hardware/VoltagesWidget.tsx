import React from 'react';
import { useTelemetryStore } from '../../../store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Zap } from 'lucide-react';
import type { VoltageDTO, FullSensorsDTO } from '../../../types/omni';

// ============================================
// Voltage stability indicator
// ============================================
function getVoltageStatus(voltage: number, label: string): { color: string; stable: boolean } {
    const lbl = label.toLowerCase();

    // Known voltage rails and their expected values
    if (lbl.includes('vcore') || lbl.includes('cpu')) {
        // Vcore typically 0.8-1.4V
        const stable = voltage >= 0.7 && voltage <= 1.5;
        return { color: stable ? 'text-green-500' : 'text-red-500', stable };
    }
    if (lbl.includes('+12') || lbl.includes('12v')) {
        const stable = voltage >= 11.4 && voltage <= 12.6;
        return { color: stable ? 'text-green-500' : 'text-yellow-500', stable };
    }
    if (lbl.includes('+5') || lbl.includes('5v')) {
        const stable = voltage >= 4.75 && voltage <= 5.25;
        return { color: stable ? 'text-green-500' : 'text-yellow-500', stable };
    }
    if (lbl.includes('+3.3') || lbl.includes('3.3v')) {
        const stable = voltage >= 3.1 && voltage <= 3.5;
        return { color: stable ? 'text-green-500' : 'text-yellow-500', stable };
    }

    // Generic - assume stable if reading is reasonable
    const stable = voltage > 0 && voltage < 15;
    return { color: 'text-blue-500', stable };
}

interface VoltageRowProps {
    voltage: VoltageDTO;
}

const VoltageRow: React.FC<VoltageRowProps> = ({ voltage }) => {
    const status = getVoltageStatus(voltage.value, voltage.label);

    return (
        <tr className="border-b border-secondary/50 hover:bg-secondary/30 transition-colors">
            <td className="py-2 px-3 text-sm font-medium">
                {voltage.label}
            </td>
            <td className={`py-2 px-3 text-sm font-mono text-right ${status.color}`}>
                {voltage.value.toFixed(3)} V
            </td>
            <td className="py-2 px-3 text-xs text-muted-foreground text-center">
                {status.stable ? '●' : '◐'}
            </td>
        </tr>
    );
};

export const VoltagesWidget: React.FC = React.memo(() => {
    const liveData = useTelemetryStore((s) => s.liveData);
    const sensors = liveData?.full_sensors as FullSensorsDTO | null | undefined;

    if (!sensors || !sensors.voltages || sensors.voltages.length === 0) {
        return (
            <Card className="h-full">
                <CardHeader className="pb-2">
                    <CardTitle className="flex items-center gap-2 text-sm">
                        <Zap className="w-4 h-4 text-yellow-500" />
                        Power Rails
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="text-muted-foreground text-sm">
                        No voltage sensors detected
                    </div>
                </CardContent>
            </Card>
        );
    }

    const voltages = sensors.voltages;
    const stableCount = voltages.filter(v => getVoltageStatus(v.value, v.label).stable).length;

    return (
        <Card className="h-full">
            <CardHeader className="pb-2">
                <CardTitle className="flex items-center justify-between text-sm">
                    <div className="flex items-center gap-2">
                        <Zap className="w-4 h-4 text-yellow-500" />
                        Power Rails
                    </div>
                    <span className="text-xs text-muted-foreground font-normal">
                        {stableCount}/{voltages.length} stable
                    </span>
                </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
                <div className="max-h-64 overflow-y-auto">
                    <table className="w-full">
                        <thead className="sticky top-0 bg-card">
                            <tr className="text-xs text-muted-foreground border-b">
                                <th className="py-2 px-3 text-left font-medium">Rail</th>
                                <th className="py-2 px-3 text-right font-medium">Value</th>
                                <th className="py-2 px-3 text-center font-medium">Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            {voltages.map((voltage, i) => (
                                <VoltageRow
                                    key={`voltage-${i}-${voltage.chip}-${voltage.index}`}
                                    voltage={voltage}
                                />
                            ))}
                        </tbody>
                    </table>
                </div>
            </CardContent>
        </Card>
    );
});

VoltagesWidget.displayName = 'VoltagesWidget';
