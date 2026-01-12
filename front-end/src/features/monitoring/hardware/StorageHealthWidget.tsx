import React, { useMemo } from 'react';
import { useTelemetryStore } from '../../../store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { HardDrive, Thermometer, Activity } from 'lucide-react';
import { ProgressBar } from '@/shared/components/ui/progress-bar';
import { formatBytes } from '@/lib/formatters';
import type { DiskInstant, NVMeSensorDTO, FullSensorsDTO } from '../../../types/omni';

// ============================================
// NVMe temperature color
// ============================================
function getNvmeHealthColor(temp: number): string {
    if (temp < 40) return 'text-green-500';
    if (temp < 55) return 'text-yellow-500';
    if (temp < 70) return 'text-orange-500';
    return 'text-red-500';
}

interface StorageItemProps {
    disk: DiskInstant;
    nvme?: NVMeSensorDTO;
}

const StorageItem: React.FC<StorageItemProps> = ({ disk, nvme }) => {
    const usageVariant = disk.percent > 90 ? 'danger' : disk.percent > 75 ? 'warning' : 'default';
    const tempColor = nvme ? getNvmeHealthColor(nvme.temp_composite) : '';

    return (
        <div className="p-3 rounded-lg bg-secondary/30 hover:bg-secondary/50 transition-all">
            <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                    <HardDrive className="w-4 h-4 text-blue-500" />
                    <span className="font-medium text-sm">{disk.mount}</span>
                </div>
                {nvme && (
                    <div className={`flex items-center gap-1 ${tempColor}`}>
                        <Thermometer className="w-3 h-3" />
                        <span className="text-xs font-mono">{nvme.temp_composite.toFixed(0)}°C</span>
                    </div>
                )}
            </div>

            {/* Usage bar */}
            <ProgressBar
                value={disk.percent}
                variant={usageVariant}
                label={`${disk.percent.toFixed(1)}%`}
            />

            {/* IO Stats */}
            <div className="flex items-center justify-between mt-2 text-xs text-muted-foreground">
                <div className="flex items-center gap-3">
                    <span title="Read">R: {formatBytes(disk.read_bps)}/s</span>
                    <span title="Write">W: {formatBytes(disk.write_bps)}/s</span>
                </div>
                <div className="flex items-center gap-1">
                    <Activity className="w-3 h-3" />
                    <span>{disk.read_iops.toFixed(0)}+{disk.write_iops.toFixed(0)} IOPS</span>
                </div>
            </div>

            {/* IO Wait if high */}
            {disk.io_wait_pct > 5 && (
                <div className="mt-1 text-xs text-orange-500">
                    ⚠ IO Wait: {disk.io_wait_pct.toFixed(1)}%
                </div>
            )}
        </div>
    );
};

export const StorageHealthWidget: React.FC = React.memo(() => {
    const liveData = useTelemetryStore((s) => s.liveData);
    const sensors = liveData?.full_sensors as FullSensorsDTO | null | undefined;
    const disks = liveData?.disks;

    // Match NVMe sensors to disk mounts
    const diskNvmeMap = useMemo(() => {
        const map = new Map<string, NVMeSensorDTO>();
        if (!sensors?.nvme_sensors) return map;

        // Simple heuristic: nvme0 -> first NVMe mount, etc.
        const nvmeMounts = disks?.filter(d =>
            d.mount.includes('nvme') || d.mount === '/' || d.mount.includes('ssd')
        ) || [];

        sensors.nvme_sensors.forEach((nvme, i) => {
            if (i < nvmeMounts.length) {
                map.set(nvmeMounts[i].mount, nvme);
            }
        });

        return map;
    }, [sensors?.nvme_sensors, disks]);

    if (!disks || disks.length === 0) {
        return (
            <Card className="h-full">
                <CardHeader className="pb-2">
                    <CardTitle className="flex items-center gap-2 text-sm">
                        <HardDrive className="w-4 h-4 text-blue-500" />
                        Storage Health
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="text-muted-foreground text-sm">
                        No storage devices detected
                    </div>
                </CardContent>
            </Card>
        );
    }

    const totalIops = disks.reduce((sum, d) => sum + d.read_iops + d.write_iops, 0);
    const avgWait = disks.length > 0
        ? disks.reduce((sum, d) => sum + d.avg_wait_ms, 0) / disks.length
        : 0;

    return (
        <Card className="h-full">
            <CardHeader className="pb-2">
                <CardTitle className="flex items-center justify-between text-sm">
                    <div className="flex items-center gap-2">
                        <HardDrive className="w-4 h-4 text-blue-500" />
                        Storage Health
                    </div>
                    <div className="flex items-center gap-3 text-xs text-muted-foreground font-normal">
                        <span>{totalIops.toFixed(0)} IOPS</span>
                        <span>{avgWait.toFixed(1)}ms wait</span>
                    </div>
                </CardTitle>
            </CardHeader>
            <CardContent>
                <div className="space-y-3 max-h-64 overflow-y-auto">
                    {disks.map((disk) => (
                        <StorageItem
                            key={disk.mount}
                            disk={disk}
                            nvme={diskNvmeMap.get(disk.mount)}
                        />
                    ))}
                </div>
            </CardContent>
        </Card>
    );
});

StorageHealthWidget.displayName = 'StorageHealthWidget';
