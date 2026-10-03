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
    homologatedProps: [],
    defaultProps: []
  };

  let activeTab = 'routes';
  let routeFilter = 'all';
  let routeSearchQuery = '';
  let ecoFilter = 'all';
  let draggedSpawnId = null;

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
        restoreAdminPanel(item);
        break;
      case 'admin_update_offsets':
        if (item.offsets) {
          adminData.trailerOffsets = item.offsets;
          renderOffsetsTab();
        }
        break;
      case 'admin_spawn_coords_calibrated':
        if (item.coords) {
          const sx = document.getElementById('spawn-form-x');
          const sy = document.getElementById('spawn-form-y');
          const sz = document.getElementById('spawn-form-z');
          const sh = document.getElementById('spawn-form-h');
          if (sx) sx.value = item.coords.x;
          if (sy) sy.value = item.coords.y;
          if (sz) sz.value = item.coords.z;
          if (sh) sh.value = item.coords.heading;
        }
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
      adminData = {
        customRoutes: data.customRoutes || data.routes || {},
        spawns: data.spawns || {},
        trailerOffsets: data.trailerOffsets || data.offsets || {},
        npcs: data.npcs || {},
        economy: data.economy || {},
        homologatedProps: data.homologatedProps || [],
        defaultProps: data.defaultProps || []
      };
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

  function restoreAdminPanel(item) {
    const panel = document.getElementById('admin-panel');
    if (panel) {
      panel.style.display = 'flex';
    }

    // UX: Avança automaticamente para o próximo slot sequencial (ex: Slot 1 -> Slot 2)
    if (item && item.savedSlot && !item.isForklift) {
      const nextSlot = parseInt(item.savedSlot) + 1;
      const slotSelect = document.getElementById('offset-form-slot');
      if (slotSelect) {
        let exists = false;
        for (let i = 0; i < slotSelect.options.length; i++) {
          if (parseInt(slotSelect.options[i].value) === nextSlot) {
            slotSelect.selectedIndex = i;
            exists = true;
            break;
          }
        }
        if (!exists && nextSlot <= 12) {
          const opt = document.createElement('option');
          opt.value = nextSlot;
          opt.textContent = `Slot ${nextSlot} (Extra)`;
          slotSelect.appendChild(opt);
          slotSelect.value = nextSlot;
        }
      }
    }

    if (item && item.trailerModel) {
      const trailerInput = document.getElementById('offset-form-trailer');
      if (trailerInput) trailerInput.value = item.trailerModel;
    }

    const chkForklift = document.getElementById('offset-form-isforklift');
    const propInput = document.getElementById('offset-form-prop');
    const slotSelect = document.getElementById('offset-form-slot');
    if (item && item.isForklift) {
      if (chkForklift) chkForklift.checked = true;
      if (propInput) {
        propInput.value = 'forklift';
        propInput.disabled = true;
      }
      if (slotSelect) slotSelect.disabled = true;
    } else if (item && item.savedSlot) {
      if (chkForklift) chkForklift.checked = false;
      if (propInput) {
        propInput.value = 'hei_prop_carrier_cargo_04b';
        propInput.disabled = false;
      }
      if (slotSelect) slotSelect.disabled = false;
    }

    renderOffsetsTab();
    renderSpawnsTab();
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
  // ABA 1: ROTAS & CONTRATOS (COM FILTROS E BUSCA)
  // ============================================================
  function renderRoutesTab() {
    const tbody = document.getElementById('admin-routes-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    const routes = adminData.customRoutes || {};
    let entries = Object.keys(routes).map(k => ({ key: k, data: routes[k] }));

    // Filtro por tipo de trabalho
    if (routeFilter && routeFilter !== 'all') {
      entries = entries.filter(e => {
        const t = (e.data.type || e.data.job_type || 'freight').toLowerCase();
        return t === routeFilter;
      });
    }

    // Filtro por busca textual
    if (routeSearchQuery && routeSearchQuery.trim() !== '') {
      const q = routeSearchQuery.toLowerCase().trim();
      entries = entries.filter(e => {
        const name = (e.data.name || e.data.title || '').toLowerCase();
        const id = String(e.data.id || e.data.route_id || e.key).toLowerCase();
        return name.includes(q) || id.includes(q);
      });
    }

    if (entries.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center; padding: 24px; color: var(--admin-text-muted);">Nenhuma rota encontrada para o filtro selecionado.</td></tr>`;
      return;
    }

    entries.forEach(e => {
      const r = e.data;
      const k = e.key;
      const tr = document.createElement('tr');
      const jobType = (r.type || r.job_type || 'freight').toLowerCase();
      let badgeClass = 'admin-badge-freight';
      if (jobType === 'adr') badgeClass = 'admin-badge-adr';
      else if (jobType === 'quick') badgeClass = 'admin-badge-quick';
      else if (jobType === 'heavy') badgeClass = 'admin-badge-heavy';
      else if (jobType === 'carrier') badgeClass = 'admin-badge-carrier';

      const payment = r.base_payment || r.payment || 0;
      const xp = r.base_xp || r.xp || 0;
      const dist = r.distance || r.distance_km || 0;

      tr.innerHTML = `
        <td><strong>#${escapeHtml(r.id || r.route_id || k)}</strong></td>
        <td>${escapeHtml(r.name || r.title || 'Carga Sem Nome')}</td>
        <td><span class="admin-badge ${badgeClass}">${jobType.toUpperCase()}</span></td>
        <td>R$ ${Number(payment).toLocaleString()} <span style="color:var(--admin-primary)">(${xp} XP)</span></td>
        <td>${Number(dist).toFixed(1)} km (Lvl ${r.req_skill || r.required_level || 1})</td>
        <td>
          <button class="admin-btn admin-btn-outline btn-edit-route" data-id="${k}" title="Editar Rota"><i class="fas fa-edit"></i></button>
          <button class="admin-btn admin-btn-danger btn-del-route" data-id="${k}" title="Excluir Rota"><i class="fas fa-trash"></i></button>
        </td>
      `;
      tbody.appendChild(tr);
    });

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
          renderEconomyTab();
        }
      });
    });
  }

  function fillRouteForm(r) {
    if (!r) return;
    document.getElementById('route-form-id').value = r.id || r.route_id || '';
    document.getElementById('route-form-title').value = r.name || r.title || '';
    document.getElementById('route-form-type').value = r.type || r.job_type || 'freight';
    document.getElementById('route-form-prop').value = r.cargo_model || r.cargo_prop || 'hei_prop_carrier_cargo_04b';
    document.getElementById('route-form-payment').value = r.base_payment || r.payment || 2500;
    document.getElementById('route-form-xp').value = r.base_xp || r.xp || 150;
    document.getElementById('route-form-distance').value = r.distance || r.distance_km || 5.0;
    document.getElementById('route-form-level').value = r.req_skill || r.required_level || 1;

    const pCoords = r.pickup_coords ? (typeof r.pickup_coords === 'string' ? JSON.parse(r.pickup_coords) : r.pickup_coords) : {};
    document.getElementById('route-form-pickup-x').value = pCoords.x ? Number(pCoords.x).toFixed(2) : '';
    document.getElementById('route-form-pickup-y').value = pCoords.y ? Number(pCoords.y).toFixed(2) : '';
    document.getElementById('route-form-pickup-z').value = pCoords.z ? Number(pCoords.z).toFixed(2) : '';

    const dCoords = r.delivery_coords ? (typeof r.delivery_coords === 'string' ? JSON.parse(r.delivery_coords) : r.delivery_coords) : {};
    document.getElementById('route-form-deliv-x').value = dCoords.x ? Number(dCoords.x).toFixed(2) : '';
    document.getElementById('route-form-deliv-y').value = dCoords.y ? Number(dCoords.y).toFixed(2) : '';
    document.getElementById('route-form-deliv-z').value = dCoords.z ? Number(dCoords.z).toFixed(2) : '';

    document.getElementById('route-form-forklift').checked = (r.has_forklift == 1 || r.has_forklift === true);
    document.getElementById('route-form-adr').checked = (r.requires_adr == 1 || r.requires_adr === true || r.type === 'adr');
  }

  function saveRouteForm() {
    const routeId = document.getElementById('route-form-id').value.trim();
    if (!routeId) {
      alert('Informe um identificador único para a rota (ex: rota_porto_oleo).');
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
      id: routeId,
      route_id: routeId,
      name: document.getElementById('route-form-title').value.trim() || 'Carga Personalizada',
      title: document.getElementById('route-form-title').value.trim() || 'Carga Personalizada',
      type: document.getElementById('route-form-type').value,
      job_type: document.getElementById('route-form-type').value,
      cargo_model: document.getElementById('route-form-prop').value.trim() || 'hei_prop_carrier_cargo_04b',
      cargo_prop: document.getElementById('route-form-prop').value.trim() || 'hei_prop_carrier_cargo_04b',
      base_payment: parseInt(document.getElementById('route-form-payment').value) || 2500,
      payment: parseInt(document.getElementById('route-form-payment').value) || 2500,
      base_xp: parseInt(document.getElementById('route-form-xp').value) || 150,
      xp: parseInt(document.getElementById('route-form-xp').value) || 150,
      distance: parseFloat(document.getElementById('route-form-distance').value) || 5.0,
      distance_km: parseFloat(document.getElementById('route-form-distance').value) || 5.0,
      req_skill: parseInt(document.getElementById('route-form-level').value) || 1,
      required_level: parseInt(document.getElementById('route-form-level').value) || 1,
      pickup_coords: pickup,
      delivery_coords: delivery,
      has_forklift: document.getElementById('route-form-forklift').checked ? 1 : 0,
      requires_adr: document.getElementById('route-form-adr').checked ? 1 : 0
    };

    postNUI('adminSaveRoute', payload);
    adminData.customRoutes[routeId] = payload;
    renderRoutesTab();
    renderEconomyTab();
    alert(`Rota #${routeId} salva com sucesso e sincronizada em tempo real!`);
  }

  // ============================================================
  // ABA 2: SPAWNS DINÂMICOS (PASTAS & DRAG-AND-DROP)
  // ============================================================
  function renderSpawnsTab() {
    const container = document.getElementById('admin-spawns-folders-container');
    const folderSelect = document.getElementById('spawn-form-folder');
    if (!container) return;
    container.innerHTML = '';

    const spawns = adminData.spawns || {};
    const spawnsList = Object.keys(spawns).map(k => {
      const s = spawns[k];
      s.key = k;
      s.folder_name = s.folder_name || 'Geral';
      return s;
    });

    // Mapeia todas as pastas existentes
    const folders = {};
    folders['Geral'] = [];

    spawnsList.forEach(s => {
      const fName = s.folder_name || 'Geral';
      if (!folders[fName]) folders[fName] = [];
      folders[fName].push(s);
    });

    // Atualiza opções no select do formulário
    if (folderSelect) {
      const currentSelected = folderSelect.value;
      folderSelect.innerHTML = '';
      Object.keys(folders).forEach(fName => {
        const opt = document.createElement('option');
        opt.value = fName;
        opt.textContent = fName;
        folderSelect.appendChild(opt);
      });
      if (currentSelected && folders[currentSelected]) {
        folderSelect.value = currentSelected;
      }
    }

    // Renderiza cada pasta como container de Drag-and-Drop
    Object.keys(folders).forEach(folderName => {
      const fList = folders[folderName];
      const folderCard = document.createElement('div');
      folderCard.className = 'admin-folder-card';
      folderCard.setAttribute('data-folder', folderName);

      const isDefault = folderName === 'Geral';
      folderCard.innerHTML = `
        <div class="admin-folder-header">
          <div class="admin-folder-title">
            <i class="fas fa-folder"></i>
            <span>${escapeHtml(folderName)}</span>
            <span class="admin-folder-badge">${fList.length} pontos</span>
          </div>
          <div style="display:flex; gap:6px; align-items:center;">
            ${!isDefault ? `<button class="admin-btn admin-btn-danger btn-del-folder" data-folder="${escapeHtml(folderName)}" style="padding: 2px 8px; font-size:10px;" title="Excluir Pasta"><i class="fas fa-trash"></i></button>` : ''}
          </div>
        </div>
        <div class="admin-folder-items" data-folder="${escapeHtml(folderName)}">
          ${fList.length === 0 ? `<div style="color:var(--admin-text-muted); font-size:11px; padding:6px; text-align:center;">Pasta vazia. Arraste pontos de spawn para cá.</div>` : ''}
        </div>
      `;

      const itemsContainer = folderCard.querySelector('.admin-folder-items');

      fList.forEach(s => {
        const coords = s.coords ? (typeof s.coords === 'string' ? JSON.parse(s.coords) : s.coords) : {};
        const row = document.createElement('div');
        row.className = 'admin-spawn-row';
        row.setAttribute('draggable', 'true');
        row.setAttribute('data-id', s.key || s.id || s.spawn_id);

        row.innerHTML = `
          <div style="display:flex; align-items:center; gap:10px;">
            <i class="fas fa-grip-vertical" style="color:var(--admin-text-muted); cursor:grab;"></i>
            <strong>#${escapeHtml(s.key || s.id || s.spawn_id)}</strong>
            <span style="color:#fff;">${escapeHtml(s.name || s.spawn_name || 'Ponto')}</span>
            <span class="admin-badge admin-badge-quick">${escapeHtml((s.spawn_type || 'truck').toUpperCase())}</span>
          </div>
          <div style="font-family:monospace; font-size:11px; color:var(--admin-text-muted);">
            X:${coords.x ? Number(coords.x).toFixed(1) : 0} Y:${coords.y ? Number(coords.y).toFixed(1) : 0} Z:${coords.z ? Number(coords.z).toFixed(1) : 0} H:${coords.heading ? Number(coords.heading).toFixed(0) : 0}°
          </div>
          <div style="display:flex; gap:6px;">
            <button class="admin-btn admin-btn-outline btn-tp-spawn" data-x="${coords.x}" data-y="${coords.y}" data-z="${coords.z}" data-h="${coords.heading}" style="padding: 3px 8px; font-size:11px;" title="Teleportar"><i class="fas fa-location-arrow"></i> TP</button>
            <button class="admin-btn admin-btn-danger btn-del-spawn" data-id="${s.key || s.id || s.spawn_id}" style="padding: 3px 8px; font-size:11px;" title="Excluir"><i class="fas fa-trash"></i></button>
          </div>
        `;

        // Eventos Drag-and-Drop no item
        row.addEventListener('dragstart', function (e) {
          draggedSpawnId = this.getAttribute('data-id');
          this.classList.add('dragging');
          e.dataTransfer.setData('text/plain', draggedSpawnId);
        });

        row.addEventListener('dragend', function () {
          this.classList.remove('dragging');
          draggedSpawnId = null;
        });

        itemsContainer.appendChild(row);
      });

      // Eventos Drag-and-Drop na Pasta
      folderCard.addEventListener('dragover', function (e) {
        e.preventDefault();
        folderCard.classList.add('drag-over');
      });

      folderCard.addEventListener('dragleave', function () {
        folderCard.classList.remove('drag-over');
      });

      folderCard.addEventListener('drop', function (e) {
        e.preventDefault();
        folderCard.classList.remove('drag-over');
        const targetFolder = this.getAttribute('data-folder');
        if (draggedSpawnId && targetFolder) {
          const spawnObj = adminData.spawns[draggedSpawnId];
          if (spawnObj && spawnObj.folder_name !== targetFolder) {
            spawnObj.folder_name = targetFolder;
            postNUI('adminMoveSpawnFolder', {
              spawn_id: draggedSpawnId,
              folder_name: targetFolder
            });
            renderSpawnsTab();
          }
        }
      });

      container.appendChild(folderCard);
    });

    // Listeners de Teleporte
    container.querySelectorAll('.btn-tp-spawn').forEach(btn => {
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

    // Listeners de Exclusão de Spawn
    container.querySelectorAll('.btn-del-spawn').forEach(btn => {
      btn.addEventListener('click', function () {
        const id = this.getAttribute('data-id');
        if (confirm(`Excluir o spawn #${id}?`)) {
          postNUI('adminDeleteSpawn', { id: id });
          delete adminData.spawns[id];
          renderSpawnsTab();
        }
      });
    });

    // Listeners de Exclusão de Pasta
    container.querySelectorAll('.btn-del-folder').forEach(btn => {
      btn.addEventListener('click', function () {
        const f = this.getAttribute('data-folder');
        if (confirm(`Excluir a pasta "${f}"? Todos os pontos contidos nela serão movidos para "Geral".`)) {
          postNUI('adminDeleteSpawnFolder', { folder_name: f });
          Object.values(adminData.spawns).forEach(s => {
            if (s.folder_name === f) s.folder_name = 'Geral';
          });
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
      id: spawnId,
      spawn_id: spawnId,
      name: document.getElementById('spawn-form-name').value.trim() || 'Ponto de Spawn',
      spawn_name: document.getElementById('spawn-form-name').value.trim() || 'Ponto de Spawn',
      spawn_type: document.getElementById('spawn-form-type').value,
      folder_name: document.getElementById('spawn-form-folder').value || 'Geral',
      coords: coords
    };

    postNUI('adminSaveSpawn', payload);
    adminData.spawns[spawnId] = payload;
    renderSpawnsTab();
    alert(`Ponto de spawn #${spawnId} gravado com sucesso!`);
  }

  // ============================================================
  // ABA 3: CARGAS & PROPS (HOMOLOGAÇÃO & VINCULAÇÃO)
  // ============================================================
  function renderPropsTab() {
    const grid = document.getElementById('admin-props-grid');
    if (!grid) return;
    grid.innerHTML = '';

    const homologated = adminData.homologatedProps || [];
    const defaultList = [
      { prop_model: 'hei_prop_carrier_cargo_04b', label: 'Contêiner Grande Seco', category: 'dry', offset_z: 0.0 },
      { prop_model: 'm24_1_prop_m24_1_carrier_cargo_04a', label: 'Carga Marítima M24', category: 'dry', offset_z: 0.0 },
      { prop_model: 'prop_boxpile_02b', label: 'Pilhas de Caixas Frágeis', category: 'fragile', offset_z: 0.0 },
      { prop_model: 'prop_boxpile_06a', label: 'Caixas de Alta Densidade', category: 'dry', offset_z: 0.0 },
      { prop_model: 'prop_barrel_exp_01a', label: 'Barris Explosivos ADR', category: 'adr', offset_z: 0.0 },
      { prop_model: 'prop_rub_crate_01', label: 'Carga de Valiosos Blindada', category: 'valuable', offset_z: 0.0 },
      { prop_model: 'prop_wood_pallet_01', label: 'Palete de Madeira Padrão', category: 'dry', offset_z: 0.0 }
    ];

    // Mescla padrões com os salvos do banco
    const map = {};
    defaultList.forEach(p => { map[p.prop_model] = p; });
    homologated.forEach(p => { map[p.prop_model] = p; });

    Object.values(map).forEach(p => {
      const card = document.createElement('div');
      card.className = 'admin-card';
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = '8px';

      const cat = (p.category || 'dry').toLowerCase();
      let badgeClass = 'admin-badge-freight';
      if (cat === 'adr') badgeClass = 'admin-badge-adr';
      else if (cat === 'fragile') badgeClass = 'admin-badge-quick';
      else if (cat === 'valuable') badgeClass = 'admin-badge-carrier';
      else if (cat === 'heavy') badgeClass = 'admin-badge-heavy';

      card.innerHTML = `
        <div class="admin-card-header" style="margin-bottom: 4px;">
          <strong style="color:var(--admin-primary); font-size:13px;"><i class="fas fa-cube"></i> ${escapeHtml(p.label || p.prop_model)}</strong>
          <span class="admin-badge ${badgeClass}">${cat.toUpperCase()}</span>
        </div>
        <div style="font-size:11px; color:var(--admin-text-muted); font-family:monospace;">
          Modelo: <span style="color:#fff;">${escapeHtml(p.prop_model)}</span> | Offset Z: ${Number(p.offset_z || 0).toFixed(2)}
        </div>
        <div style="display:flex; justify-content:space-between; gap:8px; margin-top:8px;">
          <button class="admin-btn admin-btn-danger btn-del-prop" data-model="${escapeHtml(p.prop_model)}" style="padding: 4px 10px; font-size:11px;"><i class="fas fa-trash"></i></button>
          <button class="admin-btn admin-btn-outline btn-use-prop" data-prop="${escapeHtml(p.prop_model)}" style="padding: 4px 12px; font-size:11px;">Usar no Trailer</button>
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

    grid.querySelectorAll('.btn-del-prop').forEach(btn => {
      btn.addEventListener('click', function () {
        const model = this.getAttribute('data-model');
        if (confirm(`Remover a homologação do modelo "${model}"?`)) {
          postNUI('adminDeleteHomologatedProp', { prop_model: model });
          adminData.homologatedProps = adminData.homologatedProps.filter(p => p.prop_model !== model);
          renderPropsTab();
        }
      });
    });
  }

  function saveHomologatedProp() {
    const model = document.getElementById('prop-form-model').value.trim();
    if (!model) {
      alert('Informe o modelo 3D do prop (ex: prop_boxpile_07d).');
      return;
    }

    const payload = {
      prop_model: model,
      label: document.getElementById('prop-form-label').value.trim() || model,
      category: document.getElementById('prop-form-category').value,
      offset_z: parseFloat(document.getElementById('prop-form-offsetz').value) || 0.0
    };

    postNUI('adminSaveHomologatedProp', payload);
    adminData.homologatedProps.push(payload);
    renderPropsTab();
    alert(`Modelo "${model}" homologado com sucesso! Já disponível como carga.`);
  }

  // ============================================================
  // ABA 4: CALIBRAÇÃO VISUAL 3D DE OFFSETS (COM DELETE E LABEL)
  // ============================================================
  function renderOffsetsTab() {
    const listContainer = document.getElementById('admin-offsets-list');
    if (!listContainer) return;
    listContainer.innerHTML = '';

    const offsets = adminData.trailerOffsets || {};
    const keys = Object.keys(offsets);

    if (keys.length === 0) {
      listContainer.innerHTML = `<p style="color:var(--admin-text-muted); font-size:12px;">Nenhum offset customizado salvo em banco ainda.</p>`;
      return;
    }

    keys.forEach(model => {
      const item = offsets[model];
      let palletSlots = [];
      if (item.pallets) {
        const seen = new Set();
        Object.keys(item.pallets).forEach(k => {
          const num = parseInt(k);
          if (!isNaN(num) && !seen.has(num)) {
            seen.add(num);
            palletSlots.push({ slot: num, data: item.pallets[k] });
          }
        });
        palletSlots.sort((a, b) => a.slot - b.slot);
      }

      const card = document.createElement('div');
      card.className = 'admin-card';
      card.innerHTML = `
        <div class="admin-card-header">
          <span class="admin-card-title"><i class="fas fa-truck"></i> Reboque: <strong>${escapeHtml(model.toUpperCase())}</strong></span>
          <button class="admin-btn admin-btn-outline btn-select-trailer" data-model="${escapeHtml(model)}" style="padding: 4px 10px; font-size: 11px;"><i class="fas fa-edit"></i> Usar Modelo</button>
        </div>
        <div style="font-size:12px; line-height: 1.6;">
          <div style="margin-bottom: 8px;"><strong>Slots de Paletes Calibrados:</strong></div>
          <div style="display:flex; flex-direction:column; gap:6px; margin-bottom: 10px;">
            ${palletSlots.length > 0 ? palletSlots.map(s => `
              <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.03); padding:4px 10px; border-radius:4px;">
                <span>
                  <strong style="color:var(--admin-primary)">Slot ${s.slot}</strong> 
                  ${s.data.label ? `<span style="color:#fff;">(${escapeHtml(s.data.label)})</span>` : ''}
                  <span style="font-family:monospace; color:var(--admin-text-muted); font-size:11px;"> [X:${Number(s.data.x).toFixed(2)}, Y:${Number(s.data.y).toFixed(2)}, Z:${Number(s.data.z).toFixed(2)}, H:${Number(s.data.heading || 0).toFixed(0)}°]</span>
                </span>
                <button class="admin-btn admin-btn-danger btn-del-offset" data-trailer="${escapeHtml(model)}" data-slot="${s.slot}" data-fork="0" style="padding:2px 7px; font-size:10px;" title="Excluir Offset"><i class="fas fa-trash"></i></button>
              </div>
            `).join('') : '<span style="color:var(--admin-text-muted)">Nenhum slot cadastrado</span>'}
          </div>
          <div>
            <strong>Empilhadeira Traseira:</strong> 
            ${item.forklift ? `
              <span style="color:var(--admin-primary)">[X:${Number(item.forklift.x).toFixed(2)}, Y:${Number(item.forklift.y).toFixed(2)}, Z:${Number(item.forklift.z).toFixed(2)}]</span>
              <button class="admin-btn admin-btn-danger btn-del-offset" data-trailer="${escapeHtml(model)}" data-slot="7" data-fork="1" style="padding:2px 7px; font-size:10px; margin-left:8px;" title="Excluir Forklift"><i class="fas fa-trash"></i></button>
            ` : '<span style="color:var(--admin-text-muted)">Padrão de Fábrica</span>'}
          </div>
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

    listContainer.querySelectorAll('.btn-del-offset').forEach(btn => {
      btn.addEventListener('click', function () {
        const trailer = this.getAttribute('data-trailer');
        const slot = parseInt(this.getAttribute('data-slot'));
        const isFork = this.getAttribute('data-fork') === '1';
        if (confirm(`Excluir offset do trailer "${trailer}" (${isFork ? 'Empilhadeira' : 'Slot ' + slot})?`)) {
          postNUI('adminDeleteTrailerOffset', {
            trailerModel: trailer,
            slotIndex: slot,
            isForklift: isFork
          });
          if (adminData.trailerOffsets[trailer]) {
            if (isFork) {
              adminData.trailerOffsets[trailer].forklift = null;
            } else if (adminData.trailerOffsets[trailer].pallets) {
              delete adminData.trailerOffsets[trailer].pallets[slot];
              delete adminData.trailerOffsets[trailer].pallets[String(slot)];
            }
          }
          renderOffsetsTab();
        }
      });
    });
  }

  function startCalibrationTool() {
    const trailerModel = document.getElementById('offset-form-trailer').value.trim() || 'trailers2';
    const isForklift = document.getElementById('offset-form-isforklift').checked;
    const slotIndex = isForklift ? 7 : (parseInt(document.getElementById('offset-form-slot').value) || 1);
    const propModel = isForklift ? 'forklift' : (document.getElementById('offset-form-prop').value.trim() || 'hei_prop_carrier_cargo_04b');
    const label = document.getElementById('offset-form-label').value.trim();

    postNUI('adminStartOffsetCalibration', {
      trailerModel: trailerModel,
      slotIndex: slotIndex,
      isForklift: isForklift,
      propModel: propModel,
      label: label
    });
  }

  // ============================================================
  // ABA 5: ECONOMIA & XP (LISTAGEM GLOBAL & EDIÇÃO INLINE)
  // ============================================================
  function renderEconomyTab() {
    const tbody = document.getElementById('admin-eco-routes-tbody');
    if (tbody) {
      tbody.innerHTML = '';
      const routes = adminData.customRoutes || {};
      let entries = Object.keys(routes).map(k => ({ key: k, data: routes[k] }));

      if (ecoFilter && ecoFilter !== 'all') {
        entries = entries.filter(e => {
          const t = (e.data.type || e.data.job_type || 'freight').toLowerCase();
          return t === ecoFilter;
        });
      }

      if (entries.length === 0) {
        tbody.innerHTML = `<tr><td colspan="7" style="text-align:center; padding: 18px; color: var(--admin-text-muted);">Nenhuma rota encontrada para este tipo.</td></tr>`;
      } else {
        entries.forEach(e => {
          const r = e.data;
          const k = e.key;
          const tr = document.createElement('tr');
          const jobType = (r.type || r.job_type || 'freight').toLowerCase();
          let badgeClass = 'admin-badge-freight';
          if (jobType === 'adr') badgeClass = 'admin-badge-adr';
          else if (jobType === 'quick') badgeClass = 'admin-badge-quick';
          else if (jobType === 'heavy') badgeClass = 'admin-badge-heavy';
          else if (jobType === 'carrier') badgeClass = 'admin-badge-carrier';

          const payment = r.base_payment || r.payment || 2500;
          const xp = r.base_xp || r.xp || 150;
          const dist = r.distance || r.distance_km || 5.0;

          tr.innerHTML = `
            <td><strong>#${escapeHtml(r.id || r.route_id || k)}</strong></td>
            <td>${escapeHtml(r.name || r.title || 'Carga')}</td>
            <td><span class="admin-badge ${badgeClass}">${jobType.toUpperCase()}</span></td>
            <td>${Number(dist).toFixed(1)} km</td>
            <td>
              <input type="number" class="admin-inline-input eco-route-pay" data-id="${k}" value="${payment}">
            </td>
            <td>
              <input type="number" class="admin-inline-input eco-route-xp" data-id="${k}" value="${xp}">
            </td>
            <td>
              <button class="admin-btn admin-btn-primary btn-save-route-eco" data-id="${k}" style="padding: 4px 10px; font-size:11px;"><i class="fas fa-save"></i> Salvar</button>
            </td>
          `;
          tbody.appendChild(tr);
        });

        tbody.querySelectorAll('.btn-save-route-eco').forEach(btn => {
          btn.addEventListener('click', function () {
            const id = this.getAttribute('data-id');
            const row = this.closest('tr');
            const newPay = parseInt(row.querySelector('.eco-route-pay').value) || 2500;
            const newXp = parseInt(row.querySelector('.eco-route-xp').value) || 150;

            if (adminData.customRoutes[id]) {
              adminData.customRoutes[id].base_payment = newPay;
              adminData.customRoutes[id].payment = newPay;
              adminData.customRoutes[id].base_xp = newXp;
              adminData.customRoutes[id].xp = newXp;

              postNUI('adminSaveRoute', adminData.customRoutes[id]);
              alert(`Valores da rota #${id} atualizados para R$ ${newPay.toLocaleString()} e ${newXp} XP!`);
            }
          });
        });
      }
    }

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
    alert('Multiplicadores globais atualizados e sincronizados com todos os jogadores!');
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
      enable_target: document.getElementById('npc-form-target') ? (document.getElementById('npc-form-target').checked ? 1 : 0) : 1
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

  // ============================================================
  // INICIALIZAÇÃO DE EVENTOS DO DOM
  // ============================================================
  document.addEventListener('DOMContentLoaded', function () {
    // Fechar botão
    const closeBtn = document.querySelector('.admin-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        closeAdminPanel();
        postNUI('adminClose', {});
      });
    }

    // Toggle empilhadeira no offset
    const chkForklift = document.getElementById('offset-form-isforklift');
    const propInput = document.getElementById('offset-form-prop');
    const slotSelect = document.getElementById('offset-form-slot');
    if (chkForklift && propInput) {
      chkForklift.addEventListener('change', () => {
        if (chkForklift.checked) {
          propInput.value = 'forklift';
          propInput.disabled = true;
          if (slotSelect) slotSelect.disabled = true;
        } else {
          propInput.value = 'hei_prop_carrier_cargo_04b';
          propInput.disabled = false;
          if (slotSelect) slotSelect.disabled = false;
        }
      });
    }

    // Alternância de abas
    document.querySelectorAll('.admin-tab-btn').forEach(btn => {
      btn.addEventListener('click', function () {
        const tab = this.getAttribute('data-tab');
        switchTab(tab);
      });
    });

    // Filtros por categoria na aba de rotas
    const routesFilterBar = document.getElementById('routes-filter-bar');
    if (routesFilterBar) {
      routesFilterBar.querySelectorAll('.admin-filter-btn').forEach(btn => {
        btn.addEventListener('click', function () {
          routesFilterBar.querySelectorAll('.admin-filter-btn').forEach(b => b.classList.remove('active'));
          this.classList.add('active');
          routeFilter = this.getAttribute('data-filter') || 'all';
          renderRoutesTab();
        });
      });
    }

    // Campo de busca de rotas
    const routesSearchInput = document.getElementById('routes-search-input');
    if (routesSearchInput) {
      routesSearchInput.addEventListener('input', function () {
        routeSearchQuery = this.value || '';
        renderRoutesTab();
      });
    }

    // Filtros por categoria na aba de economia
    const ecoFilterBar = document.getElementById('eco-filter-bar');
    if (ecoFilterBar) {
      ecoFilterBar.querySelectorAll('.admin-filter-btn').forEach(btn => {
        btn.addEventListener('click', function () {
          ecoFilterBar.querySelectorAll('.admin-filter-btn').forEach(b => b.classList.remove('active'));
          this.classList.add('active');
          ecoFilter = this.getAttribute('data-filter') || 'all';
          renderEconomyTab();
        });
      });
    }

    // Botões de formulário
    const btnSaveRoute = document.getElementById('btn-save-route');
    if (btnSaveRoute) btnSaveRoute.addEventListener('click', saveRouteForm);

    const btnSaveSpawn = document.getElementById('btn-save-spawn');
    if (btnSaveSpawn) btnSaveSpawn.addEventListener('click', saveSpawnForm);

    const btnStartCalib = document.getElementById('btn-start-calibration');
    if (btnStartCalib) btnStartCalib.addEventListener('click', startCalibrationTool);

    const btnSaveHomolog = document.getElementById('btn-save-homologated-prop');
    if (btnSaveHomolog) btnSaveHomolog.addEventListener('click', saveHomologatedProp);

    const btnSaveEconomy = document.getElementById('btn-save-economy');
    if (btnSaveEconomy) btnSaveEconomy.addEventListener('click', saveEconomyForm);

    const btnSaveNPC = document.getElementById('btn-save-npc');
    if (btnSaveNPC) btnSaveNPC.addEventListener('click', saveNPCForm);

    // Botão de Nova Pasta de Spawn
    const btnNewFolder = document.getElementById('btn-new-spawn-folder');
    if (btnNewFolder) {
      btnNewFolder.addEventListener('click', function () {
        const folderName = prompt('Nome da nova pasta de spawns:');
        if (folderName && folderName.trim() !== '') {
          const clean = folderName.trim();
          const folderSelect = document.getElementById('spawn-form-folder');
          if (folderSelect) {
            let exists = false;
            for (let i = 0; i < folderSelect.options.length; i++) {
              if (folderSelect.options[i].value === clean) exists = true;
            }
            if (!exists) {
              const opt = document.createElement('option');
              opt.value = clean;
              opt.textContent = clean;
              folderSelect.appendChild(opt);
              folderSelect.value = clean;
            }
          }
          alert(`Pasta "${clean}" criada!`);
        }
      });
    }

    // Botão de Gizmo para Coordenadas de Spawn
    const btnGizmoSpawn = document.getElementById('btn-gizmo-spawn');
    if (btnGizmoSpawn) {
      btnGizmoSpawn.addEventListener('click', function () {
        const sType = document.getElementById('spawn-form-type').value || 'truck';
        const sModel = document.getElementById('spawn-form-model').value.trim() || '';
        postNUI('adminStartSpawnGizmo', {
          spawn_type: sType,
          model: sModel
        });
      });
    }

    // Botão de Teste / Preview de Spawns da Área
    const btnPreviewSpawns = document.getElementById('btn-preview-spawns');
    if (btnPreviewSpawns) {
      btnPreviewSpawns.addEventListener('click', function () {
        const spawnsList = Object.values(adminData.spawns || {});
        if (spawnsList.length === 0) {
          alert('Nenhum ponto de spawn cadastrado para testar.');
          return;
        }
        postNUI('adminStartPreview', { spawns: spawnsList });
      });
    }

    // Botões de captura de coordenadas
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
