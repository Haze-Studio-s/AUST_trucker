// ====================================================================
//  AUST_trucker · html/js/gizmo_overlay.js
//  Motor de Manipulação 3D (Three.js + TransformControls)
//  Engenharia Reversa adaptada do vp_staff_studio (Haze-Studio-s)
// ====================================================================

(function () {
    let scene = null;
    let camera = null;
    let renderer = null;
    let transformControls = null;
    let targetMesh = null;
    let isActive = false;
    let currentMode = 'translate'; // 'translate' | 'rotate'
    let lastSentTime = 0;

    const container = document.getElementById('gizmo-overlay-container');
    const canvas = document.getElementById('gizmo-three-canvas');
    const btnConfirm = document.getElementById('btn-gizmo-confirm');
    const btnMode = document.getElementById('btn-gizmo-mode');
    const btnCopy = document.getElementById('btn-gizmo-copy');
    const btnCancel = document.getElementById('btn-gizmo-cancel');
    const batchBadge = document.getElementById('gizmo-batch-badge');
    const batchText = document.getElementById('gizmo-batch-text');
    const targetToggleGroup = document.getElementById('gizmo-target-toggle-group');
    const btnTargetCargo = document.getElementById('btn-gizmo-target-cargo');
    const btnTargetStrap = document.getElementById('btn-gizmo-target-strap');

    let currentTarget = 'cargo'; // 'cargo' | 'strap'

    function sendCallback(endpoint, data = {}) {
        const resName = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'AUST_trucker';
        fetch(`https://${resName}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        }).catch(() => {});
    }

    function updateTargetButtonsUI(target) {
        currentTarget = target || 'cargo';
        if (btnTargetCargo && btnTargetStrap) {
            if (currentTarget === 'cargo') {
                btnTargetCargo.style.background = '#10b981';
                btnTargetCargo.style.color = '#ffffff';
                btnTargetStrap.style.background = 'transparent';
                btnTargetStrap.style.color = '#94a3b8';
            } else {
                btnTargetCargo.style.background = 'transparent';
                btnTargetCargo.style.color = '#94a3b8';
                btnTargetStrap.style.background = '#3b82f6';
                btnTargetStrap.style.color = '#ffffff';
            }
        }
    }

    function initButtons() {
        if (btnTargetCargo) {
            btnTargetCargo.onclick = function (e) {
                e.preventDefault();
                e.stopPropagation();
                updateTargetButtonsUI('cargo');
                sendCallback('switchGizmoTarget', { target: 'cargo' });
            };
        }
        if (btnTargetStrap) {
            btnTargetStrap.onclick = function (e) {
                e.preventDefault();
                e.stopPropagation();
                updateTargetButtonsUI('strap');
                sendCallback('switchGizmoTarget', { target: 'strap' });
            };
        }
        let isConfirming = false;
        function triggerConfirm() {
            if (isConfirming) return;
            isConfirming = true;
            if (btnConfirm) {
                btnConfirm.style.transform = 'scale(0.95)';
                btnConfirm.style.filter = 'brightness(1.2)';
                setTimeout(() => {
                    if (btnConfirm) {
                        btnConfirm.style.transform = 'none';
                        btnConfirm.style.filter = 'none';
                    }
                    isConfirming = false;
                }, 300);
            } else {
                setTimeout(() => { isConfirming = false; }, 300);
            }
            sendCallback('confirmGizmoSlot');
        }

        if (btnConfirm) {
            btnConfirm.onclick = function (e) {
                e.preventDefault();
                e.stopPropagation();
                triggerConfirm();
            };
        }
        if (btnMode) {
            btnMode.onclick = function (e) {
                e.preventDefault();
                e.stopPropagation();
                const newMode = currentMode === 'translate' ? 'rotate' : 'translate';
                setGizmoMode(newMode);
            };
        }
        if (btnCopy) {
            btnCopy.onclick = function (e) {
                e.preventDefault();
                e.stopPropagation();
                sendCallback('copyGizmoSlot');
            };
        }
        if (btnCancel) {
            btnCancel.onclick = function (e) {
                e.preventDefault();
                e.stopPropagation();
                sendCallback('cancelGizmo');
            };
        }

        window.addEventListener('keydown', (e) => {
            if (!isActive) return;
            if (e.key === 'Enter') {
                e.preventDefault();
                e.stopPropagation();
                triggerConfirm();
            } else if (e.key === 'Escape') {
                e.preventDefault();
                e.stopPropagation();
                sendCallback('cancelGizmo');
            } else if (e.key === 't' || e.key === 'T') {
                setGizmoMode('translate');
            } else if (e.key === 'r' || e.key === 'R') {
                setGizmoMode('rotate');
            } else if (e.key === 'c' || e.key === 'C') {
                e.preventDefault();
                sendCallback('copyGizmoSlot');
            }
        });
    }

    function initThree() {
        if (scene) return;

        scene = new THREE.Scene();

        camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.1, 2000);
        camera.rotation.order = 'YZX';

        renderer = new THREE.WebGLRenderer({
            canvas: canvas,
            alpha: true,
            antialias: true,
            powerPreference: 'high-performance'
        });
        renderer.setClearColor(0x000000, 0);
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

        const ambientLight = new THREE.AmbientLight(0xffffff, 1.2);
        scene.add(ambientLight);

        const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
        dirLight.position.set(10, 20, 15);
        scene.add(dirLight);

        // Dummy Object3D que representa o fantasma
        targetMesh = new THREE.Object3D();
        targetMesh.rotation.order = 'YZX';
        scene.add(targetMesh);

        // Inicializa TransformControls (Tradução e Rotação visual)
        transformControls = new THREE.TransformControls(camera, renderer.domElement);
        transformControls.size = 0.85;
        transformControls.space = 'world';
        transformControls.setMode(currentMode);
        transformControls.attach(targetMesh);
        scene.add(transformControls);

        transformControls.addEventListener('change', () => {
            if (isActive) {
                renderer.render(scene, camera);
            }
        });

        transformControls.addEventListener('objectChange', () => {
            if (!isActive) return;
            sendOffsetUpdate();
        });

        window.addEventListener('resize', onWindowResize);
        initButtons();
    }

    function onWindowResize() {
        if (!camera || !renderer) return;
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.render(scene, camera);
    }

    let gizmoContext = 'trailer'; // 'trailer' | 'spawn' | 'propeditor'

    function sendOffsetUpdate() {
        const now = performance.now();
        if (now - lastSentTime < 14) return; // Limite de ~60 fps para tráfego leve
        lastSentTime = now;

        // Conversão Three.js (Y-Up) -> FiveM (Z-Up)
        const payload = {
            position: {
                x: targetMesh.position.x,
                y: -targetMesh.position.z,
                z: targetMesh.position.y
            },
            rotation: {
                x: THREE.MathUtils.radToDeg(targetMesh.rotation.x),
                y: THREE.MathUtils.radToDeg(-targetMesh.rotation.z),
                z: THREE.MathUtils.radToDeg(targetMesh.rotation.y)
            }
        };

        if (gizmoContext === 'propeditor') {
            sendCallback('moveGizmoPropOffset', payload);
        } else if (gizmoContext === 'spawn') {
            sendCallback('moveGizmoSpawn', payload);
        } else {
            sendCallback('moveGizmoOffset', payload);
        }
    }

    // ====================================================================
    //  MANIPULADORES DE COMANDOS NUI (MENSAGENS DO CLIENTE)
    // ====================================================================

    function initGizmo(data) {
        initThree();
        isActive = true;
        gizmoContext = (data && data.context) ? data.context : 'trailer';

        if (container) {
            container.style.display = 'block';
            container.style.pointerEvents = 'none';
        }
        if (canvas) {
            canvas.style.pointerEvents = 'none';
        }

        if (transformControls && targetMesh) {
            transformControls.attach(targetMesh);
            transformControls.setMode('translate');
            transformControls.enabled = true;
        }

        if (data && data.position) {
            updateTargetMesh(data.position, data.rotation || { x: 0, y: 0, z: 0 });
        }

        currentMode = 'translate';
        updateModeButtonUI();

        if (renderer && scene && camera) {
            renderer.render(scene, camera);
        }
    }

    function updateCamera(pos, rot) {
        if (!camera || !renderer || !isActive) return;

        if (pos) {
            // FiveM (Z-Up) -> Three.js (Y-Up): (x, z, -y)
            camera.position.set(pos.x, pos.z, -pos.y);
        }

        if (rot) {
            camera.rotation.order = 'YZX';
            const e = (pitch, yaw) => {
                if (pitch > 0 && pitch < 90) return yaw;
                if ((pitch > -180 && pitch < -90) || pitch > 0) return -yaw;
                return yaw;
            };
            camera.rotation.set(
                THREE.MathUtils.degToRad(rot.x),
                THREE.MathUtils.degToRad(e(rot.x, rot.z)),
                THREE.MathUtils.degToRad(rot.y)
            );
        }

        camera.updateProjectionMatrix();
        renderer.render(scene, camera);
    }

    function updateTargetMesh(pos, rot) {
        if (!targetMesh) return;

        if (pos) {
            targetMesh.position.set(pos.x, pos.z, -pos.y);
        }
        if (rot) {
            targetMesh.rotation.order = 'YZX';
            targetMesh.rotation.set(
                THREE.MathUtils.degToRad(rot.x || 0),
                THREE.MathUtils.degToRad(rot.z || 0),
                THREE.MathUtils.degToRad(rot.y || 0)
            );
        }

        if (transformControls) {
            if (transformControls.object !== targetMesh) {
                transformControls.attach(targetMesh);
            }
            transformControls.updateMatrixWorld();
        }

        if (renderer && scene && camera) {
            renderer.render(scene, camera);
        }
    }

    function updateModeButtonUI() {
        if (btnMode) {
            if (currentMode === 'translate') {
                btnMode.innerHTML = '<i class="fas fa-arrows-alt"></i> Modo: Setas (T)';
                btnMode.style.background = 'linear-gradient(135deg, #3b82f6, #2563eb)';
            } else {
                btnMode.innerHTML = '<i class="fas fa-sync-alt"></i> Modo: Rotação (R)';
                btnMode.style.background = 'linear-gradient(135deg, #8b5cf6, #7c3aed)';
            }
        }
    }

    function setGizmoMode(mode) {
        currentMode = mode === 'rotate' ? 'rotate' : 'translate';
        updateModeButtonUI();
        if (transformControls) {
            transformControls.setMode(currentMode);
            renderer.render(scene, camera);
        }
    }

    function setCursorActive(active) {
        if (container) {
            container.style.pointerEvents = active ? 'auto' : 'none';
        }
        if (canvas) {
            canvas.style.pointerEvents = active ? 'auto' : 'none';
        }
    }

    function hideGizmo() {
        isActive = false;
        if (container) {
            container.style.display = 'none';
            container.style.pointerEvents = 'none';
        }
        if (canvas) {
            canvas.style.pointerEvents = 'none';
        }
        if (batchBadge) {
            batchBadge.style.display = 'none';
        }
        if (targetToggleGroup) {
            targetToggleGroup.style.display = 'none';
        }
        if (transformControls) {
            transformControls.detach();
        }
        if (renderer && scene && camera) {
            renderer.clear();
        }
    }

    // ====================================================================
    //  EVENT LISTENER DE MENSAGENS DO FIVEM
    // ====================================================================

    window.addEventListener('message', (event) => {
        const item = event.data;
        if (!item || !item.action) return;

        switch (item.action) {
            case 'initGizmo':
            case 'showGizmo':
                initGizmo(item.data);
                break;
            case 'setCameraPosition':
                updateCamera(item.data.position, item.data.rotation);
                break;
            case 'setGizmoEntity':
                updateTargetMesh(item.data.position, item.data.rotation);
                break;
            case 'setGizmoMode':
                setGizmoMode(item.data.mode);
                break;
            case 'setGizmoCursor':
                setCursorActive(item.data.active);
                break;
            case 'updateGizmoBatch':
                if (batchBadge && batchText) {
                    if (item.data && item.data.total > 1) {
                        batchText.textContent = `Item ${item.data.current || 1} de ${item.data.total}`;
                        batchBadge.style.display = 'block';
                    } else {
                        batchBadge.style.display = 'none';
                    }
                }
                break;
            case 'setGizmoTarget':
                if (targetToggleGroup) {
                    targetToggleGroup.style.display = (item.data && item.data.showToggle) ? 'flex' : 'none';
                }
                if (item.data && item.data.target) {
                    updateTargetButtonsUI(item.data.target);
                }
                break;
            case 'hideGizmo':
                hideGizmo();
                break;
        }
    });
})();
