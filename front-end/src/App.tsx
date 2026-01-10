import { useEffect, useState, useMemo } from 'react';
import { useOmniStore } from './store/useOmniStore';
import {
  Activity,
  Cpu,
  Server,
  Thermometer,
  Brain,
  Moon,
  Sun,
  Wifi,
  History,
  TrendingUp,
  AlertTriangle,
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from './components/ui/card';
import { Badge } from './components/ui/badge';
import { ProgressBar } from './components/ui/progress-bar';
import { Skeleton } from './components/ui/skeleton';
import { formatBytes } from './lib/formatters';

// Dashboard Components
import { GpuCard } from './components/dashboard/GpuCard';
import { BatteryCard } from './components/dashboard/BatteryCard';
import { ProcessList } from './components/dashboard/ProcessList';
import { SystemMetrics } from './components/dashboard/SystemMetrics';

// Charts
import { MetricChart } from './components/charts/MetricChart';
import { CpuHeatmap } from './components/charts/CpuHeatmap';

function App() {
  const status = useOmniStore((s) => s.status);
  const connect = useOmniStore((s) => s.connect);
  const disconnect = useOmniStore((s) => s.disconnect);
  const liveData = useOmniStore((s) => s.liveData);
  const staticInfo = useOmniStore((s) => s.staticInfo);
  const history = useOmniStore((s) => s.history);

  const [theme, setTheme] = useState<'light' | 'dark'>(() => {
    if (typeof window !== 'undefined') {
      return localStorage.getItem('theme') as 'light' | 'dark' || 'light';
    }
    return 'light';
  });

  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  useEffect(() => {
    const root = window.document.documentElement;
    root.classList.remove('light', 'dark');
    root.classList.add(theme);
    localStorage.setItem('theme', theme);
  }, [theme]);

  const toggleTheme = () => {
    setTheme(prev => (prev === 'light' ? 'dark' : 'light'));
  };

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
        <div>
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

          <button
            onClick={toggleTheme}
            className="p-2 rounded-full hover:bg-muted transition-colors border"
            aria-label="Toggle theme"
          >
            {theme === 'light' ? <Moon className="w-5 h-5" /> : <Sun className="w-5 h-5" />}
          </button>
        </div>
      </header>

      {/* AI ALERT BANNER */}
      {metrics.criticalPrediction && (
        <div className="mb-6 p-4 rounded-lg bg-red-500/10 border border-red-500/20 flex items-center gap-4 animate-in fade-in slide-in-from-top-4">
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

        {/* TOP METRICS GRID */}
        <section className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">

          {/* CPU Card */}
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">CPU Usage</CardTitle>
              <Cpu className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="flex justify-between items-start">
                <div className="text-2xl font-bold">{metrics.cpuLoad}% <span className="text-sm font-normal text-muted-foreground">load</span></div>
                {liveData?.anomaly.cpu_spike && (
                  <Badge variant="danger" className="animate-pulse">SPIKE</Badge>
                )}
              </div>
              <div className="flex items-center gap-2 mt-2">
                <Thermometer className="w-3 h-3 text-red-500" />
                <span className="text-xs text-muted-foreground">{metrics.cpuTemp}°C</span>
              </div>
              <ProgressBar value={metrics.cpuLoadVal} max={100} className="mt-3" />

              {/* Heatmap */}
              <CpuHeatmap coreCount={metrics.coreCount} overallLoad={metrics.cpuLoadVal} />
            </CardContent>
          </Card>

          {/* Memory Card */}
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Memory</CardTitle>
              <Server className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              <div className="flex justify-between items-start">
                <div className="text-2xl font-bold">{liveData ? formatBytes(liveData.memory.used_kb * 1024) : '0 GB'}</div>
                {liveData?.anomaly.mem_spike && (
                  <Badge variant="danger" className="animate-pulse">SPIKE</Badge>
                )}
              </div>
              <p className="text-xs text-muted-foreground">
                Used of {liveData ? formatBytes(liveData.memory.total_kb * 1024) : '...'}
              </p>
              <ProgressBar value={metrics.ramUsagePercent} variant="default" className="mt-3" />

              {metrics.swapUsage > 0 && liveData && (
                <div className="mt-4 pt-4 border-t">
                  <div className="flex justify-between text-xs mb-1">
                    <span className="text-muted-foreground">Swap</span>
                    <span className="text-destructive font-medium">
                      {formatBytes(liveData.memory.swap_used_kb * 1024)}
                    </span>
                  </div>
                  <ProgressBar value={metrics.swapUsage} variant="danger" className="h-1.5" />
                </div>
              )}
            </CardContent>
          </Card>

          {/* Network Card */}
          <Card>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">Network</CardTitle>
              <Wifi className="h-4 w-4 text-muted-foreground" />
            </CardHeader>
            <CardContent>
              {liveData ? (
                <div className="space-y-1">
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Rx:</span>
                    <span className="font-mono">{formatBytes(liveData.network.rx_bps)}/s</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-muted-foreground">Tx:</span>
                    <span className="font-mono">{formatBytes(liveData.network.tx_bps)}/s</span>
                  </div>
                  <Badge variant="outline" className="mt-2 text-xs w-full justify-center">
                    {liveData.network.primary_iface}
                  </Badge>
                </div>
              ) : <Skeleton className="h-16 w-full" />}
            </CardContent>
          </Card>

          {/* Anomaly & AI Card */}
          <Card className={metrics.anomalyValue > 0.7 ? "border-red-500 bg-red-500/5" : ""}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium">AI Status</CardTitle>
              <Brain className={`h-4 w-4 ${metrics.anomalyValue > 0.7 ? "text-red-500 animate-pulse" : "text-purple-500"}`} />
            </CardHeader>
            <CardContent>
              <div className="flex items-baseline space-x-2">
                <div className="text-2xl font-bold">{(metrics.anomalyValue * 100).toFixed(0)}%</div>
                <span className="text-xs text-muted-foreground">Anomaly Score</span>
              </div>
              <div className="mt-2 flex items-center gap-2">
                <Activity className="w-3 h-3 text-muted-foreground" />
                <span className="text-xs font-medium uppercase text-muted-foreground">{metrics.regime}</span>
              </div>
              <ProgressBar
                value={metrics.anomalyValue * 100}
                variant={metrics.anomalyValue > 0.5 ? "danger" : "success"}
                className="mt-3"
                showValue={false}
              />
            </CardContent>
          </Card>

        </section>

        {/* HISTORY CHARTS SECTION */}
        <section>
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
            <History className="w-5 h-5 text-muted-foreground" />
            History (Last 3 Minutes)
          </h2>
          <div className="grid gap-4 md:grid-cols-3 h-[200px]">
            <MetricChart
              title="CPU Load"
              data={history}
              dataKey="cpu.load1"
              color="#3b82f6"
              unit="%"
              range={[0, 100]}
            />
            <MetricChart
              title="Memory Usage"
              data={history}
              dataKey="memory.used_kb"
              color="#a855f7"
              formatter={(val) => formatBytes(val * 1024)}
            />
            <MetricChart
              title="Network Rx"
              data={history}
              dataKey="network.rx_bps"
              color="#f59e0b"
              formatter={(val) => `${formatBytes(val)}/s`}
            />
          </div>
        </section>

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
                      <span>R: {formatBytes(disk.read_bps)}/s</span>
                      <span>W: {formatBytes(disk.write_bps)}/s</span>
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
        {liveData?.anomaly.predictions && liveData.anomaly.predictions.length > 0 && (
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
        )}

      </main>
    </div>
  );
}

export default App;