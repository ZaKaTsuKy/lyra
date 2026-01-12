import { useEffect, useMemo, useRef } from 'react';
import { useTelemetryStore } from './store/telemetryStore';
import { usePreferencesStore } from './store/preferencesStore';
import {
  TrendingUp,
  AlertTriangle,
} from 'lucide-react';
import { Skeleton } from '@/shared/components/ui/skeleton';
import { formatBytes } from '@/lib/formatters';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/shared/components/ui/card';
import { Badge } from '@/shared/components/ui/badge';
import { ProgressBar } from '@/shared/components/ui/progress-bar';

// Dashboard Components
import { GpuCard } from './components/dashboard/GpuCard';
import { BatteryCard } from './components/dashboard/BatteryCard';
import { ProcessList } from './components/dashboard/ProcessList';
import { SystemMetrics } from './components/dashboard/SystemMetrics';

// DnD Grid
import { DashboardGrid } from './features/dashboard/components/DashboardGrid';
import { ThemeToggle } from './shared/components/ThemeToggle';

// ============================================
// Auto-Refresh Hook (Long-Term Resilience)
// ============================================
const REFRESH_HOUR = parseInt(import.meta.env.VITE_REFRESH_HOUR || '4', 10);
const IDLE_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes

function useAutoRefresh() {
  const lastActivityRef = useRef(Date.now());

  useEffect(() => {
    const updateActivity = () => {
      lastActivityRef.current = Date.now();
    };

    const events = ['mousemove', 'keydown', 'click', 'scroll', 'touchstart'];
    events.forEach(e => window.addEventListener(e, updateActivity, { passive: true }));

    const interval = setInterval(() => {
      const now = new Date();
      const isRefreshHour = now.getHours() === REFRESH_HOUR;
      const isIdle = Date.now() - lastActivityRef.current > IDLE_THRESHOLD_MS;

      if (isRefreshHour && isIdle) {
        if (import.meta.env.DEV) console.log('[AutoRefresh] Performing daily maintenance reload at', now.toISOString());
        window.location.reload();
      }
    }, 60_000); // Check every minute

    return () => {
      events.forEach(e => window.removeEventListener(e, updateActivity));
      clearInterval(interval);
    };
  }, []);
}

