import { memo, useMemo, useRef, useState, useEffect } from 'react';
import { formatBytes } from '@/lib/formatters';
import { MetricChart } from '@/components/charts/MetricChart';
import { History } from 'lucide-react';
import { useTelemetryStore, selectors, type HistoryPoint } from "@/store/telemetryStore";

/**
 * ✅ OPTIMIZED HISTORY WIDGET
 * 
 * Key optimizations:
 * 1. Uses historyVersion selector to know when to update
 * 2. Throttles history retrieval to every 5 seconds instead of every second
 * 3. Caches the history array to avoid unnecessary transformations
 */

const HISTORY_THROTTLE_MS = 1000; // Matches main UPDATE_THROTTLE_MS

export const HistoryWidget = memo(function HistoryWidget() {
    // Track version changes
    const historyVersion = useTelemetryStore(selectors.historyVersion);
    const getHistory = useTelemetryStore((s) => s.getHistory);

    // State for throttled history
    const [throttledHistory, setThrottledHistory] = useState<HistoryPoint[]>([]);
    const lastUpdateRef = useRef(0);

    // Throttle history updates
    useEffect(() => {
        const now = Date.now();
        if (now - lastUpdateRef.current >= HISTORY_THROTTLE_MS || throttledHistory.length === 0) {
            lastUpdateRef.current = now;
            setThrottledHistory(getHistory());
        }
    }, [historyVersion, getHistory, throttledHistory.length]);

    // Check GPU availability from first point (memoized properly)
    const hasGpu = useMemo(() => {
        return throttledHistory.length > 0 && throttledHistory[0].gpu_util !== null;
    }, [throttledHistory.length > 0 && throttledHistory[0]?.gpu_util !== null]);

    // Early return after hooks
    if (throttledHistory.length === 0) return null;

    return (
        <div className="space-y-6">
            <h2 className="text-xl font-semibold flex items-center gap-2">
                <History className="w-5 h-5 text-muted-foreground" />
                Detailed History (Last 3 Minutes)
            </h2>

            <div className={`grid gap-4 ${hasGpu ? 'md:grid-cols-2 lg:grid-cols-4' : 'md:grid-cols-2 lg:grid-cols-3'}`}>
                <MetricChart
                    title="CPU Load"
                    data={throttledHistory}
                    dataKey="cpu_load1"
                    color="#3b82f6"
                    unit="%"
                    range={[0, 100]}
                />
                <MetricChart
                    title="Memory Usage"
                    data={throttledHistory}
                    dataKey="memory_used_kb"
                    color="#a855f7"
                    formatter={(val) => formatBytes(val * 1024)}
                />
                <MetricChart
                    title="Network Rx"
                    data={throttledHistory}
                    dataKey="network_rx_bps"
                    color="#f59e0b"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />
                <MetricChart
                    title="Total Disk Read"
                    data={throttledHistory}
                    dataKey="disk_read_bps"
                    color="#10b981"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />
                <MetricChart
                    title="Total Disk Write"
                    data={throttledHistory}
                    dataKey="disk_write_bps"
                    color="#f43f5e"
                    formatter={(val) => `${formatBytes(val)}/s`}
                />

                {hasGpu && (
                    <>
                        <MetricChart
                            title="GPU Utilization"
                            data={throttledHistory}
                            dataKey="gpu_util"
                            color="#8b5cf6"
                            unit="%"
                            range={[0, 100]}
                        />
                        <MetricChart
                            title="GPU Temperature"
                            data={throttledHistory}
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