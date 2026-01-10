import { ResponsiveContainer, AreaChart, Area, XAxis, Tooltip, YAxis } from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import type { UpdatePayload } from '@/types/omni';

interface MetricChartProps {
    title: string;
    data: UpdatePayload[];
    dataKey: string;
    color?: string;
    unit?: string;
    range?: [number | 'auto' | 'dataMin' | 'dataMax', number | 'auto' | 'dataMin' | 'dataMax'];
    formatter?: (val: number) => string;
}

export function MetricChart({
    title,
    data,
    dataKey,
    color = "#3b82f6",
    unit = "",
    range = [0, 'auto'],
    formatter = (val: number) => val.toFixed(1)
}: MetricChartProps) {

    // Helper to extract nested keys (e.g. "cpu.load1")
    const getValue = (obj: any, path: string) => {
        return path.split('.').reduce((acc, part) => acc && acc[part], obj);
    };

    const chartData = data.map(d => ({
        timestamp: d.timestamp,
        value: getValue(d, dataKey)
    }));

    // Don't render if no data (prevents Recharts width/height warning)
    if (chartData.length === 0) {
        return (
            <Card className="h-full">
                <CardHeader className="p-4 pb-0">
                    <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
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
                <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
            </CardHeader>
            <CardContent className="p-0 h-[150px]">
                <ResponsiveContainer width="100%" height="100%" minHeight={100}>
                    <AreaChart data={chartData}>
                        <defs>
                            <linearGradient id={`color-${dataKey}`} x1="0" y1="0" x2="0" y2="1">
                                <stop offset="5%" stopColor={color} stopOpacity={0.3} />
                                <stop offset="95%" stopColor={color} stopOpacity={0} />
                            </linearGradient>
                        </defs>
                        <XAxis
                            dataKey="timestamp"
                            hide
                        />
                        <YAxis
                            hide
                            domain={range}
                        />
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
                            fill={`url(#color-${dataKey})`}
                            strokeWidth={2}
                            isAnimationActive={false}
                        />
                    </AreaChart>
                </ResponsiveContainer>
            </CardContent>
        </Card>
    );
}