import { memo } from "react";
import { Server, Cpu, HardDrive, Clock, Layers } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { formatDuration } from "@/lib/formatters";
import type { SystemInstant, StaticDTO } from "@/types/omni";

interface SystemMetricsProps {
    staticInfo: StaticDTO | null;
    systemData: SystemInstant | null;
}

export const SystemMetrics = memo(function SystemMetrics({ staticInfo, systemData }: SystemMetricsProps) {
    if (!staticInfo) {
        return (
            <Card className="md:col-span-3">
                <CardHeader><Skeleton className="h-6 w-32" /></CardHeader>
                <CardContent className="space-y-4">
                    <Skeleton className="h-8 w-full" />
                    <Skeleton className="h-8 w-full" />
                </CardContent>
            </Card>
        );
    }

    const uptime = systemData ? formatDuration(systemData.uptime_sec) : "--";
    const oomKills = systemData?.oom_kills ?? 0;

    return (
        <Card className="md:col-span-3 h-full">
            <CardHeader>
                <CardTitle>System Information</CardTitle>
                <CardDescription>Host hardware and kernel metrics</CardDescription>
            </CardHeader>
            <CardContent>
                <div className="space-y-4">
                    {/* Hostname */}
                    <div className="flex items-center justify-between border-b pb-2">
                        <div className="flex items-center gap-2">
                            <Server className="w-4 h-4 text-primary" />
                            <span className="text-sm font-medium">Hostname</span>
                        </div>
                        <span className="font-mono text-sm">{staticInfo.hostname}</span>
                    </div>

                    {/* CPU Model */}
                    <div className="flex items-center justify-between border-b pb-2">
                        <div className="flex items-center gap-2">
                            <Cpu className="w-4 h-4 text-primary" />
                            <span className="text-sm font-medium">Model</span>
                        </div>
                        <span className="font-mono text-sm truncate max-w-[180px]" title={staticInfo.cpu_model}>
                            {staticInfo.cpu_model.split('@')[0]}
                        </span>
                    </div>

                    {/* Kernel & Threads */}
                    <div className="grid grid-cols-2 gap-4 border-b pb-2">
                        <div className="flex flex-col gap-1">
                            <div className="flex items-center gap-2 text-muted-foreground text-xs">
                                <HardDrive className="w-3 h-3" /> Kernel
                            </div>
                            <span className="font-mono text-sm">{staticInfo.kernel_version.split('-')[0]}</span>
                        </div>
                        <div className="flex flex-col gap-1">
                            <div className="flex items-center gap-2 text-muted-foreground text-xs">
                                <Layers className="w-3 h-3" /> Cores
                            </div>
                            <span className="font-mono text-sm">{staticInfo.core_count} Threads</span>
                        </div>
                    </div>

                    {/* Uptime */}
                    <div className="flex items-center justify-between pb-2 border-b">
                        <div className="flex items-center gap-2">
                            <Clock className="w-4 h-4 text-primary" />
                            <span className="text-sm font-medium">Uptime</span>
                        </div>
                        <span className="font-mono text-sm">{uptime}</span>
                    </div>

                    {/* Status Indicators */}
                    {systemData && (
                        <div className="grid grid-cols-2 gap-2 pt-1">
                            {/* OOM Kills */}
                            <div className={`p-2 rounded-md border text-center ${oomKills > 0 ? "bg-red-50 border-red-200" : "bg-secondary/20"}`}>
                                <div className="text-xs text-muted-foreground mb-1">OOM Kills</div>
                                <div className={`font-bold ${oomKills > 0 ? "text-red-600" : ""}`}>{oomKills}</div>
                            </div>

                            {/* Procs */}
                            <div className="p-2 rounded-md border bg-secondary/20 text-center">
                                <div className="text-xs text-muted-foreground mb-1">Tasks</div>
                                <div className="font-bold text-xs">
                                    {systemData.procs_running} Run / {systemData.procs_blocked} Blk
                                </div>
                            </div>

                            {/* PSI Check */}
                            <div className="col-span-2 flex justify-between items-center text-xs text-muted-foreground px-1">
                                <span>PSI (10s):</span>
                                <div className="flex gap-2 font-mono">
                                    <span title="CPU Pressure">C:{systemData.psi_cpu.toFixed(2)}</span>
                                    <span title="Memory Pressure">M:{systemData.psi_mem.toFixed(2)}</span>
                                    <span title="IO Pressure">I:{systemData.psi_io.toFixed(2)}</span>
                                </div>
                            </div>
                        </div>
                    )}
                </div>
            </CardContent>
        </Card>
    );
});
