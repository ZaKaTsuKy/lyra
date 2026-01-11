import { formatBytes } from '@/lib/formatters';
import { MetricChart } from './MetricChart';
import type { UpdatePayload } from '@/types/omni';
import { History } from 'lucide-react';
import { useCallback } from 'react';

interface HistoryChartsProps {
    history: UpdatePayload[];
}

export function HistoryCharts({ history }: HistoryChartsProps) {
    if (!history || history.length === 0) return null;

    // Accessors for complex metrics
    const getTotalDiskRead = useCallback((d: UpdatePayload) => d.disks.reduce((acc, disk) => acc + disk.read_bps, 0), []);
    const getTotalDiskWrite = useCallback((d: UpdatePayload) => d.disks.reduce((acc, disk) => acc + disk.write_bps, 0), []);
    const getGpuUtil = useCallback((d: UpdatePayload) => d.gpu ? d.gpu.util : 0, []);
    const getGpuTemp = useCallback((d: UpdatePayload) => d.gpu ? d.gpu.temp : 0, []);

    const hasGpu = history.some(h => h.gpu !== null);

    return (
        <section className="space-y-4">
            <h2 className="text-xl font-semibold flex items-center gap-2">
                <History className="w-5 h-5 text-muted-foreground" />
                Detailed History
            </h2>

            <div className={`grid gap-4 ${hasGpu ? 'md:grid-cols-2 lg:grid-cols-4' : 'md:grid-cols-2 lg:grid-cols-3'}`}>
                {/* Disk I/O Read */}
                <div className="h-[200px]">
                    <MetricChart
                        title="Total Disk Read"
                        data={history}
                        accessor={getTotalDiskRead}
                        color="#10b981"
                        formatter={(val) => `${formatBytes(val)}/s`}
                    />
                </div>

                {/* Disk I/O Write */}
                <div className="h-[200px]">
                    <MetricChart
                        title="Total Disk Write"
                        data={history}
                        accessor={getTotalDiskWrite}
                        color="#f43f5e"
                        formatter={(val) => `${formatBytes(val)}/s`}
                    />
                </div>

                {/* GPU Charts (if present) */}
                {hasGpu && (
                    <>
                        <div className="h-[200px]">
                            <MetricChart
                                title="GPU Utilization"
                                data={history}
                                accessor={getGpuUtil}
                                color="#8b5cf6"
                                unit="%"
                                range={[0, 100]}
                            />
                        </div>
                        <div className="h-[200px]">
                            <MetricChart
                                title="GPU Temperature"
                                data={history}
                                accessor={getGpuTemp}
                                color="#ef4444"
                                unit="°C"
                            />
                        </div>
                    </>
                )}
            </div>
        </section>
    );
}
