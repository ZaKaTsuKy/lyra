import React from 'react';
import { useTelemetryStore } from '../../../store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Thermometer } from 'lucide-react';
import type { FullSensorsDTO } from '../../../types/omni';

// ============================================
// Temperature color scale: Green (30°C) -> Yellow (60°C) -> Red (90°C)
// ============================================
function getTempColor(temp: number, critical: number = 100): string {
    const normalized = Math.min(Math.max((temp - 30) / (critical - 30), 0), 1);

    if (normalized < 0.33) {
        // Green to Yellow
        const ratio = normalized / 0.33;
        const r = Math.round(34 + (234 - 34) * ratio);
        const g = Math.round(197 + (179 - 197) * ratio);
        const b = Math.round(94 + (8 - 94) * ratio);
        return `rgb(${r}, ${g}, ${b})`;
    } else if (normalized < 0.66) {
        // Yellow to Orange
        const ratio = (normalized - 0.33) / 0.33;
        const r = Math.round(234 + (249 - 234) * ratio);
        const g = Math.round(179 + (115 - 179) * ratio);
        const b = Math.round(8 + (22 - 8) * ratio);
        return `rgb(${r}, ${g}, ${b})`;
    } else {
        // Orange to Red
        const ratio = (normalized - 0.66) / 0.34;
        const r = Math.round(249 + (239 - 249) * ratio);
        const g = Math.round(115 + (68 - 115) * ratio);
        const b = Math.round(22 + (68 - 22) * ratio);
        return `rgb(${r}, ${g}, ${b})`;
    }
}

interface ThermalBlockProps {
    label: string;
    temp: number;
    critical?: number;
    subtitle?: string;
}

const ThermalBlock: React.FC<ThermalBlockProps> = ({ label, temp, critical = 100, subtitle }) => {
    const bgColor = getTempColor(temp, critical);
    const isWarm = temp > 60;

    return (
        <div
            className="relative p-3 rounded-lg transition-all duration-300 hover:scale-105 cursor-default"
            style={{ backgroundColor: bgColor }}
        >
            <div className={`font-semibold text-sm ${isWarm ? 'text-white' : 'text-gray-900'}`}>
                {label}
            </div>
            <div className={`text-2xl font-bold ${isWarm ? 'text-white' : 'text-gray-900'}`}>
                {temp.toFixed(0)}°C
            </div>
            {subtitle && (
                <div className={`text-xs ${isWarm ? 'text-white/80' : 'text-gray-600'}`}>
                    {subtitle}
                </div>
            )}
        </div>
    );
};

export const SensorsOverviewWidget: React.FC = React.memo(() => {
    const liveData = useTelemetryStore((s) => s.liveData);
    const sensors = liveData?.full_sensors as FullSensorsDTO | null | undefined;

    if (!sensors) {
        return (
            <Card className="h-full">
                <CardHeader className="pb-2">
                    <CardTitle className="flex items-center gap-2 text-sm">
                        <Thermometer className="w-4 h-4 text-orange-500" />
                        Thermal Overview
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="text-muted-foreground text-sm">
                        Waiting for sensor data...
                    </div>
                </CardContent>
            </Card>
        );
    }

    const cpuTemps = sensors.cpu_temps;
    const gpuSensors = sensors.gpu_sensors;
    const nvmeList = sensors.nvme_sensors || [];
    const genericTemps = sensors.temps_generic || [];

    // Determine main CPU temp (AMD vs Intel)
    const mainCpuTemp = cpuTemps.tctl > 0 ? cpuTemps.tctl : cpuTemps.package;
    const cpuLabel = cpuTemps.tctl > 0 ? 'CPU Tctl' : 'CPU Package';

    return (
        <Card className="h-full">
            <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-sm">
                    <Thermometer className="w-4 h-4 text-orange-500" />
                    Thermal Overview
                </CardTitle>
            </CardHeader>
            <CardContent>
                <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                    {/* CPU */}
                    {mainCpuTemp > 0 && (
                        <ThermalBlock
                            label={cpuLabel}
                            temp={mainCpuTemp}
                            critical={cpuTemps.critical}
                            subtitle={cpuTemps.tdie > 0 ? `Tdie: ${cpuTemps.tdie.toFixed(0)}°C` : undefined}
                        />
                    )}

                    {/* CPU CCDs */}
                    {cpuTemps.tccd && cpuTemps.tccd.map((temp, i) => (
                        <ThermalBlock
                            key={`ccd-${i}`}
                            label={`CCD ${i}`}
                            temp={temp}
                            critical={cpuTemps.critical}
                        />
                    ))}

                    {/* Intel Cores (show first 4) */}
                    {cpuTemps.cores && cpuTemps.cores.slice(0, 4).map((temp, i) => (
                        <ThermalBlock
                            key={`core-${i}`}
                            label={`Core ${i}`}
                            temp={temp}
                            critical={cpuTemps.critical}
                        />
                    ))}

                    {/* GPU */}
                    {gpuSensors && gpuSensors.edge_temp > 0 && (
                        <ThermalBlock
                            label="GPU Edge"
                            temp={gpuSensors.edge_temp}
                            critical={110}
                            subtitle={gpuSensors.hotspot_temp > 0 ? `Hotspot: ${gpuSensors.hotspot_temp.toFixed(0)}°C` : undefined}
                        />
                    )}

                    {gpuSensors && gpuSensors.mem_temp > 0 && (
                        <ThermalBlock
                            label="GPU VRAM"
                            temp={gpuSensors.mem_temp}
                            critical={110}
                        />
                    )}

                    {/* NVMe */}
                    {nvmeList.map((nvme) => (
                        <ThermalBlock
                            key={nvme.name}
                            label={nvme.name.toUpperCase()}
                            temp={nvme.temp_composite}
                            critical={70}
                        />
                    ))}

                    {/* Generic temps (first 4) */}
                    {genericTemps.slice(0, 4).map((temp) => (
                        <ThermalBlock
                            key={`${temp.chip}-${temp.index}`}
                            label={temp.label}
                            temp={temp.value}
                            critical={85}
                        />
                    ))}
                </div>

                {/* Legend */}
                <div className="mt-4 flex items-center gap-4 text-xs text-muted-foreground">
                    <div className="flex items-center gap-1">
                        <div className="w-3 h-3 rounded" style={{ backgroundColor: getTempColor(30) }} />
                        <span>Cool</span>
                    </div>
                    <div className="flex items-center gap-1">
                        <div className="w-3 h-3 rounded" style={{ backgroundColor: getTempColor(60) }} />
                        <span>Warm</span>
                    </div>
                    <div className="flex items-center gap-1">
                        <div className="w-3 h-3 rounded" style={{ backgroundColor: getTempColor(85) }} />
                        <span>Hot</span>
                    </div>
                </div>
            </CardContent>
        </Card>
    );
});

SensorsOverviewWidget.displayName = 'SensorsOverviewWidget';
