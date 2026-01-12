import { memo } from 'react';
import { useTelemetryStore } from '@/store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Badge } from '@/shared/components/ui/badge';
import { Brain, Waves, Activity, AlertCircle } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { CognitiveInsightsDTO } from '@/types/omni';

// Extracted outside component to avoid recreation on every render
const STATE_COLORS: Record<string, string> = {
    'Idle': 'text-gray-400',
    'Light Load': 'text-green-400',
    'Compute': 'text-blue-400',
    'Network Active': 'text-cyan-400',
    'I/O Bound': 'text-orange-400',
    'Thermal Throttling': 'text-red-500 animate-pulse',
    'Fan Spin-up': 'text-yellow-400',
    'Fan Spin-down': 'text-yellow-400',
    'Overload': 'text-red-600',
    'Unknown': 'text-gray-500'
};

export const CognitiveWidget = memo(function CognitiveWidget() {
    const data = useTelemetryStore((state) => state.liveData);

    if (!data?.cognitive) {
        return (
            <Card className="h-full bg-white/5 backdrop-blur-md border-white/10">
                <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium flex items-center gap-2">
                        <Brain className="w-4 h-4 text-muted-foreground" />
                        Cognitive Engine
                    </CardTitle>
                </CardHeader>
                <CardContent className="flex items-center justify-center h-32 text-muted-foreground text-xs">
                    Initializing AI engine...
                </CardContent>
            </Card>
        );
    }
    const ai: CognitiveInsightsDTO = data.cognitive;

    const currentStateColor = STATE_COLORS[ai.behavioral_state] || 'text-white';

    return (
        <Card className="h-full bg-white/5 backdrop-blur-md border-white/10 overflow-hidden relative">
            <div className="absolute top-0 right-0 p-3 opacity-10">
                <Brain className="w-16 h-16" />
            </div>

            <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center gap-2">
                    <Brain className="w-4 h-4 text-purple-400" />
                    Cognitive Engine
                    {ai.iforest_score > 0.8 && (
                        <Badge variant="destructive" className="ml-auto animate-pulse">
                            ANOMALY ({ai.iforest_score.toFixed(2)})
                        </Badge>
                    )}
                </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">

                {/* Behavioral State */}
                <div className="flex flex-col">
                    <span className="text-xs text-muted-foreground uppercase tracking-widest">Current State</span>
                    <span className={cn("text-2xl font-black mt-1 tracking-tight transition-colors duration-500", currentStateColor)}>
                        {ai.behavioral_state.toUpperCase()}
                    </span>
                    <div className="w-full bg-white/10 h-1 mt-2 rounded-full overflow-hidden">
                        <div
                            className={cn("h-full transition-all duration-1000",
                                ai.state_stability > 0.8 ? "bg-green-500" : "bg-yellow-500"
                            )}
                            style={{ width: `${ai.state_stability * 100}%` }}
                        />
                    </div>
                    <span className="text-[10px] text-right text-muted-foreground mt-1">
                        Stability: {(ai.state_stability * 100).toFixed(0)}%
                    </span>
                </div>

                {/* Oscillations Alert */}
                {ai.oscillation_detected && (
                    <div className="bg-purple-500/20 border border-purple-500/30 rounded-md p-3 flex items-start gap-3">
                        <Waves className="w-4 h-4 text-purple-300 mt-0.5 animate-bounce" />
                        <div>
                            <h4 className="text-sm font-bold text-purple-300">Oscillation Detected</h4>
                            <p className="text-xs text-purple-200/80 mt-1">
                                {ai.oscillation_type} pattern identified.
                            </p>
                            <div className="flex gap-4 mt-2 text-[10px] text-purple-300/60 font-mono">
                                <span>Entropy(CPU): {ai.spectral_entropy_cpu.toFixed(2)}</span>
                                <span>Entropy(Fan): {ai.spectral_entropy_fan.toFixed(2)}</span>
                            </div>
                        </div>
                    </div>
                )}

                {/* Behavioral Anomaly */}
                {ai.behavioral_anomaly && (
                    <div className="bg-orange-500/20 border border-orange-500/30 rounded-md p-3 flex items-center gap-2">
                        <AlertCircle className="w-4 h-4 text-orange-400" />
                        <span className="text-xs text-orange-200">{ai.behavioral_description}</span>
                    </div>
                )}

                {/* iForest Score (if no major anomaly but elevated) */}
                {!ai.oscillation_detected && ai.iforest_score > 0.5 && (
                    <div className="flex items-center gap-2 text-xs text-yellow-400">
                        <Activity className="w-3 h-3" />
                        <span>Elevated Anomaly Score: {ai.iforest_score.toFixed(2)}</span>
                    </div>
                )}

            </CardContent>
        </Card>
    );
});
