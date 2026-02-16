import React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';
import { Slot } from '@radix-ui/react-slot';

const glassPanelVariants = cva(
    "rounded-2xl border backdrop-blur-md transition-all duration-300",
    {
        variants: {
            variant: {
                default: "border-white/10 bg-black/40 hover:bg-black/50 shadow-lg",
                // Using hsl for primary transparency assuming --primary is valid HSL channel data or a color. 
                // Since config maps it to hsl(var(--primary)), --primary likely contains channels.
                active: "border-primary/50 bg-primary/10 hover:bg-primary/20 shadow-[0_0_15px_hsl(var(--primary)/0.3)]",
                danger: "border-destructive/30 bg-destructive/20 hover:bg-destructive/30",
            },
            glow: {
                true: "shadow-[0_0_20px_rgba(255,255,255,0.05)]",
                false: "",
            },
        },
        defaultVariants: {
            variant: "default",
            glow: false,
        },
    }
);

export interface GlassPanelProps
    extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof glassPanelVariants> {
    asChild?: boolean;
}

const GlassPanel = React.forwardRef<HTMLDivElement, GlassPanelProps>(
    ({ className, variant, glow, asChild = false, ...props }, ref) => {
        const Comp = asChild ? Slot : "div";
        return (
            <Comp
                className={cn(glassPanelVariants({ variant, glow, className }))}
                ref={ref}
                {...props}
            />
        );
    }
);
GlassPanel.displayName = "GlassPanel";

export { GlassPanel, glassPanelVariants };
