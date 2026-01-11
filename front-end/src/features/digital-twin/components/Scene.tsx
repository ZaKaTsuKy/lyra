import React, { Suspense, useState, useEffect, useRef, useCallback } from 'react';
import { Canvas, useThree } from '@react-three/fiber';
import { OrbitControls, PerspectiveCamera, Environment, ContactShadows } from '@react-three/drei';
import { TowerModel } from './TowerModel';

// ============================
// FRAME LOOP CONTROLLER
// Invalidates the frame on telemetry update (1Hz) instead of 60fps
// ============================
function FrameLoopController() {
    const { invalidate } = useThree();
    const animationRef = useRef<number | null>(null);
    const lastFrameTime = useRef(0);
    const TARGET_FPS = 30; // 30fps is plenty for a monitoring dashboard
    const FRAME_INTERVAL = 1000 / TARGET_FPS;

    useEffect(() => {
        let isVisible = true;

        const handleVisibilityChange = () => {
            isVisible = document.visibilityState === 'visible';
            if (isVisible) {
                // Resume animation loop when tab becomes visible
                startLoop();
            } else {
                // Stop animation loop when tab is hidden
                if (animationRef.current) {
                    cancelAnimationFrame(animationRef.current);
                    animationRef.current = null;
                }
            }
        };

        const loop = (currentTime: number) => {
            if (!isVisible) return;

            const elapsed = currentTime - lastFrameTime.current;
            if (elapsed >= FRAME_INTERVAL) {
                lastFrameTime.current = currentTime - (elapsed % FRAME_INTERVAL);
                invalidate(); // Trigger a single frame render
            }

            animationRef.current = requestAnimationFrame(loop);
        };

        const startLoop = () => {
            if (!animationRef.current) {
                animationRef.current = requestAnimationFrame(loop);
            }
        };

        document.addEventListener('visibilitychange', handleVisibilityChange);
        startLoop();

        return () => {
            document.removeEventListener('visibilitychange', handleVisibilityChange);
            if (animationRef.current) {
                cancelAnimationFrame(animationRef.current);
            }
        };
    }, [invalidate]);

    return null;
}

export const Scene: React.FC = () => {
    return (
        <div className="w-full h-full min-h-[300px] bg-slate-950 rounded-lg overflow-hidden relative">
            <Canvas
                shadows
                dpr={[1, 1.5]} // Reduce max DPR for performance
                frameloop="demand" // Only render when invalidate() is called
                gl={{
                    powerPreference: 'low-power', // Prefer integrated GPU
                    antialias: true,
                }}
                onCreated={({ gl }) => {
                    return () => {
                        gl.dispose();
                    };
                }}
            >
                <FrameLoopController />

                <PerspectiveCamera makeDefault position={[5, 4, 6]} fov={50} />
                <OrbitControls
                    makeDefault
                    minPolarAngle={0}
                    maxPolarAngle={Math.PI / 1.5}
                    enablePan={false}
                    autoRotate={true}
                    autoRotateSpeed={0.3} // Slower rotation
                />

                <ambientLight intensity={0.5} />
                <spotLight
                    position={[10, 10, 10]}
                    angle={0.15}
                    penumbra={1}
                    intensity={1}
                    castShadow
                    shadow-mapSize={[512, 512]} // Reduce shadow map size
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

            {/* Overlay UI if needed */}
            <div className="absolute bottom-2 left-2 pointer-events-none">
                <span className="text-xs text-slate-500 font-mono">DIGITAL TWIN // LIVE</span>
            </div>
        </div>
    );
};
