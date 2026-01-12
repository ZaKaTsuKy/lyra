import React, { Suspense, useEffect, useRef } from 'react';
import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls, PerspectiveCamera, Environment, ContactShadows } from '@react-three/drei';
import { TowerModel } from './TowerModel';

// ============================
// UNIFIED FRAME CONTROLLER
// Uses interval-based invalidation (more reliable than frame counting)
// ============================
function UnifiedFrameController() {
    const { invalidate, gl } = useThree();
    const isVisible = useRef(true);
    const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

    // Visibility handling
    useEffect(() => {
        const handleVisibility = () => {
            isVisible.current = document.visibilityState === 'visible';
            if (isVisible.current) {
                invalidate();
            }
        };

        document.addEventListener('visibilitychange', handleVisibility);
        return () => document.removeEventListener('visibilitychange', handleVisibility);
    }, [invalidate]);

    // Fixed interval invalidation (~20fps = 50ms)
    // This is more predictable than frame counting
    useEffect(() => {
        intervalRef.current = setInterval(() => {
            if (isVisible.current) {
                invalidate();
            }
        }, 50); // 20fps refresh rate

        return () => {
            if (intervalRef.current) {
                clearInterval(intervalRef.current);
            }
        };
    }, [invalidate]);

    // Cleanup WebGL context on unmount
    useEffect(() => {
        return () => {
            gl.dispose();
        };
    }, [gl]);

    return null;
}

// ============================
// SCENE COMPONENT - Optimized
// ============================
export const Scene: React.FC = React.memo(() => {
    const canvasRef = useRef<HTMLCanvasElement>(null);

    return (
        <div className="w-full h-full min-h-[300px] bg-slate-950 rounded-lg overflow-hidden relative">
            <Canvas
                ref={canvasRef}
                shadows
                dpr={[1, 1.5]}
                frameloop="demand"
                gl={{
                    powerPreference: 'low-power',
                    antialias: true,
                    // Reduce memory usage
                    preserveDrawingBuffer: false,
                    // Disable unnecessary features
                    alpha: false,
                    stencil: false,
                    depth: true,
                }}
                // Performance optimizations
                performance={{
                    min: 0.5,  // Allow frame rate to drop to 50%
                    max: 1,
                    debounce: 200,
                }}
            >
                <UnifiedFrameController />

                <PerspectiveCamera makeDefault position={[5, 4, 6]} fov={50} />

                {/* OrbitControls WITHOUT autoRotate - rotation handled manually */}
                <OrbitControls
                    makeDefault
                    minPolarAngle={0}
                    maxPolarAngle={Math.PI / 1.5}
                    enablePan={false}
                    autoRotate={false}  // DISABLED - prevents continuous invalidation
                    enableDamping={true}
                    dampingFactor={0.05}
                />

                <ambientLight intensity={0.5} />
                <spotLight
                    position={[10, 10, 10]}
                    angle={0.15}
                    penumbra={1}
                    intensity={1}
                    castShadow
                    shadow-mapSize={[512, 512]}
                />
                <pointLight position={[-10, -10, -10]} intensity={0.5} color="#4ade80" />

                <Suspense fallback={null}>
                    <TowerModel />
                    <Environment preset="city" />
                </Suspense>

                <ContactShadows
                    position={[0, 0, 0]}
                    opacity={0.5}
                    scale={10}
                    blur={1.5}
                    far={4.5}
                />
            </Canvas>

            <div className="absolute bottom-2 left-2 pointer-events-none">
                <span className="text-xs text-slate-500 font-mono">DIGITAL TWIN // LIVE</span>
            </div>
        </div>
    );
});

Scene.displayName = 'Scene';