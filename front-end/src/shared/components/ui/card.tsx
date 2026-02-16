import * as React from "react"
import { cn } from "@/lib/utils"

/**
 * Card Component with Glassmorphism Design
 * 
 * Updated to use the glass-card utility for a consistent premium look.
 * Supports variants for different status states.
 */

interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
    variant?: 'default' | 'success' | 'warning' | 'danger';
}

const Card = React.forwardRef<HTMLDivElement, CardProps>(
    ({ className, variant = 'default', ...props }, ref) => {
        const variantClasses = {
            default: '',
            success: 'glass-card--success',
            warning: 'glass-card--warning',
            danger: 'glass-card--danger border-red-500/30',
        };

        return (
            <div
                ref={ref}
                className={cn(
                    "glass-card glass-glow rounded-lg",
                    "text-card-foreground",
                    variantClasses[variant],
                    className
                )}
                {...props}
            />
        );
    }
);
Card.displayName = "Card"

const CardHeader = React.forwardRef<
    HTMLDivElement,
    React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
    <div
        ref={ref}
        className={cn("flex flex-col space-y-1.5 p-4 pb-2", className)}
        {...props}
    />
))
CardHeader.displayName = "CardHeader"

const CardTitle = React.forwardRef<
    HTMLParagraphElement,
    React.HTMLAttributes<HTMLHeadingElement>
>(({ className, ...props }, ref) => (
    <h3
        ref={ref}
        className={cn(
            "text-sm font-semibold leading-none tracking-tight",
            className
        )}
        {...props}
    />
))
CardTitle.displayName = "CardTitle"

const CardDescription = React.forwardRef<
    HTMLParagraphElement,
    React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
    <p
        ref={ref}
        className={cn("text-xs text-muted-foreground", className)}
        {...props}
    />
))
CardDescription.displayName = "CardDescription"

const CardContent = React.forwardRef<
    HTMLDivElement,
    React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
    <div ref={ref} className={cn("p-4 pt-0", className)} {...props} />
))
CardContent.displayName = "CardContent"

const CardFooter = React.forwardRef<
    HTMLDivElement,
    React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
    <div
        ref={ref}
        className={cn("flex items-center p-4 pt-0", className)}
        {...props}
    />
))
CardFooter.displayName = "CardFooter"

export { Card, CardHeader, CardFooter, CardTitle, CardDescription, CardContent }
