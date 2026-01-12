import { memo } from "react";
import { Zap, Thermometer, Database, Activity } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { ProgressBar } from '@/shared/components/ui/progress-bar';
import { Badge } from '@/shared/components/ui/badge';
import { formatBytes } from "@/lib/formatters";
import type { GPUInstant } from "@/types/omni";

interface GpuCardProps {
    data: GPUInstant | null;
}

export const GpuCard = memo(function GpuCard({ data }: GpuCardProps) {
    if (!data) return null;

    const vramPercent = data.mem_total > 0 ? (data.mem_used / data.mem_total) * 100 : 0;

    return (
        <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">GPU: {data.name}</CardTitle>
                <Activity className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent className="space-y-4">
                {/* Utilization */}
                <div className="space-y-1">
                    <div className="flex justify-between text-sm">
                        <span className="text-muted-foreground">Core Load</span>
                        <span className="font-bold">{data.util}%</span>
                    </div>
                    <ProgressBar value={data.util} className="h-2" />
                </div>

                {/* VRAM */}
                <div className="space-y-1">
                    <div className="flex justify-between text-sm">
                        <div className="flex items-center gap-1 text-muted-foreground">
                            <Database className="w-3 h-3" />
                            <span>VRAM</span>
                        </div>
                        <span className="text-xs">
                            {formatBytes(data.mem_used * 1024 * 1024)} / {formatBytes(data.mem_total * 1024 * 1024)}
                        </span>
                    </div>
                    <ProgressBar value={vramPercent} variant="default" className="h-2" />
                </div>

                {/* Badges */}
                <div className="flex justify-between pt-2">
                    <Badge variant="outline" className="flex items-center gap-1">
                        <Thermometer className="w-3 h-3" />
                        {data.temp}°C
                    </Badge>
                    <Badge variant="outline" className="flex items-center gap-1">
                        <Zap className="w-3 h-3" />
                        {data.power_draw.toFixed(0)}W / {data.power_limit.toFixed(0)}W
                    </Badge>
                </div>
            </CardContent>
        </Card>
    );
});
