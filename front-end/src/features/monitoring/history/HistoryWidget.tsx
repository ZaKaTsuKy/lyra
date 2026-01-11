import { memo, useMemo } from 'react';
import { formatBytes } from '@/lib/formatters';
import { MetricChart } from '@/components/charts/MetricChart';
import { History } from 'lucide-react';
import { useTelemetryStore, selectors } from "@/store/telemetryStore";

export const HistoryWidget = memo(function HistoryWidget() {
    // Utiliser le sélecteur direct (pas de fonction qui crée un nouveau tableau)
    const history = useTelemetryStore(selectors.history);

    // Optimized: Check only first point instead of iterating all 180 entries
    const hasGpu = useMemo(() => {
        return history.length > 0 && history[0].gpu_util !== null;
    }, [history.length > 0 ? history[0]?.gpu_util : null]);

    // Early return APRÈS tous les hooks
    if (history.length === 0) return null;

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
                    dataKey="cpu_load1"
                    color="#3b82f6"
                    unit="%"
                    range={[0, 100]}
                />
                <MetricChart
                    title="Memory Usage"
                    data={history}
                    dataKey="memory_used_kb"
                    color="#a855f7"
                    formatter={(val) => formatBytes(val * 1024)}
                />
                <MetricChart
                    title="Network Rx"
                    data={history}
                    dataKey="network_rx_bps"
                    color="#f59e0b"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />
                <MetricChart
                    title="Total Disk Read"
                    data={history}
                    dataKey="disk_read_bps"
                    color="#10b981"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />
                <MetricChart
                    title="Total Disk Write"
                    data={history}
                    dataKey="disk_write_bps"
                    color="#f43f5e"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />

                {hasGpu && (
                    <>
                        <MetricChart
                            title="GPU Utilization"
                            data={history}
                            dataKey="gpu_util"
                            color="#8b5cf6"
                            unit="%"
                            range={[0, 100]}
                        />
                        <MetricChart
                            title="GPU Temperature"
                            data={history}
                            dataKey="gpu_temp"
                            color="#ef4444"
                            unit="°C"
                        />
                    </>
                )}
            </div>
        </div>
    );
});