import * as React from "react"
import { cn } from "@/lib/utils"

interface ProgressBarProps extends React.HTMLAttributes<HTMLDivElement> {
    value: number
    max?: number
    label?: string
    showValue?: boolean
    variant?: "default" | "success" | "warning" | "danger"
}

const ProgressBar = React.forwardRef<HTMLDivElement, ProgressBarProps>(
    ({ className, value, max = 100, label, showValue = true, variant = "default", ...props }, ref) => {
        const percentage = Math.min(Math.max((value / max) * 100, 0), 100)

        let colorClass = "bg-primary"
        if (variant === "success") colorClass = "bg-green-500"
        if (variant === "warning") colorClass = "bg-yellow-500"
        if (variant === "danger") colorClass = "bg-red-500"

        // Auto-color based on value if default variant
        if (variant === "default") {
            if (percentage > 90) colorClass = "bg-red-500"
            else if (percentage > 75) colorClass = "bg-yellow-500"
        }

        return (
            <div ref={ref} className={cn("w-full space-y-1", className)} {...props}>
                {(label || showValue) && (
                    <div className="flex justify-between text-xs text-muted-foreground">
                        {label && <span>{label}</span>}
                        {showValue && <span>{percentage.toFixed(1)}%</span>}
                    </div>
                )}
                <div className="h-2 w-full overflow-hidden rounded-full bg-secondary">
                    <div
                        className={cn("h-full transition-all duration-500 ease-in-out", colorClass)}
                        style={{ width: `${percentage}%` }}
                    />
                </div>
            </div>
        )
    }
)
ProgressBar.displayName = "ProgressBar"

export { ProgressBar }
