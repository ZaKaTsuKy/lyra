import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { Skeleton } from "@/shared/components/ui/skeleton";
import { Wifi } from "lucide-react";
import { formatBytes } from "@/lib/formatters";

export function NetworkWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Network</CardTitle>
                <Wifi className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
                {liveData ? (
                    <div className="space-y-1">
                        <div className="flex justify-between text-sm">
                            <span className="text-muted-foreground">Rx:</span>
                            <span className="font-mono">{formatBytes(liveData.network.rx_bps)}/s</span>
                        </div>
                        <div className="flex justify-between text-sm">
                            <span className="text-muted-foreground">Tx:</span>
                            <span className="font-mono">{formatBytes(liveData.network.tx_bps)}/s</span>
                        </div>
                        <Badge variant="outline" className="mt-2 text-xs w-full justify-center">
                            {liveData.network.primary_iface}
                        </Badge>
                    </div>
                ) : <Skeleton className="h-16 w-full" />}
            </CardContent>
        </Card>
    );
}
