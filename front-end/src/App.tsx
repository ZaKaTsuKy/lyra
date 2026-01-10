import { useEffect } from 'react';
import { useOmniStore } from './store/useOmniStore';
import { cn } from './lib/utils';
import { Activity, Cpu, Server, AlertTriangle, Thermometer, Brain } from 'lucide-react';

function App() {
  const { connect, status, staticInfo, liveData } = useOmniStore();

  useEffect(() => {
    connect();
  }, [connect]);

  // Derive simple CPU load average from the load1/load5/load15 if desired, or just use load1
  const cpuLoad = liveData?.cpu.load1.toFixed(2) ?? '0.00';
  const cpuTemp = liveData?.cpu.temp_package.toFixed(1) ?? '0.0';
  const ramUsage = liveData ? ((liveData.memory.used_kb / liveData.memory.total_kb) * 100).toFixed(1) : '0.0';
  // Actually Anomaly is 0.0-1.0
  const anomalyValue = liveData?.anomaly.overall.toFixed(2) ?? '0.00';
  const regime = liveData?.anomaly.regime ?? 'Unknown';

  return (
    <div className="min-h-screen bg-background text-foreground p-8 font-sans">
      <header className="mb-8 flex items-center justify-between border-b pb-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Omni Monitor Debug</h1>
          <p className="text-muted-foreground">WebSocket telemetry validation</p>
        </div>
        <div className={cn(
          "flex items-center gap-2 px-3 py-1 rounded-full text-sm font-medium border",
          status === 'connected' ? "bg-green-100 text-green-700 border-green-200" :
            status === 'connecting' ? "bg-yellow-100 text-yellow-700 border-yellow-200" :
              "bg-red-100 text-red-700 border-red-200"
        )}>
          <div className={cn(
            "w-2 h-2 rounded-full",
            status === 'connected' ? "bg-green-600 animate-pulse" :
              status === 'connecting' ? "bg-yellow-600" :
                "bg-red-600"
          )} />
          {status.toUpperCase()}
        </div>
      </header>

      <main className="grid gap-6 md:grid-cols-2">
        {/* Static Info Card */}
        <section className="border rounded-lg p-6 bg-card shadow-sm">
          <div className="flex items-center gap-2 mb-4 text-primary">
            <Server className="w-5 h-5" />
            <h2 className="text-lg font-semibold">Static Info</h2>
          </div>

          {staticInfo ? (
            <div className="space-y-2 text-sm">
              <div className="grid grid-cols-3 gap-2 py-1 border-b">
                <span className="font-medium text-muted-foreground">Hostname</span>
                <span className="col-span-2 font-mono">{staticInfo.static.hostname}</span>
              </div>
              <div className="grid grid-cols-3 gap-2 py-1 border-b">
                <span className="font-medium text-muted-foreground">Kernel</span>
                <span className="col-span-2 font-mono">{staticInfo.static.kernel_version}</span>
              </div>
              <div className="grid grid-cols-3 gap-2 py-1 border-b">
                <span className="font-medium text-muted-foreground">CPU Model</span>
                <span className="col-span-2 font-mono">{staticInfo.static.cpu_model}</span>
              </div>
              <div className="grid grid-cols-3 gap-2 py-1">
                <span className="font-medium text-muted-foreground">Cores</span>
                <span className="col-span-2 font-mono">{staticInfo.static.core_count} Threads</span>
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-center h-32 text-muted-foreground animate-pulse">
              Waiting for init payload...
            </div>
          )}
        </section>

        {/* Live Metrics Card */}
        <section className="border rounded-lg p-6 bg-card shadow-sm">
          <div className="flex items-center gap-2 mb-4 text-primary">
            <Activity className="w-5 h-5" />
            <h2 className="text-lg font-semibold">Live Metrics</h2>
          </div>

          <div className="grid grid-cols-2 gap-4">

            {/* CPU */}
            <div className="p-4 bg-secondary/20 rounded-md border">
              <div className="flex items-center gap-2 mb-2 text-sm text-muted-foreground">
                <Cpu className="w-4 h-4" /> CPU Load (1m)
              </div>
              <div className="text-2xl font-bold font-mono">{cpuLoad}</div>
              <div className="text-xs text-muted-foreground mt-1 flex items-center gap-1">
                <Thermometer className="w-3 h-3" /> {cpuTemp}°C
              </div>
            </div>

            {/* RAM */}
            <div className="p-4 bg-secondary/20 rounded-md border">
              <div className="flex items-center gap-2 mb-2 text-sm text-muted-foreground">
                <Server className="w-4 h-4" /> RAM Usage
              </div>
              <div className="text-2xl font-bold font-mono">{ramUsage}%</div>
            </div>

            {/* Anomaly */}
            <div className="p-4 bg-secondary/20 rounded-md border text-slate-900">
              <div className="flex items-center gap-2 mb-2 text-sm text-slate-500">
                <AlertTriangle className="w-4 h-4" /> Anomaly Score
              </div>
              <div className={cn(
                "text-2xl font-bold font-mono",
                parseFloat(anomalyValue) > 0.5 ? "text-red-500" : "text-green-500"
              )}>{anomalyValue}</div>
            </div>

            {/* Regime */}
            <div className="p-4 bg-secondary/20 rounded-md border">
              <div className="flex items-center gap-2 mb-2 text-sm text-muted-foreground">
                <Brain className="w-4 h-4" /> AI Regime
              </div>
              <div className="text-lg font-bold font-mono uppercase tracking-wider text-purple-600">
                {regime}
              </div>
            </div>

          </div>

          {!liveData && (
            <div className="mt-4 text-center text-xs text-muted-foreground animate-pulse">
              Connecting to stream...
            </div>
          )}
        </section>
      </main>
    </div>
  );
}

export default App;