function App() {
  // Long-term resilience: auto-refresh at configured hour when idle
  useAutoRefresh();

  const status = useTelemetryStore((s) => s.status);
  const connect = useTelemetryStore((s) => s.connect);
  const disconnect = useTelemetryStore((s) => s.disconnect);
  const liveData = useTelemetryStore((s) => s.liveData);
  const staticInfo = useTelemetryStore((s) => s.staticInfo);

  const theme = usePreferencesStore((s) => s.theme);


  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    root.classList.add(theme);
  }, [theme]);





  // Derived Metrics with useMemo
  const metrics = useMemo(() => {
    const coreCount = staticInfo?.static.core_count ?? 1;
    const cpuLoadVal = liveData ? (liveData.cpu.load1 / coreCount) * 100 : 0;

    // Predictions
    const predictions = liveData?.anomaly.predictions ?? [];
    const criticalPrediction = predictions.find(p => p.confidence > 0.8 && p.time_to_critical_sec < 300);

    return {
      coreCount,
      cpuLoadVal,
      cpuLoad: cpuLoadVal.toFixed(2),
      cpuTemp: liveData?.cpu.temp_package.toFixed(1) ?? '0.0',
      ramUsagePercent: liveData ? (liveData.memory.used_kb / liveData.memory.total_kb) * 100 : 0,
      anomalyValue: liveData?.anomaly.overall ?? 0,
      regime: liveData?.anomaly.regime ?? 'Unknown',
      swapUsage: liveData ? (liveData.memory.swap_used_kb / liveData.memory.swap_total_kb) * 100 : 0,
      criticalPrediction
    };
  }, [liveData, staticInfo]);

  return (
    <div className="min-h-screen bg-background text-foreground font-sans p-6 md:p-8 transition-colors duration-300">

      {/* HEADER */}
      <header className="mb-8 flex flex-col md:flex-row items-start md:items-center justify-between gap-4 border-b pb-6">
        <div className="transition-opacity duration-500 ease-in-out">
          <h1 className="text-3xl font-bold tracking-tight bg-gradient-to-r from-primary to-blue-600 bg-clip-text text-transparent">
            Omni Monitor
          </h1>
          <p className="text-muted-foreground mt-1">Real-time system telemetry & AI analysis</p>
        </div>

        <div className="flex items-center gap-4">
          <Badge
            variant={
              status === 'connected' ? 'success' :
                status === 'connecting' ? 'warning' : 'danger'
            }
            className="text-sm px-3 py-1"
          >
            <div className={`w-2 h-2 rounded-full mr-2 ${status === 'connected' ? 'bg-white animate-pulse' : 'bg-white/50'}`} />
            {status.toUpperCase()}
          </Badge>

          <ThemeToggle />
        </div>
      </header>

      {/* AI ALERT BANNER */}
      {metrics.criticalPrediction && (
        <div className="mb-6 p-4 rounded-lg bg-red-500/10 border border-red-500/20 flex items-center gap-4 transition-all duration-300 animate-in fade-in slide-in-from-top-4">
          <AlertTriangle className="w-6 h-6 text-red-500 animate-pulse" />
          <div>
            <h3 className="font-bold text-red-500">Critical Anomaly Predicted</h3>
            <p className="text-sm text-red-500/80">
              High probability event ({metrics.criticalPrediction.metric}) detected in {metrics.criticalPrediction.time_to_critical_sec.toFixed(0)}s.
            </p>
          </div>
        </div>
      )}

      <main className="space-y-6">

        {/* TOP METRICS GRID (Draggable) */}
        <DashboardGrid />



        {/* DETAILED INFO SECTION */}
        <section className="grid gap-6 md:grid-cols-7">

          {/* Static Info & Metrics Panel */}
          <SystemMetrics staticInfo={staticInfo ? staticInfo.static : null} systemData={liveData ? liveData.system : null} />

          {/* Disks, GPU, Battery */}
          <Card className="md:col-span-4 h-full">
            <CardHeader>
              <CardTitle>Hardware Details</CardTitle>
              <CardDescription>Storage, GPU, and Power status</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid gap-4 md:grid-cols-2">
                {/* Storage */}
                {liveData?.disks.map((disk) => (
                  <div key={disk.mount} className="p-4 border rounded-lg bg-secondary/10">
                    <div className="flex items-center justify-between mb-2">
                      <span className="font-mono text-sm font-bold">{disk.mount}</span>
                      <Badge variant="outline" className="text-xs">{disk.io_wait_pct?.toFixed(1) ?? 0}% Wait</Badge>
                    </div>
                    <ProgressBar value={disk.percent} variant="default" label="Usage" />
                    <div className="flex justify-between text-xs text-muted-foreground mt-2">
                      <span title="Read">R: {formatBytes(disk.read_bps)}/s</span>
                      <span title="Write">W: {formatBytes(disk.write_bps)}/s</span>
                    </div>
                    <div className="flex justify-between text-xs text-muted-foreground mt-1 text-[10px]">
                      <span title="IOPS Read">R-IOPS: {disk.read_iops}</span>
                      <span title="IOPS Write">W-IOPS: {disk.write_iops}</span>
                    </div>
                  </div>
                ))}

                {/* GPU (Conditional) */}
                {liveData?.gpu && <GpuCard data={liveData.gpu} />}

                {/* Battery (Conditional) */}
                {liveData?.battery && <BatteryCard data={liveData.battery} />}

                {/* Simulations if data missing */}
                {!liveData && <Skeleton className="h-32 w-full col-span-2" />}
              </div>
            </CardContent>
          </Card>

          {/* Full Width Processes List */}
          {liveData && <ProcessList processes={liveData.top_processes} />}

        </section>

        {/* AI PREDICTIONS ROW */}
        {
          liveData?.anomaly.predictions && liveData.anomaly.predictions.length > 0 && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <TrendingUp className="w-5 h-5 text-purple-500" />
                  AI Predictions
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-4">
                  {liveData.anomaly.predictions.map((pred, i) => (
                    <div key={i} className="p-3 border rounded-md min-w-[200px] flex flex-col gap-1">
                      <div className="text-sm font-bold capitalize">{pred.metric}</div>
                      <div className="text-xs text-muted-foreground">Confidence: {(pred.confidence * 100).toFixed(0)}%</div>
                      <div className="text-xs font-mono">In {pred.time_to_critical_sec.toFixed(0)}s</div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          )
        }

      </main >
    </div >
  );
}

export default App;