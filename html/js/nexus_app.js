// ============================================================================
// AUST_trucker — UNIFIED APP (Vue 3 + Nexus OS Design System)
// Gerenciador de UI do Motorista, Staff Admin, Gizmo 3D e Toasts
// ============================================================================

const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

const app = createApp({
    setup() {
        // Visibilidade
        const isDriverOpen = ref(false);
        const isAdminOpen = ref(false);
        const activeDriverTab = ref('jobs'); // 'jobs' | 'garage' | 'progression' | 'company'
        const activeAdminTab = ref('routes'); // 'routes' | 'offsets' | 'spawns' | 'economy'
        
        // Dados do Jogador e Fretes
        const player = ref({
            name: 'Motorista Profissional',
            money: 12500,
            level: 3,
            xp: 1450,
            nextXp: 2000,
            totalDeliveries: 18,
            totalDistance: 142.5
        });

        const contracts = ref([]);
        const myTrucks = ref([]);
        const toasts = ref([]);
        const adrAlert = ref(null);

        // Modal de Despacho / Início de Frete
        const selectedContract = ref(null);
        const dispatchForm = ref({
            useOwnedTruck: false,
            withForklift: true
        });

        // Dados do Admin
        const adminData = ref({
            customRoutes: {},
            spawns: {},
            trailerOffsets: {},
            npcs: {},
            economy: {},
            defaultProps: []
        });
        const selectedTrailerModel = ref('');
        const selectedSlotIndex = ref(1);
        const isForkliftSlot = ref(false);

        // NUI Post Helper
        const postNUI = async (endpoint, data = {}) => {
            const resName = window.GetParentResourceName ? window.GetParentResourceName() : 'AUST_trucker';
            try {
                const res = await fetch(`https://${resName}/${endpoint}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                    body: JSON.stringify(data)
                });
                return await res.json();
            } catch (err) {
                return null;
            }
        };

        // Adicionar Notificação Toast
        const addToast = (title, message, type = 'info', duration = 6000) => {
            const id = Date.now() + Math.random();
            toasts.value.push({ id, title, message, type });
            setTimeout(() => {
                toasts.value = toasts.value.filter(t => t.id !== id);
            }, duration);
        };

        // Fechar Tudo / Hard Escape
        const closeAll = () => {
            isDriverOpen.value = false;
            isAdminOpen.value = false;
            selectedContract.value = null;
            postNUI('escapeNui', {});
        };

        // Handlers de Janela
        const closeDriver = () => {
            isDriverOpen.value = false;
            postNUI('closeMenu', {});
        };

        const closeAdmin = () => {
            isAdminOpen.value = false;
            postNUI('adminClose', {});
        };

        // Iniciar Frete
        const confirmStartDelivery = () => {
            if (!selectedContract.value) return;
            const payload = {
                contract_id: selectedContract.value.contract_id,
                jobId: selectedContract.value.contract_id,
                name: selectedContract.value.contract_name,
                cargoType: selectedContract.value.cargo_type_name || 'dry',
                trailerModel: selectedContract.value.trailer,
                useOwnedTruck: dispatchForm.value.useOwnedTruck,
                withForklift: dispatchForm.value.withForklift,
                reward: selectedContract.value.reward,
                distance: selectedContract.value.distance
            };
            postNUI('startDelivery', payload);
            isDriverOpen.value = false;
            selectedContract.value = null;
        };

        // Admin: Iniciar Calibração de Gizmo 3D
        const startGizmoCalibration = () => {
            if (!selectedTrailerModel.value) {
                addToast('Admin', 'Selecione um modelo de reboque primeiro!', 'warning');
                return;
            }
            postNUI('adminStartOffsetCalibration', {
                trailerModel: selectedTrailerModel.value,
                slotIndex: selectedSlotIndex.value,
                isForklift: isForkliftSlot.value
            });
            isAdminOpen.value = false;
        };

        // Listener de Mensagens NUI
        const handleMessage = (event) => {
            const item = event.data;
            if (!item) return;

            // Fechamento
            if (item.action === 'close' || item.action === 'close_all' || item.action === 'closeUI' || item.hidemenu) {
                isDriverOpen.value = false;
                isAdminOpen.value = false;
                selectedContract.value = null;
                return;
            }

            // Abertura do Driver Panel
            if (item.showmenu || item.action === 'open' || item.update) {
                const dados = item.dados || item;
                if (item.jobs && Array.isArray(item.jobs)) {
                    contracts.value = item.jobs;
                } else if (dados.trucker_available_contracts) {
                    contracts.value = dados.trucker_available_contracts;
                }
                if (dados.trucker_users) {
                    player.value.money = dados.trucker_users.money || 0;
                    player.value.xp = dados.trucker_users.exp || 0;
                }
                if (dados.trucker_trucks) {
                    myTrucks.value = dados.trucker_trucks;
                }
                isDriverOpen.value = true;
                return;
            }

            // Abertura do Admin Panel
            if (item.action === 'admin_open') {
                if (item.data) {
                    adminData.value = item.data;
                    if (item.data.trailerOffsets) {
                        const keys = Object.keys(item.data.trailerOffsets);
                        if (keys.length > 0) selectedTrailerModel.value = keys[0];
                    }
                }
                isAdminOpen.value = true;
                return;
            }

            // Toasts NUI
            if (item.action === 'showNotification' || item.action === 'notify') {
                addToast(item.title || 'Central Logística', item.description || item.message, item.type || 'info');
                return;
            }

            // Alerta ADR
            if (item.action === 'showAdrAlert') {
                adrAlert.value = item.data;
                return;
            }
            if (item.action === 'hideAdrAlert') {
                adrAlert.value = null;
                return;
            }
        };

        const handleKeyDown = (e) => {
            if (e.key === 'Escape') {
                if (selectedContract.value) {
                    selectedContract.value = null;
                } else if (isDriverOpen.value || isAdminOpen.value) {
                    closeAll();
                }
            }
        };

        onMounted(() => {
            window.addEventListener('message', handleMessage);
            window.addEventListener('keydown', handleKeyDown);
        });

        onUnmounted(() => {
            window.removeEventListener('message', handleMessage);
            window.removeEventListener('keydown', handleKeyDown);
        });

        return {
            isDriverOpen,
            isAdminOpen,
            activeDriverTab,
            activeAdminTab,
            player,
            contracts,
            myTrucks,
            toasts,
            adrAlert,
            selectedContract,
            dispatchForm,
            adminData,
            selectedTrailerModel,
            selectedSlotIndex,
            isForkliftSlot,
            closeDriver,
            closeAdmin,
            confirmStartDelivery,
            startGizmoCalibration,
            addToast
        };
    }
});

app.mount('#app');
