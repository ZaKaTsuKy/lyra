import { ResponsiveContainer, AreaChart, Area, XAxis, Tooltip, YAxis } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import type { HistoryPoint } from '@/store/telemetryStore';
import { memo, useId, useMemo, useRef } from 'react';

interface MetricChartProps {
    title: string;
    data: HistoryPoint[];
    dataKey: keyof HistoryPoint;
    color?: string;
    unit?: string;
    range?: [number | 'auto' | 'dataMin' | 'dataMax', number | 'auto' | 'dataMin' | 'dataMax'];
    formatter?: (val: number) => string;
    limit?: number;
}

// ============================================
// Optimized comparison function
// ============================================
function arePropsEqual(prev: MetricChartProps, next: MetricChartProps): boolean {
    // Quick length check first
    if (prev.data.length !== next.data.length) return false;
    if (prev.data.length === 0 && next.data.length === 0) return true;

    // Static props
    if (prev.title !== next.title) return false;
    if (prev.color !== next.color) return false;
    if (prev.dataKey !== next.dataKey) return false;
    if (prev.limit !== next.limit) return false;

    // Compare only the VALUES of first and last points, NOT timestamps
    // This prevents unnecessary re-renders when only time changes but data is same
    const prevFirst = prev.data[0];
    const nextFirst = next.data[0];
    const prevLast = prev.data[prev.data.length - 1];
    const nextLast = next.data[next.data.length - 1];

    const dataKey = prev.dataKey as keyof HistoryPoint;

    return (
        prevFirst[dataKey] === nextFirst[dataKey] &&
        prevLast[dataKey] === nextLast[dataKey]
    );
}

// ============================================
// Pre-computed chart config outside component
// ============================================
const TOOLTIP_STYLE = {
    backgroundColor: "hsl(var(--background))",
    borderColor: "hsl(var(--border))",
    borderRadius: "8px"
};

export const MetricChart = memo(function MetricChart({
    title,
    data,
    dataKey,
    color = "#3b82f6",
    unit = "",
    range = [0, 'auto'],
    formatter = (val: number) => val.toFixed(1),
    limit = 30,
}: MetricChartProps) {
    const gradientId = useId();

    // Cache for transformed data to avoid recreation if inputs haven't changed
    const cacheRef = useRef<{
        data: HistoryPoint[];
        dataKey: keyof HistoryPoint;
        limit: number;
        result: { timestamp: number; value: number }[];
    } | null>(null);

    // Optimized data transformation with caching
    const chartData = useMemo(() => {
        // Check cache
        if (
            cacheRef.current &&
            cacheRef.current.data === data &&
            cacheRef.current.dataKey === dataKey &&
            cacheRef.current.limit === limit
        ) {
            return cacheRef.current.result;
        }

        const count = data.length;
        if (count === 0) return [];

        const startIndex = limit > 0 && count > limit ? count - limit : 0;
        const resultSize = Math.min(count, limit > 0 ? limit : count);
        const result = new Array<{ timestamp: number; value: number }>(resultSize);

        for (let i = 0; i < resultSize; i++) {
            const d = data[startIndex + i];
            result[i] = {
                timestamp: d.timestamp,
                value: (d[dataKey] as number) ?? 0
            };
        }

        // Update cache
        cacheRef.current = { data, dataKey, limit, result };
        return result;
    }, [data, dataKey, limit]);

    // Memoize label formatter to avoid recreation
    const labelFormatter = useMemo(() => () => '', []);

    // Memoize tooltip formatter
    const tooltipFormatter = useMemo(() => {
        return (val: number | string | Array<number | string> | undefined) => [
            `${formatter(Number(val ?? 0))}${unit}`,
            title
        ];
    }, [formatter, unit, title]);

    // Loading state
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
                            contentStyle={TOOLTIP_STYLE}
                            labelFormatter={labelFormatter}
                            formatter={tooltipFormatter}
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