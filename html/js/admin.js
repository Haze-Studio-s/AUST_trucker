/* ============================================================
   AUST_trucker — html/js/admin.js
   Controle do Painel Administrativo de Rotas Dinâmicas & Spawns
   Padrão Visual Lation Modern UI (Emerald Edition)
   ============================================================ */

(function () {
  let adminData = {
    customRoutes: {},
    spawns: {},
    trailerOffsets: {},
    npcs: {},
    economy: {},
    defaultProps: []
  };

  let activeTab = 'routes';
  let capturingTarget = null; // Guarda qual campo de coordenadas está aguardando captura

  // Inicialização e listeners de Mensagens do FiveM
  window.addEventListener('message', function (event) {
    const item = event.data;
    if (!item || !item.action) return;

    switch (item.action) {
      case 'admin_open':
        openAdminPanel(item.data);
        break;
      case 'admin_close':
        closeAdminPanel();
        break;
      case 'admin_minimize':
        minimizeAdminPanel();
        break;
      case 'admin_restore':
        restoreAdminPanel();
        break;
    }
  });

  // Fechar no ESC
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      const panel = document.getElementById('admin-panel');
      if (panel && panel.style.display === 'flex') {
        closeAdminPanel();
        postNUI('adminClose', {});
      }
    }
  });

  // Helper de comunicação com o Client Lua
  function postNUI(callbackName, data) {
    const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'AUST_trucker';
    return fetch(`https://${resourceName}/${callbackName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {})
    }).then(res => res.json()).catch(() => ({}));
  }

  function openAdminPanel(data) {
    if (data) {
      adminData = data;
    }
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'flex';
      switchTab(activeTab);
    }
  }

  function closeAdminPanel() {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'none';
    }
  }

  function minimizeAdminPanel() {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'none';
    }
  }

  function restoreAdminPanel() {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'flex';
    }
  }

  // Troca de Abas
  function switchTab(tabName) {
    activeTab = tabName;
    document.querySelectorAll('.admin-tab-btn').forEach(btn => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tabName);
    });
    document.querySelectorAll('.admin-tab-pane').forEach(pane => {
      pane.classList.toggle('active', pane.getAttribute('id') === `admin-tab-${tabName}`);
    });

    // Renderiza o conteúdo da aba selecionada
    switch (tabName) {
      case 'routes':
        renderRoutesTab();
        break;
      case 'spawns':
        renderSpawnsTab();
        break;
      case 'props':
        renderPropsTab();
        break;
      case 'offsets':
        renderOffsetsTab();
        break;
      case 'economy':
        renderEconomyTab();
        break;
      case 'npcs':
        renderNPCsTab();
        break;
    }
  }

  // ============================================================
  // ABA 1: ROTAS & CONTRATOS DINÂMICOS
  // ============================================================
  function renderRoutesTab() {
    const tbody = document.getElementById('admin-routes-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const routes = adminData.customRoutes || {};
    const keys = Object.keys(routes);

    if (keys.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding: 24px; color: var(--admin-text-muted);">Nenhuma rota dinâmica cadastrada ainda. Crie uma abaixo!</td></tr>`;
      return;
    }

    keys.forEach(k => {
      const r = routes[k];
      const tr = document.createElement('tr');
      const badgeClass = r.job_type === 'adr' ? 'admin-badge-adr' : (r.job_type === 'quick' ? 'admin-badge-quick' : 'admin-badge-freight');
      
      tr.innerHTML = `
        <td><strong>#${escapeHtml(r.route_id || k)}</strong></td>
        <td>${escapeHtml(r.title || 'Carga Sem Nome')}</td>
        <td><span class="admin-badge ${badgeClass}">${(r.job_type || 'freight').toUpperCase()}</span></td>
        <td>R$ ${Number(r.payment || 0).toLocaleString()} <span style="color:var(--admin-primary)">(${r.xp || 0} XP)</span></td>
        <td>${r.distance_km || 0} km (Lvl ${r.required_level || 1})</td>
        <td>
          <button class="admin-btn admin-btn-outline btn-edit-route" data-id="${k}" title="Editar Rota"><i class="fas fa-edit"></i></button>
          <button class="admin-btn admin-btn-danger btn-del-route" data-id="${k}" title="Excluir Rota"><i class="fas fa-trash"></i></button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    // Eventos dos botões da tabela
    tbody.querySelectorAll('.btn-edit-route').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        fillRouteForm(adminData.customRoutes[id]);
      });
    });

    tbody.querySelectorAll('.btn-del-route').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        if (confirm(`Tem certeza que deseja excluir a rota #${id}?`)) {
          postNUI('adminDeleteRoute', { id: id });
          delete adminData.customRoutes[id];
          renderRoutesTab();
        }
      });
    });
  }

  function fillRouteForm(r) {
    if (!r) return;
    document.getElementById('route-form-id').value = r.route_id || '';
    document.getElementById('route-form-title').value = r.title || '';
    document.getElementById('route-form-type').value = r.job_type || 'freight';
    document.getElementById('route-form-prop').value = r.cargo_prop || 'hei_prop_carrier_cargo_04b';
    document.getElementById('route-form-payment').value = r.payment || 1500;
    document.getElementById('route-form-xp').value = r.xp || 100;
    document.getElementById('route-form-distance').value = r.distance_km || 5.0;
    document.getElementById('route-form-level').value = r.required_level || 1;

    const pCoords = r.pickup_coords ? (typeof r.pickup_coords === 'string' ? JSON.parse(r.pickup_coords) : r.pickup_coords) : {};
    document.getElementById('route-form-pickup-x').value = pCoords.x ? Number(pCoords.x).toFixed(2) : '';
    document.getElementById('route-form-pickup-y').value = pCoords.y ? Number(pCoords.y).toFixed(2) : '';
    document.getElementById('route-form-pickup-z').value = pCoords.z ? Number(pCoords.z).toFixed(2) : '';

    const dCoords = r.delivery_coords ? (typeof r.delivery_coords === 'string' ? JSON.parse(r.delivery_coords) : r.delivery_coords) : {};
    document.getElementById('route-form-deliv-x').value = dCoords.x ? Number(dCoords.x).toFixed(2) : '';
    document.getElementById('route-form-deliv-y').value = dCoords.y ? Number(dCoords.y).toFixed(2) : '';
    document.getElementById('route-form-deliv-z').value = dCoords.z ? Number(dCoords.z).toFixed(2) : '';

    document.getElementById('route-form-forklift').checked = (r.has_forklift == 1 || r.has_forklift === true);
    document.getElementById('route-form-adr').checked = (r.requires_adr == 1 || r.requires_adr === true);
  }

  function saveRouteForm() {
    const routeId = document.getElementById('route-form-id').value.trim();
    if (!routeId) {
      alert('Por favor, informe um identificador único para a rota (ex: rota_porto_oleo).');
      return;
    }

    const pickup = {
      x: parseFloat(document.getElementById('route-form-pickup-x').value) || 0.0,
      y: parseFloat(document.getElementById('route-form-pickup-y').value) || 0.0,
      z: parseFloat(document.getElementById('route-form-pickup-z').value) || 0.0
    };

    const delivery = {
      x: parseFloat(document.getElementById('route-form-deliv-x').value) || 0.0,
      y: parseFloat(document.getElementById('route-form-deliv-y').value) || 0.0,
      z: parseFloat(document.getElementById('route-form-deliv-z').value) || 0.0
    };

    const payload = {
      route_id: routeId,
      title: document.getElementById('route-form-title').value.trim() || 'Carga Personalizada',
      job_type: document.getElementById('route-form-type').value,
      cargo_prop: document.getElementById('route-form-prop').value.trim() || 'hei_prop_carrier_cargo_04b',
      payment: parseInt(document.getElementById('route-form-payment').value) || 1500,
      xp: parseInt(document.getElementById('route-form-xp').value) || 100,
      distance_km: parseFloat(document.getElementById('route-form-distance').value) || 5.0,
      required_level: parseInt(document.getElementById('route-form-level').value) || 1,
      pickup_coords: pickup,
      delivery_coords: delivery,
      has_forklift: document.getElementById('route-form-forklift').checked ? 1 : 0,
      requires_adr: document.getElementById('route-form-adr').checked ? 1 : 0
    };

    postNUI('adminSaveRoute', payload);
    adminData.customRoutes[routeId] = payload;
    renderRoutesTab();
    alert(`Rota #${routeId} salva com sucesso em tempo real!`);
  }

  // ============================================================
  // ABA 2: SPAWNS DINÂMICOS
  // ============================================================
  function renderSpawnsTab() {
    const tbody = document.getElementById('admin-spawns-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const spawns = adminData.spawns || {};
    const keys = Object.keys(spawns);

    if (keys.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; padding: 24px; color: var(--admin-text-muted);">Nenhum ponto de spawn cadastrado. Capture um abaixo!</td></tr>`;
      return;
    }

    keys.forEach(k => {
      const s = spawns[k];
      const coords = s.coords ? (typeof s.coords === 'string' ? JSON.parse(s.coords) : s.coords) : {};
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>#${escapeHtml(s.spawn_id || k)}</strong></td>
        <td>${escapeHtml(s.spawn_name || 'Ponto')}</td>
        <td><span class="admin-badge admin-badge-quick">${(s.spawn_type || 'all').toUpperCase()}</span></td>
        <td style="font-family: monospace; font-size: 11px;">
          X: ${coords.x ? Number(coords.x).toFixed(1) : 0}, Y: ${coords.y ? Number(coords.y).toFixed(1) : 0}, Z: ${coords.z ? Number(coords.z).toFixed(1) : 0}, H: ${coords.heading ? Number(coords.heading).toFixed(1) : 0}°
        </td>
        <td>
          <button class="admin-btn admin-btn-outline btn-tp-spawn" data-x="${coords.x}" data-y="${coords.y}" data-z="${coords.z}" data-h="${coords.heading}" title="Teleportar"><i class="fas fa-location-arrow"></i> TP</button>
          <button class="admin-btn admin-btn-danger btn-del-spawn" data-id="${k}" title="Excluir"><i class="fas fa-trash"></i></button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-tp-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        postNUI('adminTeleport', {
          coords: {
            x: parseFloat(this.getAttribute('data-x')),
            y: parseFloat(this.getAttribute('data-y')),
            z: parseFloat(this.getAttribute('data-z')),
            heading: parseFloat(this.getAttribute('data-h'))
          }
        });
      });
    });

    tbody.querySelectorAll('.btn-del-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        if (confirm(`Excluir o spawn #${id}?`)) {
          postNUI('adminDeleteSpawn', { id: id });
          delete adminData.spawns[id];
          renderSpawnsTab();
        }
      });
    });
  }

  function saveSpawnForm() {
    const spawnId = document.getElementById('spawn-form-id').value.trim();
    if (!spawnId) {
      alert('Informe o ID do ponto de spawn!');
      return;
    }

    const coords = {
      x: parseFloat(document.getElementById('spawn-form-x').value) || 0.0,
      y: parseFloat(document.getElementById('spawn-form-y').value) || 0.0,
      z: parseFloat(document.getElementById('spawn-form-z').value) || 0.0,
      heading: parseFloat(document.getElementById('spawn-form-h').value) || 0.0
    };

    const payload = {
      spawn_id: spawnId,
      spawn_name: document.getElementById('spawn-form-name').value.trim() || 'Ponto de Spawn',
      spawn_type: document.getElementById('spawn-form-type').value,
      coords: coords
    };

    postNUI('adminSaveSpawn', payload);
    adminData.spawns[spawnId] = payload;
    renderSpawnsTab();
    alert(`Ponto de spawn #${spawnId} cadastrado!`);
  }

  // ============================================================
  // ABA 3: CARGAS & PROPS
  // ============================================================
  function renderPropsTab() {
    const grid = document.getElementById('admin-props-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const defaultList = adminData.defaultProps && adminData.defaultProps.length > 0 ? adminData.defaultProps : [
      'hei_prop_carrier_cargo_04b',
      'm24_1_prop_m24_1_carrier_cargo_04a',
      'prop_boxpile_02b',
      'prop_boxpile_06a',
      'prop_boxpile_07d',
      'prop_rub_crate_01',
      'prop_barrel_exp_01a',
      'prop_barrel_02a',
      'prop_wood_pallet_01'
    ];

    defaultList.forEach(prop => {
      const card = document.createElement('div');
      card.className = 'admin-card';
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = '8px';
      card.innerHTML = `
        <div class="admin-card-header" style="margin-bottom: 4px;">
          <strong style="color:var(--admin-primary); font-size:13px;"><i class="fas fa-cube"></i> ${escapeHtml(prop)}</strong>
          <span class="admin-badge admin-badge-freight">Disponível</span>
        </div>
        <p style="margin:0; font-size:11px; color:var(--admin-text-muted);">Modelo 3D validado para amarração e física de slots no trailer.</p>
        <div style="display:flex; justify-content:flex-end; gap:8px; margin-top:8px;">
          <button class="admin-btn admin-btn-outline btn-use-prop" data-prop="${prop}">Usar no Editor de Offsets</button>
        </div>
      `;
      grid.appendChild(card);
    });

    grid.querySelectorAll('.btn-use-prop').forEach(btn => {
      btn.addEventListener('click', function () {
        const prop = this.getAttribute('data-prop');
        document.getElementById('offset-form-prop').value = prop;
        switchTab('offsets');
      });
    });
  }

  // ============================================================
  // ABA 4: CALIBRAÇÃO VISUAL 3D DE OFFSETS
  // ============================================================
  function renderOffsetsTab() {
    const listContainer = document.getElementById('admin-offsets-list');
    if (!listContainer) return;
    listContainer.innerHTML = '';

    const offsets = adminData.trailerOffsets || {};
    const keys = Object.keys(offsets);

    if (keys.length === 0) {
      listContainer.innerHTML = `<p style="color:var(--admin-text-muted); font-size:12px;">Nenhum offset customizado salvo em banco ainda. Os padrões do Config.TrailerSlots estão em vigor.</p>`;
    } else {
      keys.forEach(model => {
        const item = offsets[model];
        const card = document.createElement('div');
        card.className = 'admin-card';
        card.innerHTML = `
          <div class="admin-card-header">
            <span class="admin-card-title"><i class="fas fa-truck"></i> Reboque: <strong>${escapeHtml(model.toUpperCase())}</strong></span>
            <button class="admin-btn admin-btn-outline btn-select-trailer" data-model="${escapeHtml(model)}" style="padding: 4px 10px; font-size: 11px;"><i class="fas fa-edit"></i> Usar Modelo</button>
          </div>
          <div style="font-size:12px; line-height: 1.6;">
            <div><strong>Slots de Paletes Salvos:</strong> ${item.pallets ? Object.keys(item.pallets).length : 0} posições</div>
            <div><strong>Empilhadeira Traseira:</strong> ${item.forklift ? `<span style="color:var(--admin-primary)">Mapeada (X:${Number(item.forklift.x).toFixed(2)}, Y:${Number(item.forklift.y).toFixed(2)}, Z:${Number(item.forklift.z).toFixed(2)})</span>` : 'Padrão'}</div>
          </div>
        `;
        listContainer.appendChild(card);
      });

      listContainer.querySelectorAll('.btn-select-trailer').forEach(btn => {
        btn.addEventListener('click', function () {
          const m = this.getAttribute('data-model');
          const input = document.getElementById('offset-form-trailer');
          if (input) {
            input.value = m;
            input.focus();
          }
        });
      });
    }
  }

  function startCalibrationTool() {
    const trailerModel = document.getElementById('offset-form-trailer').value.trim() || 'trailers2';
    const slotIndex = parseInt(document.getElementById('offset-form-slot').value) || 1;
    const isForklift = document.getElementById('offset-form-isforklift').checked;
    const propModel = document.getElementById('offset-form-prop').value.trim() || 'hei_prop_carrier_cargo_04b';

    postNUI('adminStartOffsetCalibration', {
      trailerModel: trailerModel,
      slotIndex: slotIndex,
      isForklift: isForklift,
      propModel: propModel
    });
  }

  // ============================================================
  // ABA 5: ECONOMIA & XP (LIVE SYNC)
  // ============================================================
  function renderEconomyTab() {
    const eco = adminData.economy || {};
    if (document.getElementById('eco-form-km-pay')) {
      document.getElementById('eco-form-km-pay').value = eco.base_payment_per_km || 18.5;
      document.getElementById('eco-form-km-xp').value = eco.base_xp_per_km || 5.0;
      document.getElementById('eco-form-adr-mult').value = eco.adr_multiplier || 1.45;
      document.getElementById('eco-form-fragile-mult').value = eco.fragile_bonus || 1.25;
      document.getElementById('eco-form-valuable-mult').value = eco.valuable_bonus || 1.35;
      document.getElementById('eco-form-penalty').value = eco.cargo_loss_penalty || 500;
    }
  }

  function saveEconomyForm() {
    const payload = {
      base_payment_per_km: parseFloat(document.getElementById('eco-form-km-pay').value) || 18.5,
      base_xp_per_km: parseFloat(document.getElementById('eco-form-km-xp').value) || 5.0,
      adr_multiplier: parseFloat(document.getElementById('eco-form-adr-mult').value) || 1.45,
      fragile_bonus: parseFloat(document.getElementById('eco-form-fragile-mult').value) || 1.25,
      valuable_bonus: parseFloat(document.getElementById('eco-form-valuable-mult').value) || 1.35,
      cargo_loss_penalty: parseFloat(document.getElementById('eco-form-penalty').value) || 500
    };

    postNUI('adminSaveEconomy', payload);
    adminData.economy = payload;
    alert('Configurações de Economia e XP salvas e transmitidas a todos os jogadores!');
  }

  // ============================================================
  // ABA 6: NPCS DESPACHANTES DINÂMICOS
  // ============================================================
  function renderNPCsTab() {
    const tbody = document.getElementById('admin-npcs-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const npcs = adminData.npcs || {};
    const keys = Object.keys(npcs);

    if (keys.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; padding: 24px; color: var(--admin-text-muted);">Nenhum NPC despachante adicionado. Crie um abaixo!</td></tr>`;
      return;
    }

    keys.forEach(k => {
      const n = npcs[k];
      const coords = n.coords ? (typeof n.coords === 'string' ? JSON.parse(n.coords) : n.coords) : {};
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>#${escapeHtml(n.npc_id || k)}</strong></td>
        <td>${escapeHtml(n.npc_name || 'Despachante')}</td>
        <td><span class="admin-badge admin-badge-heavy">${escapeHtml(n.npc_model || 's_m_m_trucker_01')}</span></td>
        <td style="font-family: monospace; font-size: 11px;">
          X: ${coords.x ? Number(coords.x).toFixed(1) : 0}, Y: ${coords.y ? Number(coords.y).toFixed(1) : 0}, Z: ${coords.z ? Number(coords.z).toFixed(1) : 0}
        </td>
        <td>
          <button class="admin-btn admin-btn-outline btn-tp-npc" data-x="${coords.x}" data-y="${coords.y}" data-z="${coords.z}" data-h="${coords.heading}" title="Teleportar"><i class="fas fa-location-arrow"></i> TP</button>
          <button class="admin-btn admin-btn-danger btn-del-npc" data-id="${k}" title="Remover"><i class="fas fa-trash"></i></button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-tp-npc').forEach(btn => {
      btn.addEventListener('click', function () {
        postNUI('adminTeleport', {
          coords: {
            x: parseFloat(this.getAttribute('data-x')),
            y: parseFloat(this.getAttribute('data-y')),
            z: parseFloat(this.getAttribute('data-z')),
            heading: parseFloat(this.getAttribute('data-h'))
          }
        });
      });
    });

    tbody.querySelectorAll('.btn-del-npc').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        if (confirm(`Remover NPC despachante #${id}?`)) {
          postNUI('adminDeleteNPC', { id: id });
          delete adminData.npcs[id];
          renderNPCsTab();
        }
      });
    });
  }

  function saveNPCForm() {
    const npcId = document.getElementById('npc-form-id').value.trim();
    if (!npcId) {
      alert('Informe o identificador do NPC (ex: dispatcher_paleto)!');
      return;
    }

    const coords = {
      x: parseFloat(document.getElementById('npc-form-x').value) || 0.0,
      y: parseFloat(document.getElementById('npc-form-y').value) || 0.0,
      z: parseFloat(document.getElementById('npc-form-z').value) || 0.0,
      heading: parseFloat(document.getElementById('npc-form-h').value) || 0.0
    };

    const payload = {
      npc_id: npcId,
      npc_name: document.getElementById('npc-form-name').value.trim() || 'Despachante Central',
      npc_model: document.getElementById('npc-form-model').value.trim() || 's_m_m_trucker_01',
      coords: coords,
      enable_target: document.getElementById('npc-form-target').checked ? 1 : 0
    };

    postNUI('adminSaveNPC', payload);
    adminData.npcs[npcId] = payload;
    renderNPCsTab();
    alert(`NPC #${npcId} salvo e spawnado no mapa com sucesso!`);
  }

  // ============================================================
  // UTILITÁRIO: CAPTURA DINÂMICA DE COORDENADAS
  // ============================================================
  function captureCoords(targetPrefix) {
    postNUI('adminCaptureCoords', {}).then(res => {
      if (res && res.coords) {
        const c = res.coords;
        if (targetPrefix === 'route-pickup') {
          document.getElementById('route-form-pickup-x').value = c.x.toFixed(2);
          document.getElementById('route-form-pickup-y').value = c.y.toFixed(2);
          document.getElementById('route-form-pickup-z').value = c.z.toFixed(2);
        } else if (targetPrefix === 'route-deliv') {
          document.getElementById('route-form-deliv-x').value = c.x.toFixed(2);
          document.getElementById('route-form-deliv-y').value = c.y.toFixed(2);
          document.getElementById('route-form-deliv-z').value = c.z.toFixed(2);
        } else if (targetPrefix === 'spawn') {
          document.getElementById('spawn-form-x').value = c.x.toFixed(2);
          document.getElementById('spawn-form-y').value = c.y.toFixed(2);
          document.getElementById('spawn-form-z').value = c.z.toFixed(2);
          document.getElementById('spawn-form-h').value = c.heading.toFixed(2);
        } else if (targetPrefix === 'npc') {
          document.getElementById('npc-form-x').value = c.x.toFixed(2);
          document.getElementById('npc-form-y').value = c.y.toFixed(2);
          document.getElementById('npc-form-z').value = c.z.toFixed(2);
          document.getElementById('npc-form-h').value = c.heading.toFixed(2);
        }
      }
    });
  }

  function escapeHtml(string) {
    if (!string) return '';
    return String(string)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Inicialização de Eventos do DOM
  document.addEventListener('DOMContentLoaded', function () {
    // Botão de fechar do cabeçalho
    const closeBtn = document.querySelector('.admin-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        closeAdminPanel();
        postNUI('adminClose', {});
      });
    }

    // Botões de alternância de abas
    document.querySelectorAll('.admin-tab-btn').forEach(btn => {
      btn.addEventListener('click', function () {
        const tab = this.getAttribute('data-tab');
        switchTab(tab);
      });
    });

    // Eventos de formulários
    const btnSaveRoute = document.getElementById('btn-save-route');
    if (btnSaveRoute) btnSaveRoute.addEventListener('click', saveRouteForm);

    const btnSaveSpawn = document.getElementById('btn-save-spawn');
    if (btnSaveSpawn) btnSaveSpawn.addEventListener('click', saveSpawnForm);

    const btnStartCalib = document.getElementById('btn-start-calibration');
    if (btnStartCalib) btnStartCalib.addEventListener('click', startCalibrationTool);

    const btnSaveEconomy = document.getElementById('btn-save-economy');
    if (btnSaveEconomy) btnSaveEconomy.addEventListener('click', saveEconomyForm);

    const btnSaveNPC = document.getElementById('btn-save-npc');
    if (btnSaveNPC) btnSaveNPC.addEventListener('click', saveNPCForm);

    // Eventos de captura de coordenadas
    const btnCapPickup = document.getElementById('btn-cap-pickup');
    if (btnCapPickup) btnCapPickup.addEventListener('click', () => captureCoords('route-pickup'));

    const btnCapDeliv = document.getElementById('btn-cap-deliv');
    if (btnCapDeliv) btnCapDeliv.addEventListener('click', () => captureCoords('route-deliv'));

    const btnCapSpawn = document.getElementById('btn-cap-spawn');
    if (btnCapSpawn) btnCapSpawn.addEventListener('click', () => captureCoords('spawn'));

    const btnCapNPC = document.getElementById('btn-cap-npc');
    if (btnCapNPC) btnCapNPC.addEventListener('click', () => captureCoords('npc'));
  });

})();
