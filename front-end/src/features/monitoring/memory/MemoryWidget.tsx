import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Server } from "lucide-react";
import { formatBytes } from "@/lib/formatters";

export function MemoryWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);

    const ramUsagePercent = liveData ? (liveData.memory.used_kb / liveData.memory.total_kb) * 100 : 0;
    const swapUsage = liveData ? (liveData.memory.swap_used_kb / liveData.memory.swap_total_kb) * 100 : 0;

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Memory</CardTitle>
                <Server className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                <div className="flex justify-between items-start">
                    <div className="text-2xl font-bold">{liveData ? formatBytes(liveData.memory.used_kb * 1024) : '0 GB'}</div>
                    {liveData?.anomaly.mem_spike && (
                        <Badge variant="danger" className="animate-pulse">SPIKE</Badge>
                    )}
                </div>
                <p className="text-xs text-muted-foreground">
                    Used of {liveData ? formatBytes(liveData.memory.total_kb * 1024) : '...'}
                </p>
                <ProgressBar value={ramUsagePercent} variant="default" className="mt-3" />

                {swapUsage > 0 && liveData && (
                    <div className="mt-4 pt-4 border-t">
                        <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Swap</span>
                            <span className="text-destructive font-medium">
                                {formatBytes(liveData.memory.swap_used_kb * 1024)}
                            </span>
                        </div>
                        <ProgressBar value={swapUsage} variant="danger" className="h-1.5" />
                    </div>
                )}
            </CardContent>
        </Card>
    );
}
