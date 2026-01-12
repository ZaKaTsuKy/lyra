import React from 'react';
import { useTelemetryStore } from '../../../store/telemetryStore';
import { Card, CardContent, CardHeader, CardTitle } from '@/shared/components/ui/card';
import { Badge } from '@/shared/components/ui/badge';
import { ProgressBar } from '@/shared/components/ui/progress-bar';
import {
    AlertTriangle,
    Thermometer,
    Fan,
    Zap,
    Clock,
    Gauge,
    Activity,
    TrendingUp,
    TrendingDown,
    Minus
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { PhysicsDiagnosticsDTO } from '../../../types/omni';

/**
 * Physics-Aware Diagnostics Widget
 * Displays thermal efficiency, bottleneck detection, and hardware health insights
 * 
 * FIXED: Now uses useTelemetryStore instead of expecting props
 */
export const PhysicsDiagnosticsWidget: React.FC = React.memo(() => {
    const liveData = useTelemetryStore((state) => state.liveData);
    const physics = liveData?.physics_diagnostics as PhysicsDiagnosticsDTO | null | undefined;

    if (!physics) {
        return (
            <Card className="h-full bg-white/5 backdrop-blur-md border-white/10">
                <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium flex items-center gap-2">
                        <Activity className="w-4 h-4 text-cyan-400" />
                        Physics Diagnostics
                    </CardTitle>
                </CardHeader>
                <CardContent className="flex items-center justify-center h-32 text-muted-foreground text-xs">
                    Waiting for physics engine data...
                </CardContent>
            </Card>
        );
    }

    const formatTTC = (seconds: number): string => {
        if (!isFinite(seconds) || seconds > 86400) return '∞';
        if (seconds < 60) return `${Math.round(seconds)}s`;
        if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
        return `${(seconds / 3600).toFixed(1)}h`;
    };

    const getEfficiencyVariant = (pct: number): 'success' | 'warning' | 'danger' | 'default' => {
        if (pct >= 90) return 'success';
        if (pct >= 75) return 'warning';
        return 'danger';
    };

    const getWorkloadColor = (state: string): string => {
        switch (state.toUpperCase()) {
            case 'IDLE': return 'text-gray-400';
            case 'COMPUTE': return 'text-blue-400';
            case 'GAMING': return 'text-purple-400';
            case 'IO_INTENSIVE': return 'text-orange-400';
            case 'MIXED': return 'text-cyan-400';
            default: return 'text-gray-400';
        }
    };

    const getBottleneckColor = (bottleneck: string): string => {
        if (bottleneck === 'None') return 'text-green-400';
        if (bottleneck === 'CPU' || bottleneck === 'GPU') return 'text-red-400';
        return 'text-yellow-400';
    };

    const getTempDerivativeIcon = () => {
        if (physics.temp_derivative > 0.5) return <TrendingUp className="w-3 h-3 text-red-400" />;
        if (physics.temp_derivative < -0.5) return <TrendingDown className="w-3 h-3 text-green-400" />;
        return <Minus className="w-3 h-3 text-gray-400" />;
    };

    return (
        <Card className="h-full bg-white/5 backdrop-blur-md border-white/10 overflow-hidden">
            <CardHeader className="pb-2">
                <CardTitle className="text-sm font-medium flex items-center justify-between">
                    <div className="flex items-center gap-2">
                        <Activity className="w-4 h-4 text-cyan-400" />
                        Physics Diagnostics
                    </div>
                    <Badge
                        variant="outline"
                        className={cn(
                            "text-[10px] font-mono",
                            getWorkloadColor(physics.workload_state)
                        )}
                    >
                        {physics.workload_state}
                    </Badge>
                </CardTitle>
            </CardHeader>

            <CardContent className="space-y-4">
                {/* Thermal Efficiency */}
                <div className="space-y-1">
                    <div className="flex items-center justify-between text-xs">
                        <span className="flex items-center gap-1 text-muted-foreground">
                            <Thermometer className="w-3 h-3" />
                            Thermal Efficiency
                        </span>
                        <span className={cn(
                            "font-mono",
                            physics.thermal_efficiency_pct >= 90 ? "text-green-400" :
                                physics.thermal_efficiency_pct >= 75 ? "text-yellow-400" : "text-red-400"
                        )}>
                            {physics.thermal_efficiency_pct.toFixed(0)}%
                        </span>
                    </div>
                    <ProgressBar
                        value={Math.min(100, Math.max(0, physics.thermal_efficiency_pct))}
                        variant={getEfficiencyVariant(physics.thermal_efficiency_pct)}
                    />
                    {physics.thermal_degradation && (
                        <div className="flex items-center gap-1 text-[10px] text-orange-400 mt-1">
                            <AlertTriangle className="w-3 h-3" />
                            Cooling degradation detected
                        </div>
                    )}
                </div>

                {/* Time to Throttle */}
                <div className="flex items-center justify-between">
                    <span className="flex items-center gap-1 text-xs text-muted-foreground">
                        <Clock className="w-3 h-3" />
                        Time to Throttle
                    </span>
                    <div className="flex items-center gap-2">
                        {getTempDerivativeIcon()}
                        <span className={cn(
                            "font-mono text-sm",
                            physics.throttle_imminent ? "text-red-400 animate-pulse" : "text-green-400"
                        )}>
                            {formatTTC(physics.time_to_throttle_sec)}
                        </span>
                        {physics.is_transient_spike && (
                            <span className="text-[10px] text-blue-400">(transient)</span>
                        )}
                    </div>
                </div>

                {/* Dynamic Thresholds */}
                <div className="flex items-center gap-4 text-[10px] text-muted-foreground">
                    <span>Warn: {physics.temp_warning}°C</span>
                    <span>Crit: {physics.temp_critical}°C</span>
                </div>

                {/* Fan Hunting Alert */}
                {physics.fan_hunting && (
                    <div className="bg-yellow-500/20 border border-yellow-500/30 rounded-md p-2 flex items-center gap-2">
                        <Fan className="w-4 h-4 text-yellow-400 animate-spin" style={{ animationDuration: '2s' }} />
                        <div className="text-xs">
                            <span className="text-yellow-300 font-medium">Fan hunting detected</span>
                            <span className="text-yellow-200/70 ml-2">
                                (σ²: {physics.rpm_variance.toFixed(0)} RPM²)
                            </span>
                        </div>
                    </div>
                )}

                {/* Power Quality Alerts */}
                {(physics.vcore_unstable || physics.rail_12v_unstable) && (
                    <div className="bg-orange-500/20 border border-orange-500/30 rounded-md p-2 space-y-1">
                        <div className="flex items-center gap-2">
                            <Zap className="w-4 h-4 text-orange-400" />
                            <span className="text-xs text-orange-300 font-medium">Power Quality Issues</span>
                        </div>
                        {physics.vcore_unstable && (
                            <div className="text-[10px] text-orange-200/80 pl-6">
                                Vcore unstable (±{physics.vcore_variance_mv.toFixed(1)}mV)
                            </div>
                        )}
                        {physics.rail_12v_unstable && (
                            <div className="text-[10px] text-orange-200/80 pl-6">
                                12V rail unstable
                            </div>
                        )}
                    </div>
                )}

                {/* Bottleneck Detection */}
                <div className="flex items-center justify-between">
                    <span className="flex items-center gap-1 text-xs text-muted-foreground">
                        <Gauge className="w-3 h-3" />
                        Bottleneck
                    </span>
                    <div className="flex items-center gap-2">
                        <span className={cn("font-medium text-sm", getBottleneckColor(physics.bottleneck))}>
                            {physics.bottleneck === 'None' ? 'No bottleneck' : physics.bottleneck}
                        </span>
                        {physics.bottleneck_severity > 0 && (
                            <span className="text-[10px] text-muted-foreground">
                                ({(physics.bottleneck_severity * 100).toFixed(0)}%)
                            </span>
                        )}
                    </div>
                </div>

                {/* Diagnostics Log */}
                {physics.diagnostics.length > 0 && (
                    <div className="border-t border-white/10 pt-3 mt-3">
                        <div className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">
                            Diagnostics
                        </div>
                        <ul className="space-y-1">
                            {physics.diagnostics.map((msg, i) => (
                                <li key={i} className="text-xs text-muted-foreground flex items-start gap-2">
                                    <span className="text-cyan-400">•</span>
                                    {msg}
                                </li>
                            ))}
                        </ul>
                    </div>
                )}

                {/* Thermal Resistance Debug (optional, can be hidden) */}
                {physics.rth_baseline > 0 && (
                    <div className="text-[10px] text-muted-foreground/50 font-mono">
                        Rth: {physics.rth_instant.toFixed(4)} (baseline: {physics.rth_baseline.toFixed(4)})
                    </div>
                )}
            </CardContent>
        </Card>
    );
});

PhysicsDiagnosticsWidget.displayName = 'PhysicsDiagnosticsWidget';

export default PhysicsDiagnosticsWidget;