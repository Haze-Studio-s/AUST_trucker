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
    }

    function onWindowResize() {
        if (!camera || !renderer) return;
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.render(scene, camera);
    }

    function sendOffsetUpdate() {
        const now = performance.now();
        if (now - lastSentTime < 14) return; // Limite de ~60 fps para tráfego leve
        lastSentTime = now;

        const resName = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'AUST_trucker';

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

        fetch(`https://${resName}/moveGizmoOffset`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload)
        }).catch(() => {});
    }

    // ====================================================================
    //  MANIPULADORES DE COMANDOS NUI (MENSAGENS DO CLIENTE)
    // ====================================================================

    function initGizmo(data) {
        initThree();
        isActive = true;

        if (container) {
            container.style.display = 'block';
            container.style.pointerEvents = 'none';
        }
        if (canvas) {
            canvas.style.pointerEvents = 'none';
        }

        if (data && data.position) {
            updateTargetMesh(data.position, data.rotation || { x: 0, y: 0, z: 0 });
        }

        currentMode = 'translate';
        if (transformControls) {
            transformControls.setMode('translate');
            transformControls.enabled = true;
        }

        renderer.render(scene, camera);
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
            transformControls.updateMatrixWorld();
        }

        if (renderer && scene && camera) {
            renderer.render(scene, camera);
        }
    }

    function setGizmoMode(mode) {
        currentMode = mode === 'rotate' ? 'rotate' : 'translate';
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
            case 'hideGizmo':
                hideGizmo();
                break;
        }
    });
})();
