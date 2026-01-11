import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Cpu, Thermometer } from "lucide-react";
import { CpuHeatmap } from "@/components/charts/CpuHeatmap";

export function CpuWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);
    const staticInfo = useTelemetryStore((s) => s.staticInfo);

    const coreCount = staticInfo?.static.core_count ?? 1;
    const cpuLoadVal = liveData ? (liveData.cpu.load1 / coreCount) * 100 : 0;
    const cpuLoad = cpuLoadVal.toFixed(2);
    const cpuTemp = liveData?.cpu.temp_package.toFixed(1) ?? '0.0';

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">CPU Usage</CardTitle>
                <Cpu className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="flex justify-between items-start">
                    <div className="text-2xl font-bold">{cpuLoad}% <span className="text-sm font-normal text-muted-foreground">load</span></div>
                    {liveData?.anomaly.cpu_spike && (
                        <Badge variant="danger" className="animate-pulse">SPIKE</Badge>
                    )}
                </div>
                <div className="flex items-center gap-2 mt-2">
                    <Thermometer className="w-3 h-3 text-red-500" />
                    <span className="text-xs text-muted-foreground">{cpuTemp}°C</span>
                </div>
                <ProgressBar value={cpuLoadVal} max={100} className="mt-3" />

                {/* Heatmap */}
                <CpuHeatmap coreCount={coreCount} overallLoad={cpuLoadVal} />
            </CardContent>
        </Card>
    );
}
