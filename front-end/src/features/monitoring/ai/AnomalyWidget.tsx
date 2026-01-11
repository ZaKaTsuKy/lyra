import { useTelemetryStore } from "@/store/telemetryStore";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { Brain, Activity } from "lucide-react";

export function AnomalyWidget() {
    const liveData = useTelemetryStore((s) => s.liveData);
    const anomalyValue = liveData?.anomaly.overall ?? 0;
    const regime = liveData?.anomaly.regime ?? 'Unknown';

    return (
        <Card className={`h-full ${anomalyValue > 0.7 ? "border-red-500 bg-red-500/5" : ""}`}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">AI Status</CardTitle>
                <Brain className={`h-4 w-4 ${anomalyValue > 0.7 ? "text-red-500 animate-pulse" : "text-purple-500"}`} />
            </CardHeader>
            <CardContent>
                <div className="flex items-baseline space-x-2">
                    <div className="text-2xl font-bold">{(anomalyValue * 100).toFixed(0)}%</div>
                    <span className="text-xs text-muted-foreground">Anomaly Score</span>
                </div>

                {/* AI Trends */}
                {liveData && (
                    <div className="grid grid-cols-4 gap-1 mt-2 mb-2 text-[10px] text-muted-foreground text-center">
                        <div title="CPU Trend">CPU {liveData.anomaly.cpu_trend === 'up' ? '↑' : liveData.anomaly.cpu_trend === 'down' ? '↓' : '→'}</div>
                        <div title="Mem Trend">MEM {liveData.anomaly.mem_trend === 'up' ? '↑' : liveData.anomaly.mem_trend === 'down' ? '↓' : '→'}</div>
                        <div title="IO Trend">IO {liveData.anomaly.io_trend === 'up' ? '↑' : liveData.anomaly.io_trend === 'down' ? '↓' : '→'}</div>
                        <div title="Net Trend">NET {liveData.anomaly.net_trend === 'up' ? '↑' : liveData.anomaly.net_trend === 'down' ? '↓' : '→'}</div>
                    </div>
                )}

                <div className="mt-2 flex items-center gap-2">
                    <Activity className="w-3 h-3 text-muted-foreground" />
                    <span className="text-xs font-medium uppercase text-muted-foreground">{regime}</span>
                </div>
                <ProgressBar
                    value={anomalyValue * 100}
                    variant={anomalyValue > 0.5 ? "danger" : "success"}
                    className="mt-3"
                    showValue={false}
                />
            </CardContent>
        </Card>
    );
}
