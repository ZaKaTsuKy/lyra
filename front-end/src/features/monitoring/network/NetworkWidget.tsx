import { memo } from "react";
import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { Skeleton } from "@/shared/components/ui/skeleton";
import { Wifi, ArrowDown, ArrowUp, Link2 } from "lucide-react";
import { formatBytes } from "@/lib/formatters";

/**
 * ✅ ENHANCED NETWORK WIDGET
 * 
 * Now displays:
 * - Rx/Tx bandwidth
 * - Network classification (idle, light, heavy, burst)
 * - TCP connections (established + time_wait)
 * - Interface name
 */

const CLASSIFICATION_COLORS: Record<string, string> = {
    'idle': 'bg-gray-500/20 text-gray-400',
    'light': 'bg-green-500/20 text-green-400',
    'moderate': 'bg-yellow-500/20 text-yellow-400',
    'heavy': 'bg-orange-500/20 text-orange-400',
    'burst': 'bg-red-500/20 text-red-400 animate-pulse',
};

export const NetworkWidget = memo(function NetworkWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);
    const netSpike = liveData?.anomaly.net_spike ?? false;

    if (!liveData) {
        return (
            <Card className="h-full">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <CardTitle className="text-sm font-medium">Network</CardTitle>
                    <Wifi className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                    <Skeleton className="h-24 w-full" />
                </CardContent>
            </Card>
        );
    }

    const { network } = liveData;
    const classification = network.classification || 'idle';
    const classColor = CLASSIFICATION_COLORS[classification] || CLASSIFICATION_COLORS['idle'];

    return (
        <Card className="h-full">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Network</CardTitle>
                <div className="flex items-center gap-2">
                    {netSpike && (
                        <Badge variant="danger" className="animate-pulse text-xs">SPIKE</Badge>
                    )}
                    <Wifi className="h-4 w-4 text-muted-foreground" />
                </div>
            </CardHeader>
            <CardContent className="space-y-3">
                {/* Rx/Tx Traffic */}
                <div className="space-y-2">
                    <div className="flex justify-between items-center text-sm">
                        <div className="flex items-center gap-1.5">
                            <ArrowDown className="w-3.5 h-3.5 text-green-500" />
                            <span className="text-muted-foreground">Rx:</span>
                        </div>
                        <span className="font-mono font-medium">{formatBytes(network.rx_bps)}/s</span>
                    </div>
                    <div className="flex justify-between items-center text-sm">
                        <div className="flex items-center gap-1.5">
                            <ArrowUp className="w-3.5 h-3.5 text-blue-500" />
                            <span className="text-muted-foreground">Tx:</span>
                        </div>
                        <span className="font-mono font-medium">{formatBytes(network.tx_bps)}/s</span>
                    </div>
                </div>

                {/* Classification Badge */}
                <div className="flex items-center justify-between">
                    <Badge className={`text-xs uppercase ${classColor}`}>
                        {classification}
                    </Badge>
                    <Badge variant="outline" className="text-xs font-mono">
                        {network.primary_iface}
                    </Badge>
                </div>

                {/* TCP Connections */}
                <div className="flex items-center gap-2 text-xs bg-secondary/30 rounded-md px-2 py-1.5">
                    <Link2 className="w-3 h-3 text-cyan-500" />
                    <span className="text-muted-foreground">TCP:</span>
                    <span className="font-mono font-medium text-green-500">
                        {network.tcp_established}
                    </span>
                    <span className="text-muted-foreground">established</span>
                    {network.tcp_time_wait > 0 && (
                        <>
                            <span className="text-muted-foreground/50">|</span>
                            <span className="font-mono text-yellow-500">
                                {network.tcp_time_wait}
                            </span>
                            <span className="text-muted-foreground">time_wait</span>
                        </>
                    )}
                </div>
            </CardContent>
        </Card>
    );
});
