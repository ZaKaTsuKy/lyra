import { ResponsiveContainer, AreaChart, Area, XAxis, Tooltip, YAxis } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import type { HistoryPoint } from '@/store/telemetryStore';
import { memo, useId, useMemo } from 'react';

interface MetricChartProps {
    title: string;
    data: HistoryPoint[];
    dataKey: keyof HistoryPoint;
    color?: string;
    unit?: string;
    range?: [number | 'auto' | 'dataMin' | 'dataMax', number | 'auto' | 'dataMin' | 'dataMax'];
    formatter?: (val: number) => string;
}

// Comparaison optimisée pour memo
function arePropsEqual(prev: MetricChartProps, next: MetricChartProps): boolean {
    // Si les deux sont vides, pas de re-render
    if (prev.data.length === 0 && next.data.length === 0) return true;

    // Si la longueur change, re-render
    if (prev.data.length !== next.data.length) return false;

    // Comparer uniquement le dernier timestamp (le plus récent)
    const prevLast = prev.data[prev.data.length - 1];
    const nextLast = next.data[next.data.length - 1];

    // Comparer les props statiques et le dernier point
    return (
        prevLast?.timestamp === nextLast?.timestamp &&
        prev.title === next.title &&
        prev.color === next.color &&
        prev.dataKey === next.dataKey
    );
}

export const MetricChart = memo(function MetricChart({
    title,
    data,
    dataKey,
    color = "#3b82f6",
    unit = "",
    range = [0, 'auto'],
    formatter = (val: number) => val.toFixed(1),
}: MetricChartProps) {
    const gradientId = useId();

    // Mémoïser la transformation des données
    const chartData = useMemo(() => {
        return data.map(d => ({
            timestamp: d.timestamp,
            value: d[dataKey] as number ?? 0
        }));
    }, [data, dataKey]);

    // État de chargement
    if (chartData.length === 0) {
        return (
            <Card className="h-full">
                <CardHeader className="p-4 pb-0">
                    <CardTitle className="text-sm font-medium text-muted-foreground">
                        {title}
                    </CardTitle>
                </CardHeader>
                <CardContent className="p-4 h-[150px] flex items-center justify-center text-muted-foreground text-sm">
                    Waiting for data...
                </CardContent>
            </Card>
        );
    }

    return (
        <Card className="h-full">
            <CardHeader className="p-4 pb-0">
                <CardTitle className="text-sm font-medium text-muted-foreground">
                    {title}
                </CardTitle>
            </CardHeader>
            <CardContent className="p-0 h-[150px]">
                <ResponsiveContainer width="100%" height="100%" minHeight={100}>
                    <AreaChart data={chartData}>
                        <defs>
                            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                                <stop offset="5%" stopColor={color} stopOpacity={0.3} />
                                <stop offset="95%" stopColor={color} stopOpacity={0} />
                            </linearGradient>
                        </defs>
                        <XAxis dataKey="timestamp" hide />
                        <YAxis hide domain={range} />
                        <Tooltip
                            contentStyle={{
                                backgroundColor: "hsl(var(--background))",
                                borderColor: "hsl(var(--border))",
                                borderRadius: "8px"
                            }}
                            labelFormatter={() => ''}
                            formatter={(val: number | string | Array<number | string> | undefined) => [
                                `${formatter(Number(val ?? 0))}${unit}`,
                                title
                            ]}
                        />
                        <Area
                            type="monotone"
                            dataKey="value"
                            stroke={color}
                            fillOpacity={1}
                            fill={`url(#${gradientId})`}
                            strokeWidth={2}
                            isAnimationActive={false}
                        />
                    </AreaChart>
                </ResponsiveContainer>
            </CardContent>
        </Card>
    );
}, arePropsEqual);