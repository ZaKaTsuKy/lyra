import { memo } from "react";
import { Battery, BatteryCharging, Clock } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ProgressBar } from "@/components/ui/progress-bar";
import { formatDuration } from "@/lib/formatters";
import type { BatteryInstant } from "@/types/omni";

interface BatteryCardProps {
    data: BatteryInstant;
}

export const BatteryCard = memo(function BatteryCard({ data }: BatteryCardProps) {
    if (!data || !data.present) return null;

    const isCharging = data.status.toLowerCase() === 'charging';
    const isCritical = data.percent < 20 && !isCharging;

    return (
        <Card className={isCritical ? "border-red-500 bg-red-500/5" : ""}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Battery</CardTitle>
                {isCharging ? (
                    <BatteryCharging className="h-4 w-4 text-green-500" />
                ) : (
                    <Battery className={`h-4 w-4 ${isCritical ? "text-red-500" : "text-muted-foreground"}`} />
                )}
            </CardHeader>
            <CardContent className="space-y-4">
                <div className="flex items-center justify-between">
                    <span className="text-2xl font-bold">{data.percent}%</span>
                    <Badge variant={isCharging ? "success" : isCritical ? "danger" : "warning"}>
                        {data.status}
                    </Badge>
                </div>

                <ProgressBar
                    value={data.percent}
                    variant={isCharging ? "success" : isCritical ? "danger" : "default"}
                    className="h-2"
                />

                <div className="flex justify-between items-center text-sm pt-2 border-t">
                    <div className="flex items-center gap-1 text-muted-foreground">
                        <Clock className="w-3 h-3" />
                        <span>Time Remaining</span>
                    </div>
                    <span className="font-mono">
                        {data.time_remaining_min > 0 ? formatDuration(data.time_remaining_min * 60) : "--"}
                    </span>
                </div>
                <div className="text-xs text-right text-muted-foreground">
                    {data.power_w.toFixed(1)} W
                </div>
            </CardContent>
        </Card>
    );
});
