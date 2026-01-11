import { memo } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/shared/components/ui/card";
import { ProgressBar } from "@/shared/components/ui/progress-bar";
import { formatBytes } from "@/lib/formatters";
import type { ProcessInstant } from "@/types/omni";
import { Activity } from "lucide-react";

interface ProcessListProps {
    processes: ProcessInstant[];
}

export const ProcessList = memo(function ProcessList({ processes }: ProcessListProps) {
    return (
        <Card className="col-span-full">
            <CardHeader className="pb-3">
                <CardTitle className="flex items-center gap-2 text-lg">
                    <Activity className="w-5 h-5" />
                    Top Processes
                </CardTitle>
            </CardHeader>
            <CardContent>
                <div className="overflow-x-auto">
                    <table className="w-full text-sm text-left">
                        <thead className="text-xs text-muted-foreground uppercase bg-secondary/50">
                            <tr>
                                <th className="px-4 py-2 rounded-tl-md">PID</th>
                                <th className="px-4 py-2">Name</th>
                                <th className="px-4 py-2 w-1/3">CPU Usage</th>
                                <th className="px-4 py-2 rounded-tr-md text-right">Memory</th>
                            </tr>
                        </thead>
                        <tbody>
                            {processes.map((proc) => (
                                <tr key={proc.pid} className="border-b last:border-0 hover:bg-muted/50 transition-colors">
                                    <td className="px-4 py-3 font-mono text-muted-foreground">{proc.pid}</td>
                                    <td className="px-4 py-3 font-medium">{proc.name}</td>
                                    <td className="px-4 py-3">
                                        <div className="flex items-center gap-3">
                                            <span className="w-12 text-right font-mono">{proc.cpu.toFixed(1)}%</span>
                                            <ProgressBar value={proc.cpu} max={100} className="h-1.5 flex-1" showValue={false} />
                                        </div>
                                    </td>
                                    <td className="px-4 py-3 text-right font-mono">{formatBytes(proc.mem_kb * 1024)}</td>
                                </tr>
                            ))}
                            {processes.length === 0 && (
                                <tr>
                                    <td colSpan={4} className="px-4 py-8 text-center text-muted-foreground">
                                        No process data available
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </CardContent>
        </Card>
    );
});
