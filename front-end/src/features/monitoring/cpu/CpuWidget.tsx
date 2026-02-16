import { memo } from "react";
import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Cpu, Thermometer, Gauge, Activity } from "lucide-react";
import { CpuHeatmap } from "@/components/charts/CpuHeatmap";

/**
 * ✅ ENHANCED CPU WIDGET
 * 
 * Now displays:
 * - Load average (1, 5, 15 min)
 * - CPU Frequency (current/max)
 * - Temperature
 * - Pressure Stall Information
 * - Spike detection
 */
export const CpuWidget = memo(function CpuWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);
    const staticInfo = useTelemetryStore((s) => s.staticInfo);

    const coreCount = staticInfo?.static.core_count ?? 1;

    // CPU Load
    const load1 = liveData?.cpu.load1 ?? 0;
    const load5 = liveData?.cpu.load5 ?? 0;
    const load15 = liveData?.cpu.load15 ?? 0;
    const cpuLoadVal = (load1 / coreCount) * 100;

    // CPU Frequency
    const freqAvg = liveData?.cpu.freq_avg ?? 0;
    const freqMax = liveData?.cpu.freq_max ?? 0;

    // Temperature
    const cpuTemp = liveData?.cpu.temp_package ?? 0;

    // Pressure (Linux PSI)
    const pressure = liveData?.cpu.pressure_avg10 ?? 0;

    // Spike detection
    const cpuSpike = liveData?.anomaly.cpu_spike ?? false;

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">CPU Usage</CardTitle>
                <div className="flex items-center gap-2">
                    {cpuSpike && (
                        <Badge variant="danger" className="animate-pulse text-xs">SPIKE</Badge>
                    )}
                    <Cpu className="h-4 w-4 text-muted-foreground" />
                </div>
            </CardHeader>
            <CardContent className="space-y-3">
                {/* Main Load Display */}
                <div className="flex justify-between items-baseline">
                    <div className="text-2xl font-bold">
                        {cpuLoadVal.toFixed(1)}%
                    </div>
                    <div className="text-xs text-muted-foreground font-mono">
                        Load: {load1.toFixed(2)} / {load5.toFixed(2)} / {load15.toFixed(2)}
                    </div>
                </div>

                <ProgressBar value={cpuLoadVal} max={100} />

                {/* Frequency & Temperature Row */}
                <div className="grid grid-cols-2 gap-2 text-xs">
                    {/* Frequency */}
                    <div className="flex items-center gap-1.5 bg-secondary/30 rounded-md px-2 py-1.5">
                        <Gauge className="w-3 h-3 text-blue-500" />
                        <span className="text-muted-foreground">Freq:</span>
                        <span className="font-mono font-medium">
                            {(freqAvg / 1000).toFixed(2)} GHz
                        </span>
                        <span className="text-muted-foreground/60 text-[10px]">
                            / {(freqMax / 1000).toFixed(1)}
                        </span>
                    </div>

                    {/* Temperature */}
                    <div className="flex items-center gap-1.5 bg-secondary/30 rounded-md px-2 py-1.5">
                        <Thermometer className={`w-3 h-3 ${cpuTemp > 80 ? 'text-red-500' : cpuTemp > 60 ? 'text-orange-500' : 'text-green-500'}`} />
                        <span className="text-muted-foreground">Temp:</span>
                        <span className={`font-mono font-medium ${cpuTemp > 80 ? 'text-red-500' : ''}`}>
                            {cpuTemp.toFixed(0)}°C
                        </span>
                    </div>
                </div>

                {/* Pressure Indicator */}
                {pressure > 0 && (
                    <div className="flex items-center gap-2 text-xs">
                        <Activity className={`w-3 h-3 ${pressure > 10 ? 'text-red-500' : pressure > 5 ? 'text-yellow-500' : 'text-green-500'}`} />
                        <span className="text-muted-foreground">CPU Pressure:</span>
                        <span className={`font-mono ${pressure > 10 ? 'text-red-500 font-semibold' : ''}`}>
                            {pressure.toFixed(1)}%
                        </span>
                        {pressure > 10 && (
                            <Badge variant="warning" className="text-[10px] px-1 py-0">Stalled</Badge>
                        )}
                    </div>
                )}

                {/* Heatmap */}
                <CpuHeatmap coreCount={coreCount} overallLoad={cpuLoadVal} />
            </CardContent>
        </Card>
    );
});