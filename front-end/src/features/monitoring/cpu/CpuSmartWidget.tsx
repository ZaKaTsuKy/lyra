import { useMemo } from 'react';
import { AreaChart, Area, XAxis, YAxis, ResponsiveContainer, Tooltip } from 'recharts';
import SmartWidget from '@/features/dashboard/SmartWidget';
import { useTelemetryStore, selectors, useThrottledHistory } from '@/store/telemetryStore';

export default function CpuSmartWidget() {
    const load = useTelemetryStore(selectors.cpuLoad);
    const temp = useTelemetryStore(selectors.cpuTemp);
    const history = useThrottledHistory(1000); // 1s throttle

    // Memoize chart data to strictly follow "Optimization"
    const chartData = useMemo(() => {
        return history.map((h: any) => ({
            time: h.timestamp,
            load: h.cpu_load1,
            temp: h.cpu_temp
        }));
    }, [history]);

    const getStatusColor = (load: number) => {
        if (load > 90) return 'text-lyra-amber shadow-glow-amber';
        if (load > 70) return 'text-lyra-violet shadow-glow-violet';
        return 'text-lyra-cyan shadow-glow-cyan';
    };

    return (
        <SmartWidget title="CPU CORES" glow={load > 80}>
            {(size) => (
                <div className="h-full w-full flex flex-col justify-center">

                    {/* SMALL (1x1): Minimal KPI */}
                    {size === 'small' && (
                        <div className="flex flex-col items-center justify-center space-y-2">
                            <span className={`text-4xl font-mono font-bold ${getStatusColor(load)}`}>
                                {load.toFixed(0)}%
                            </span>
                            <div className="text-xs text-lyra-text-dim">
                                {temp.toFixed(1)}°C
                            </div>
                        </div>
                    )}

                    {/* MEDIUM (2x1): KPI + Sparkline */}
                    {size === 'medium' && (
                        <div className="flex items-center justify-between h-full gap-4">
                            <div className="flex flex-col">
                                <span className={`text-5xl font-mono font-bold tracking-tighter ${getStatusColor(load)}`}>
                                    {load.toFixed(0)}%
                                </span>
                                <span className="text-sm font-technical text-lyra-text-secondary mt-1">
                                    {temp.toFixed(1)}°C / 4.2GHz
                                </span>
                            </div>
                            <div className="flex-1 h-full w-full max-h-[80px]">
                                <ResponsiveContainer width="100%" height="100%">
                                    <AreaChart data={chartData}>
                                        <defs>
                                            <linearGradient id="colorLoad" x1="0" y1="0" x2="0" y2="1">
                                                <stop offset="5%" stopColor="#00f0ff" stopOpacity={0.3} />
                                                <stop offset="95%" stopColor="#00f0ff" stopOpacity={0} />
                                            </linearGradient>
                                        </defs>
                                        <Area
                                            type="monotone"
                                            dataKey="load"
                                            stroke="#00f0ff"
                                            fillOpacity={1}
                                            fill="url(#colorLoad)"
                                            strokeWidth={2}
                                        />
                                    </AreaChart>
                                </ResponsiveContainer>
                            </div>
                        </div>
                    )}

                    {/* LARGE (2x2): Full Detail */}
                    {(size === 'large' || size === 'xlarge') && (
                        <div className="h-full flex flex-col gap-4">
                            <div className="flex items-end justify-between border-b border-white/5 pb-2">
                                <div className="flex items-baseline gap-4">
                                    <span className={`text-6xl font-mono font-bold tracking-tighter ${getStatusColor(load)}`}>
                                        {load.toFixed(1)}%
                                    </span>
                                    <div className="flex flex-col text-sm font-technical text-lyra-text-secondary">
                                        <span>TEMP: <b className="text-white">{temp.toFixed(1)}°C</b></span>
                                        <span>FREQ: <b className="text-white">4.2 GHz</b></span>
                                    </div>
                                </div>
                                <div className="text-xs text-lyra-text-dim font-mono">
                                    Ryzen 9 5950X [16C/32T]
                                </div>
                            </div>

                            <div className="flex-1 min-h-0">
                                <ResponsiveContainer width="100%" height="100%">
                                    <AreaChart data={chartData}>
                                        <defs>
                                            <linearGradient id="colorLoadLarge" x1="0" y1="0" x2="0" y2="1">
                                                <stop offset="5%" stopColor="#00f0ff" stopOpacity={0.4} />
                                                <stop offset="95%" stopColor="#00f0ff" stopOpacity={0} />
                                            </linearGradient>
                                            <linearGradient id="colorTemp" x1="0" y1="0" x2="0" y2="1">
                                                <stop offset="5%" stopColor="#bd00ff" stopOpacity={0.4} />
                                                <stop offset="95%" stopColor="#bd00ff" stopOpacity={0} />
                                            </linearGradient>
                                        </defs>
                                        <XAxis hide />
                                        <YAxis hide domain={[0, 100]} />
                                        <Tooltip
                                            contentStyle={{ backgroundColor: '#05050a', borderColor: '#333' }}
                                            itemStyle={{ color: '#fff', fontSize: '12px' }}
                                            labelStyle={{ display: 'none' }}
                                        />
                                        <Area
                                            type="monotone"
                                            dataKey="load"
                                            stroke="#00f0ff"
                                            fill="url(#colorLoadLarge)"
                                            strokeWidth={2}
                                        />
                                        <Area
                                            type="monotone"
                                            dataKey="temp"
                                            stroke="#bd00ff"
                                            fill="url(#colorTemp)"
                                            strokeWidth={2}
                                            strokeDasharray="4 4"
                                        />
                                    </AreaChart>
                                </ResponsiveContainer>
                            </div>
                        </div>
                    )}
                </div>
            )}
        </SmartWidget>
    );
}
