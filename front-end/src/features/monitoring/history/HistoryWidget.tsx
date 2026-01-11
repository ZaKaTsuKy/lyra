import { formatBytes } from '@/lib/formatters';
import { MetricChart } from '@/components/charts/MetricChart';
import type { UpdatePayload } from '@/types/omni';
import { History } from 'lucide-react';
import { useCallback } from 'react';
import { useTelemetryStore } from "@/store/telemetryStore";

export function HistoryWidget() {
    const history = useTelemetryStore((s) => s.history);

    // ⚠️ IMPORTANT: All hooks MUST be called before any early return
    // This is a React rule: hooks must be called in the same order every render
    const getTotalDiskRead = useCallback((d: UpdatePayload) => d.disks.reduce((acc, disk) => acc + disk.read_bps, 0), []);
    const getTotalDiskWrite = useCallback((d: UpdatePayload) => d.disks.reduce((acc, disk) => acc + disk.write_bps, 0), []);
    const getGpuUtil = useCallback((d: UpdatePayload) => d.gpu ? d.gpu.util : 0, []);
    const getGpuTemp = useCallback((d: UpdatePayload) => d.gpu ? d.gpu.temp : 0, []);

    // Early return AFTER all hooks
    if (!history || history.length === 0) return null;

    const hasGpu = history.some(h => h.gpu !== null);

    return (
        <div className="space-y-6">
            <h2 className="text-xl font-semibold flex items-center gap-2">
                <History className="w-5 h-5 text-muted-foreground" />
                Detailed History (Last 3 Minutes)
            </h2>

            <div className={`grid gap-4 ${hasGpu ? 'md:grid-cols-2 lg:grid-cols-4' : 'md:grid-cols-2 lg:grid-cols-3'}`}>
                <MetricChart
                    title="CPU Load"
                    data={history}
                    dataKey="cpu.load1"
                    color="#3b82f6"
                    unit="%"
                    range={[0, 100]}
                />
                <MetricChart
                    title="Memory Usage"
                    data={history}
                    dataKey="memory.used_kb"
                    color="#a855f7"
                    formatter={(val) => formatBytes(val * 1024)}
                />
                <MetricChart
                    title="Network Rx"
                    data={history}
                    dataKey="network.rx_bps"
                    color="#f59e0b"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />
                <MetricChart
                    title="Total Disk Read"
                    data={history}
                    accessor={getTotalDiskRead}
                    color="#10b981"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />
                <MetricChart
                    title="Total Disk Write"
                    data={history}
                    accessor={getTotalDiskWrite}
                    color="#f43f5e"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />

                {hasGpu && (
                    <>
                        <MetricChart
                            title="GPU Utilization"
                            data={history}
                            accessor={getGpuUtil}
                            color="#8b5cf6"
                            unit="%"
                            range={[0, 100]}
                        />
                        <MetricChart
                            title="GPU Temperature"
                            data={history}
                            accessor={getGpuTemp}
                            color="#ef4444"
                            unit="°C"
                        />
                    </>
                )}
            </div>
        </div>
    );
}