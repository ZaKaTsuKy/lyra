import { memo } from "react";
import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { Badge } from "@/shared/components/ui/badge";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Brain, Activity, Thermometer, HardDrive, AlertTriangle } from "lucide-react";

/**
 * ✅ ENHANCED ANOMALY WIDGET
 * 
 * Now displays:
 * - Overall anomaly score
 * - Per-metric trends (CPU, MEM, IO, NET)
 * - System regime classification
 * - Coherence alerts (temp_without_load, io_latency_without_activity)
 */

const TREND_ICONS: Record<string, string> = {
    'up': '↑',
    'down': '↓',
    'stable': '→',
};

const TREND_COLORS: Record<string, string> = {
    'up': 'text-red-400',
    'down': 'text-green-400',
    'stable': 'text-gray-400',
};

export const AnomalyWidget = memo(function AnomalyWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);
    const anomalyValue = liveData?.anomaly.overall ?? 0;
    const regime = liveData?.anomaly.regime ?? 'Unknown';

    // Coherence alerts
    const coherenceTempAlert = liveData?.anomaly.coherence_temp_alert ?? false;
    const coherenceIoAlert = liveData?.anomaly.coherence_io_alert ?? false;
    const hasCoherenceAlert = coherenceTempAlert || coherenceIoAlert;

    return (
        <Card className={`h-full ${anomalyValue > 0.7 ? "border-red-500/50 bg-red-500/5" : ""}`}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">AI Status</CardTitle>
                <Brain className={`h-4 w-4 ${anomalyValue > 0.7 ? "text-red-500 animate-pulse" : "text-purple-500"}`} />
            </CardHeader>
            <CardContent className="space-y-3">
                {/* Main Anomaly Score */}
                <div className="flex items-baseline justify-between">
                    <div className="text-2xl font-bold">
                        {(anomalyValue * 100).toFixed(0)}%
                    </div>
                    <span className="text-xs text-muted-foreground">Anomaly Score</span>
                </div>

                <ProgressBar
                    value={anomalyValue * 100}
                    variant={anomalyValue > 0.7 ? "danger" : anomalyValue > 0.5 ? "warning" : "success"}
                    showValue={false}
                />

                {/* AI Trends Grid */}
                {liveData && (
                    <div className="grid grid-cols-4 gap-1.5 text-[10px]">
                        {(['cpu', 'mem', 'io', 'net'] as const).map((metric) => {
                            const trend = liveData.anomaly[`${metric}_trend` as keyof typeof liveData.anomaly] as string;
                            return (
                                <div
                                    key={metric}
                                    className="flex flex-col items-center bg-secondary/30 rounded py-1"
                                    title={`${metric.toUpperCase()} Trend: ${trend}`}
                                >
                                    <span className={`text-base ${TREND_COLORS[trend] || 'text-gray-400'}`}>
                                        {TREND_ICONS[trend] || '→'}
                                    </span>
                                    <span className="text-muted-foreground uppercase">{metric}</span>
                                </div>
                            );
                        })}
                    </div>
                )}

                {/* Regime Badge */}
                <div className="flex items-center gap-2">
                    <Activity className="w-3 h-3 text-muted-foreground" />
                    <Badge variant="outline" className="text-xs uppercase font-medium">
                        {regime}
                    </Badge>
                </div>

                {/* Coherence Alerts */}
                {hasCoherenceAlert && (
                    <div className="space-y-1.5 pt-2 border-t border-border/50">
                        <div className="flex items-center gap-1.5 text-xs text-yellow-500">
                            <AlertTriangle className="w-3 h-3" />
                            <span className="font-medium">Coherence Alerts</span>
                        </div>
                        {coherenceTempAlert && (
                            <div className="flex items-center gap-1.5 text-xs text-yellow-400/80 pl-4">
                                <Thermometer className="w-3 h-3" />
                                <span>High temp without CPU load</span>
                            </div>
                        )}
                        {coherenceIoAlert && (
                            <div className="flex items-center gap-1.5 text-xs text-yellow-400/80 pl-4">
                                <HardDrive className="w-3 h-3" />
                                <span>IO latency without disk activity</span>
                            </div>
                        )}
                    </div>
                )}
            </CardContent>
        </Card>
    );
});
